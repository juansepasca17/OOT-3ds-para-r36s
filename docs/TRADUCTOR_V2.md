# OOT3D R36S — Plan v2 (traductor v2 + sacrificios aprobados)

**Documento de traspaso.** Contiene todo lo necesario para retomar el trabajo en otra sesión sin
re-investigar: estado exacto, decisiones del usuario, tareas ordenadas con pasos, criterios de
aceptación, comandos y trampas conocidas. Última actualización: **2026-10-26 ~11:00**.

---

## 0. Estado en una mirada

| Qué | Dónde | Estado |
|---|---|---|
| **Versión jugable** | Rama **`estable`** = tag **`v1.2.0`**; en la SD: `Ports → OOT3D v1.2.0` | **14,3 fps** de lógica (69,8 ms), HUD y menú Fn visibles |
| Desarrollo | Rama `main` | v1.1.0 + coma flotante rápida (exacta, sin efecto medible) + herramientas + debug menú |
| Límite actual | CPU de la consola (hilo principal) | Código del juego traducido ~38 %, frontend PICA ~9 % (+5 % en render) |
| Binario en el servidor | `work/devserver/files/oot3d_r36s-menu.gz` | Build de depuración del menú Fn (C1), **aún no probado** |
| Consola | Agente "OOT3D Dev" actualizado (bench/perfrec/reintentos) | Último trabajo: 007-vfp |

### Decisiones del usuario (no volver a preguntar)

- **D1** frontend PICA en otro núcleo → **sí**, activado.
- **D2** audio más simple → **sí, activado por defecto** (como el port de Banjo-Kazooie para R36S).
  *Duda menor:* el usuario escribió "sobretodo el de la música que si no me agrada demasiado"; se
  interpretó "activado por defecto". Si al probarlo no le gusta, se apaga desde el menú.
- **D3** preparar el dibujo 1 de cada 2 frames → **sí, activado por defecto**.
- **D1–D3 deben poder desactivarse desde el menú Fn** → hace falta arreglar el menú (**C1**) primero.
- Sacrificios futuros no listados aquí: anotarlos en `docs/PENDIENTE_CONFIRMAR.md` y preguntar.
- Ramas: `estable` = lo jugable; `main` = desarrollo. Publicar en `estable` solo versiones medidas.

---

## 1. Orden de trabajo (siguiente sesión)

| # | Tarea | Ganancia | Esfuerzo | Depende de |
|---|---|---|---|---|
| 1 | **C1** Menú Fn visible en GLES | — | Bajo–medio | — |
| 2 | **C1b** Interruptores D1/D2/D3 en el menú (+ persistencia en config) | — | Bajo | C1 |
| 3 | **D3** Dibujo 1 de cada 2 frames | **15–25 %** | Medio | C1b |
| 4 | **D2** Audio más simple | 1–3 % | Bajo | C1b |
| 5 | **D1** Frontend PICA en otro núcleo | 5–9 % | Medio–alto | — |
| 6 | Publicar **v1.2.0** (D1–D3 + menú) en `estable` tras A/B en consola | — | Bajo | 1–5 |
| 7 | **A5** Benchmark x86 determinista | — | ✅ Hecho (DSP sin inicializar; `scripts/wsl/det_run.sh`) | — |
| 8 | **A4** Banco diferencial por función | — | Medio | A5 opcional |
| 9 | **T1→T3→T2→T7→T4** Traductor v2 | 15–30 % | Alto | A4 |

Estimación: v1.2.0 ≈ **15–17 fps**; con traductor v2 ≈ **18–22 fps**.

---

## 2. Tareas detalladas

### C1 — Menú Fn invisible en GLES

- **Síntoma:** Fn abre el menú (log `[menu] drawing 565 primitives…`), pero en la consola no se ve.
- **Ruta del dibujo:**
  - `oot3d_native_a32_window_frame.cpp` (~línea 585) → `inGameMenu.BuildPresentation(1280/3, 240)` →
    `n64UiRenderer.Render(…, N64UiCanvasMode::Widescreen16x9, …)` dentro de `renderStream.Submit`.
  - `tools/oot3d/ui_n64/oot3d_n64_ui_renderer.cpp::Render` → `PrepareUiOverlay(viewport)` + `DrawUiTriangles`
    (implementación GL en el backend OpenGL).
- **Hipótesis, por orden:**
  1. El overlay de UI se dibuja en un FBO o pase que luego tapa el blit de scanout (`pica_scanout`) o
     la presentación del "topscreen".
  2. Viewport o scissor del lienzo panorámico fuera de pantalla a 640×480 (4:3).
  3. Estado GL que difiere en GLES: blend, depth test o un VAO que no se restablece.
- **Herramienta ya añadida:** la variable `OOT3D_MENU_OPEN_AT_FRAME=N` abre el menú en el N-ésimo
  update, sin mando.
- **Prueba en el PC:**
  - Usar `scripts/wsl/qemu_smoke.sh` con `EXTRA_ARGS="--screenshot /tmp/menu.png --width 640 --height 480"`,
    `FRAMES=60` y `OOT3D_MENU_OPEN_AT_FRAME=30`. El binario es `work/dist-pgo-sw/oot3d_r36s`,
    construido con `console_build.sh menu`.
  - Si en qemu (Mesa) se ve y en Mali no, es un problema de estado GL o del driver: probar en la consola
    con un trabajo que use `--screenshot`.
- **Hecho cuando:** el menú se ve en la consola y se navega con el mando.

### C1b — Interruptores en el menú

- Añadir filas en `InGameMenu::BuildGameTab` (o una pestaña "Rendimiento"). Seguir el patrón de
  `ExtendedDrawDistance` (~línea 343), que usa una lambda getter/setter.
- Persistir en `config/oot3d_native_game.json`, con estos valores por defecto: D1 activado, D2
  activado, D3 activado.
- **Textos en español:** "Dibujo a medio ritmo (más fps)", "Audio simplificado (más fps)" y
  "Dibujo en paralelo".

### D3 — Preparar el dibujo 1 de cada 2 frames

- **Candidato concreto:** `Gameplay_Draw` en **0x002E25F0** (3024368, en `whole_aot_functions.json`).
  También existen `GameState_Update` (0x416F14) y `Graph_ThreadEntry` (0x416208).
- **Idea:**
  - En los frames impares, saltarse la llamada a `Gameplay_Draw`: hacer que retorne al instante con un
    hook, como `ApplyNativeActorVisibilityHook` o `ExecuteProductTopScreenHook`, que ya existen.
  - Repetir en pantalla el último frame presentado.
- **Riesgo principal:** que la presentación espere un display-transfer o una lista de comandos que
  no llega, lo que daría pantalla negra o un cuelgue. Opciones:
  - (a) Mantener el último framebuffer y saltarse también el `GSP` de ese frame.
  - (b) Saltarse solo la parte de actores y CMB (`CmbRenderer_*`, `MeshCommandPacket_*`).
- **Medir:** con `bench` en la consola, D3 activado frente a desactivado. Verificar a ojo que no
  parpadee, con capturas `--screenshot-sequence`.

### D2 — Audio más simple

- **Dónde:** `AudioCore` (HLE DSP): `AudioInterp::Linear`, `Source::MixInto`, `DecodeADPCM`.
- **Opciones:** interpolación "none" en vez de lineal; mezclar a 16 kHz en vez de 32 kHz, y luego
  duplicar muestras.
- **Medir con audio activado:** el benchmark usa `--disable-audio`; quitar ese argumento en el trabajo.

### D1 — Frontend PICA en otro núcleo

- **Hoy:** `SubmitGspCommand`, `BuildOot3dPicaCanonicalDrawIdentity` y `ApplyShaderRegisterSideEffects`
  corren en el hilo principal (~9 %).
- **Idea:** encolar los paquetes GSP crudos y procesarlos en un hilo propio antes del hilo de render.
  Hay que respetar `FlushNativeDependencies` (síncrono: copias que el juego espera).

### A5 — Benchmark x86 determinista

- **Causa probable de la no-determinismo:** `compare_x86.sh` arranca desde cero, con una savedata vacía.
  El proyecto original consigue huellas idénticas con un **checkpoint** + `--load-state` y
  `OOT3D_GRAPHICS_FRAME_RATE=Uncapped`; ver `scripts/linux/benchmark-switch-opengl.sh`.
- **Pasos:**
  1. Correr x86 con `--save-state-frame 3000 --save-state /root/oot3d/work/ckpt.oot3dsav`.
  2. `compare_x86.sh` con `--load-state ckpt` + `Uncapped`.
  3. Correr 2 veces el mismo binario: huellas iguales = listo.
- El reloj guest es virtual (`mSystemTicks` en `oot3d_native_a32_ctr_host.cpp`), así que es
  determinista por diseño.

### A4 — Banco diferencial por función

- **Objetivo:** un binario x86 con el código generado viejo y el nuevo.
  - Compilar el viejo con `-DGeneratedWholeAot=GeneratedWholeAotRef` (renombra el espacio de nombres).
  - Ejecutar cada función desde estados capturados y comparar R0–R15, NZCV, FPSCR y las escrituras a
    memoria (hay infraestructura: `mTraceWriteFingerprint` / `RecordTracedWrite` en `oot3d_native_a32_memory.h`).
- **Alternativa más barata:** A5 + `compare_block_traces.py` (ya existe) para encontrar el primer bloque
  divergente.

### T1–T7 — Traductor v2 (generador `tools/oot3d/native_a32_runtime/whole_aot_cpp.py`)

**Cómo es hoy el código generado** (ejemplo: `FUN_004a0338`, la función más caliente):

```cpp
uint32_t& r0 = state.R[0];                       // registros = referencias a memoria
block_004A0338:
    if (!Oot3dAotEnterBlock(context, frame, state, 0x004A0338U, ...)) ...   // costo por bloque
    uint8_t value; if (!context.Memory.ReadFast<uint8_t>(r0 + 0x100U, &value)) ...
    Oot3dAotSetSubtractFlags(flags, r2, 0, 0xF);  // NZCV completos...
    if (flags.Z()) return Oot3dAotReturned(r14);  // ...pero solo se lee Z
```

| # | Costo | Causa |
|---|---|---|
| E1 | Registros en memoria | Cada `ReadFast`/`WriteFast` tiene una ruta lenta con **llamada** (`ReadFastChecked`, noinline); GCC asume que una llamada puede tocar `state.R` → guarda y recarga |
| E2 | `Oot3dAotEnterBlock` por bloque | Contador de presupuesto + revisión de callback cada 4–6 instrucciones |
| E3 | Flags completos | El análisis de vida por flag existe (`whole_aot_optimization_ir.py`), pero se usa a medias |
| E4 | Contabilidad por escritura | `++mWriteGeneration` y `entry.WriteGeneration` en cada store |
| E5 | Llamadas | `--local-state` (opción existente) fue 14 % más lento: guarda y recarga los 15 registros por llamada |

**Ya probado y descartado:** `__restrict` en `state`/`context` (idea de XenonRecomp). Sin efecto: en el
shard 243, los `ldr` pasan de 20.618 a 20.688 y los `str` de 12.435 a 12.473. Se descarta por E1:
las llamadas de la ruta lenta.

| Etapa | Cambio | Ganancia | Riesgo | Cómo medir en el PC |
|---|---|---|---|---|
| **T1** | Registros como **valores locales** (no referencias) en funciones sin llamadas | 5–10 % | Bajo | `ldr`/`str` del shard en `.s` (ver `work/restrict_exp.sh`); `run_llvm_aot_pilot.py` |
| **T3** | Flags solo vivos, como `bool` locales o `cmp` fusionado | 2–5 % | Bajo | Ídem |
| **T2** | **MOD/REF transitivo** por el grafo de llamadas: antes de una llamada, guardar solo REF(callee) ∩ definidos; después, recargar solo MOD(callee) ∩ vivos. Llamadas indirectas: conjunto completo | 5–10 % | Medio | Ídem + A4 |
| **T7** | **Fastmem**: reservar 4 GB (`mmap PROT_NONE`) y mapear las regiones de la 3DS; acceso `base+addr` (1 instrucción); fallos con SIGSEGV → ruta lenta | 5–15 % | Medio–alto | A4 + qemu |
| **T4** | `EnterBlock` solo en saltos hacia atrás y entradas de función (como N64Recomp) | 3–8 % | Medio: **puede cambiar el reparto de tiempo entre hilos guest** → `PENDIENTE_CONFIRMAR` | A5 |
| **T5** | Contabilidad de escrituras por página | 2–4 % | Medio | A5 |
| **T6** | Llamadas directas sin `FindDispatchEntry` | 1–2 % | Bajo | — |

**Referencias** (investigadas 2026-10-26):

- [XenonRecomp](https://github.com/hedge-dev/XenonRecomp): opciones `non_volatile_as_local` y similares.
- [N64Recomp](https://github.com/N64Recomp/N64Recomp): memoria con base fija y sin comprobación por bloque.
- [Remill](https://github.com/lifting-bits/remill): memoria por intrínsecos, sin alias con el estado.
- [dynarmic](https://github.com/lioncash/dynarmic):
  - pasos de IR en `src/dynarmic/ir/opt`: `a32_get_set_elimination`, constantes, código muerto;
  - `fastmem_pointer` y `recompile_on_fastmem_failure`;
  - fuzzing contra Unicorn en `tests/A32/fuzz_arm.cpp`.
- [gbarecomp](https://github.com/mstan/gbarecomp): ARM→C++ en shards, con replay y huella por frame.

---

## 3. Herramientas y comandos

| Para | Comando / archivo |
|---|---|
| Compilar para la consola | `bash scripts/wsl/console_build.sh NOMBRE [--regen] [--no-smoke]`; deja `work/devserver/files/oot3d_r36s-NOMBRE.{gz,sha}` y los símbolos en `work/symfs` |
| Servidor de trabajos (PC) | `python -u scripts/devserver.py --root work/devserver --port 8765` (token en `work/devserver/token.txt`) |
| Trabajo en la consola | Escribir `work/devserver/job.sh`; **después** el id en `job.txt`. Funciones del agente: `bench NOMBRE BIN [VAR=v]`, `perfrec`, `fetch`, `send` (ver `docs/PRUEBAS.md`) |
| Resultados | `python scripts/summarize_results.py work/devserver/results/NNN --base ref` |
| Perfil por categoría | `bash work/perfcat.sh perfNNN.data` en WSL (symfs `/root/oot3d/work/symfs`) |
| Contar ldr/str de un shard | `work/restrict_exp.sh` (plantilla: genera en `aot-cpp-exp` y compila el shard 243 a `.s`) |
| Exactitud de coma flotante | `work/vfptest/run.sh` (x86) y `run-a64.sh` (qemu) |

### Trampas conocidas (no repetir)

1. **Rutas relativas** en scripts de WSL fallan: `qemu_smoke.sh` y `compare_x86.sh` hacen `cd`. Usar siempre rutas absolutas.
2. **Cambiar la línea de compilación** (flags, launcher) hace que ninja recompile los 256 shards (~30 min).
3. **ccache no cacheaba la build PGO**: ccache 4.11 no conoce `-fprofile-partial-training` ("unsupported compiler option").
   Arreglado con `ccache -o ignore_options=-fprofile-partial-training` (2026-10-26). **Falta verificar** que haya aciertos al repetir una compilación.
4. **La huella de memoria del benchmark x86 no es determinista** sin checkpoint (ver A5).
5. Clasificar el perfil por espacio de nombres engaña: `recomp::a32` no es solo coma flotante.
6. Las subidas del agente se colgaban si parpadeaba el anclaje USB: ya tienen tiempo límite y reintentos.
7. Publicar `job.txt` **lo último**.
8. Cambiar una cabecera usada por el código generado (p. ej. `oot3d_native_a32_vfp_fast.h`) recompila los 256 shards.

### Tiempos de referencia (Ryzen 5 7535HS, 6C/12T, WSL 10 GB)

| Paso | Tiempo |
|---|---|
| Regenerar C++ | ~75 s |
| Un shard a `-O3` con PGO, solo | ~23 s (16 % parseo: las cabeceras precompiladas no valen la pena) |
| 256 shards aarch64 | ~25–30 min |
| Cambio en un `.cpp` del runtime | ~1–2 min con empaquetado |
| Descarga del binario a la consola | ~100 s (47 MB a ~0,46 MB/s) |

---

## 4. Mediciones (consola, 600 frames, A/B alternado)

| Versión | p50 | fps | Nota |
|---|---|---|---|
| v1.0.0 | 129 ms | 7,7 | CPU y GPU por turnos |
| **v1.2.0** | 69,8 ms | 14,3 | D3 dibujo a medio ritmo + D2 audio simple (con audio) |
| **v1.1.0** | 83–85 ms | 11,7–12,0 | `TRIAEVUM_INPUT_ADMISSION=0` |
| main (coma flotante rápida) | 84,4 ms | 11,8 | Sin cambio (ruido) |

---

## 5. Cómo retomar (prompt sugerido para la próxima sesión)

> Lee `docs/TRADUCTOR_V2.md`, `docs/PRUEBAS.md` y el final de `docs/BITACORA.md` del proyecto OOT 3ds.
> Arranca el servidor de trabajos (`scripts/devserver.py`) y sigue el orden de la sección 1, empezando
> por C1 (menú Fn). Trabaja de forma autónoma, mide cada cambio en la consola con A/B y anota todo
> en estos documentos. No apliques sacrificios nuevos sin preguntar.
