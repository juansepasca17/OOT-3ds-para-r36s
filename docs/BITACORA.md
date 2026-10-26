# Bitácora técnica

## 2026-10-25 — Sesión 1: investigación y entorno

### ROM
- `rom/Legend of Zelda, The - Ocarina of Time 3D (USA) (En,Fr,Es) (Rev 1).cci`, 536,870,912 bytes.
- NCSD → NCCH `CTR-P-AQEE`, Title ID `0004000000033500`, flags `0000000001030004` → **NoCrypto** (desencriptada).
- SHA-1 `50d6b33de7298d397fa9f0dde78f8b0f23256564` = No-Intro USA Rev 1 (registro 1259).
  TriAevum la cubre en la verificación de catálogo del 2026-09-08 (`docs/TRIAEVUM_SUPPORTED_ROM.md`)
  mediante el adaptador USA→canónico (`tools/triaevum_release/input_adapters.py`).

### TriAevum (`repos/TriAevum`, commit `8f69a26`, 2026-10-22; último tag `v0.8.0-beta.1.2`)
- Pipeline de datos (`tools/triaevum_release/forge_gui.py::install_private_title`):
  `ctr_rom.extract_decrypted_rom` → `match_extracted_recipe` → `adapt_extracted_inputs` (USA) →
  `forge.verify_sources` → `forge.prepare_content` → IR AOT → 256 shards C++ → módulo.
- Producto whole-AOT: 12,419 funciones, 3 fronteras de host, 0 entradas A32 residuales.
- Port de Switch (`scripts/switch/build-product.sh`): ARM64, `-DOOT3D_ENABLE_VULKAN_RENDERER=OFF`,
  `-DOOT3D_WHOLE_AOT_PRODUCT_MODE=ON`, SDL2 + OpenGL (Mesa). Solo verificado en el emulador Eden.
- Backend OpenGL PICA: shaders Vulkan GLSL 450 reescritos a GLSL **430 de escritorio**, con SSBO
  `std430` (`renderer3ds/pica_gl_shader_dialect.cpp`). El contexto SDL pide un perfil Core 4.x
  (`gfx_sdl2.cpp:410-417`). → Hay que portarlo a **GLES 3.2**.
- Toon y contorno: **solo en el backend Vulkan** (`gfx_vulkan_*`). → Hay que portarlos.
- El runtime ya tiene flags útiles: `--renderer opengl`, `--throughput-benchmark`, `--frames`,
  `--benchmark-warmup-frames`, `--load-state`, `--disable-audio`, `--ui-profile topscreen`,
  `--gameplay-timing native30_no_interpolation`, `--parallel-presentation`, `--whole-aot-block-budget`.
- CPU medida por el proyecto en un PC de escritorio: unos 5.3 ms por actualización sin renderer
  (4.75 ms de AOT) y unos 94.8 FPS totales en el benchmark OpenGL de Linux.

### dArkOS (`repos/dArkOS`) / dArkOS RE (`southoz/dArkOSRE-R36`)
- Debian **trixie** (`DEBIAN_CODE_NAME ?= trixie`).
- RK3326: GPU con **libmali** `libmali-bifrost-g31-rxp0-gbm.so` enlazada como libEGL y libGLESv2
  → solo GLES + GBM/KMSDRM. No hay Vulkan ni GL de escritorio en RK3326 (Vulkan solo en RK3566).
- Incluye userspace armhf de 32 bits (`BUILD_ARMHF`) para ports de PortMaster.
- SDL2 propio (`build_sdl2.sh`).

### Entorno local
- WSL2 **Debian 13 trixie** instalado (12 hilos, 7.4 GB de RAM, mismo glibc que dArkOS).
- `deps/mali/libmali-bifrost-g31-rxp0-gbm.so` (aarch64, 40.8 MB) descargada de
  `christianhaitian/rk3326_core_builds`.

### Datos del juego e IR AOT
- `scripts/prepare_gamedata.py`: receta `oot3d-usa-input-canonical-eur-ef210566` (entrada USA,
  runtime EUR canónico). Entradas extraídas: code `ef210566…`, exheader `dbe5fa01…`, romfs `dd6def65…`
  (idénticas a las que TriAevum probó). Adaptación en 2.2 s.
- `forge prepare-aot-ir`: 12,442 funciones, 162,766 bloques, 924,535 instrucciones A32, 0 sin reclamar
  (3.5 min en 1 hilo).
- La auditoría del producto exigía el hash del ExHeader EUR. El ExHeader USA tiene el mismo entrypoint
  (`0x100000`) y el mismo tamaño de texto (3,973,120). → `patches/0001-accept-qualified-usa-exheader.patch`
  acepta hashes extra vía `OOT3D_ACCEPT_EXHEADER_SHA256` y mantiene todas las demás comprobaciones.

### Consola del usuario (`OOT3D-Info.sh`, 2026-10-25)
- **R36S-V12 Panel 4**, dArkOSRE **03082026**, Debian 13.3, kernel 4.4.189, glibc 2.41.
- CPU 4× Cortex-A35 r0p2, máx. **1512 MHz** (governor ya en `performance`). Flags: asimd, aes, crc32.
- RAM 895 MB usables + **zram 512 MB**. `/tmp` es tmpfs de 448 MB.
- GPU Mali-G31 en `ff400000.gpu`, máx. **520 MHz**. libmali `bifrost-g31-rxp0-gbm`, la misma que en `deps/`.
- SDL2 **2.32.10**. Pantalla 640×480 a **77 Hz** (`640x480p77`) → 30 fps no divide exacto la
  frecuencia del panel: hay que medir el ritmo de frames (VSync vs. limitador propio).
- Control: `GO-Super Gamepad` (js0/event2). PortMaster en `/opt/system/Tools/PortMaster`.
- Tiene Ship of Harkinian (PortMaster) funcionando: referencia útil para el contexto GLES y los controles.

### Puerta de CPU — primera medición real en la R36S (2026-10-25)
Build: GCC 14 `-O2 -mcpu=cortex-a35`, sin LTO ni PGO. Intro del título, 300 frames de calentamiento
+ 600 medidos, renderizado por software (llvmpipe), presentación en serie, sin audio.
Hicieron falta tres intentos para arrancar: (1) `/etc/profile.d/SDL_VIDEO.sh` forzaba el EGL de Mali
→ `SDL_VIDEO_EGL_DRIVER` explícito; (2) SDL offscreen elegía la GPU Rockchip y Mesa se caía
→ `SDL_HINT_EGL_DEVICE=1` (llvmpipe); (3) corrió completo, exit 0.

| Métrica (por frame) | Valor | Presupuesto a 30 fps |
|---|---|---|
| CPU antes del renderer (lógica + host), media | **89.1 ms** (p95 98.4) | 33.3 ms |
| — guest (código AOT del juego) | **76.9 ms** | |
| — plan de presentación | 6.8 ms | |
| — DSP | 2.6 ms | |
| — captura de cola PICA | 2.4 ms | |
| Frame total con llvmpipe | 687 ms (1.46 fps) | (no representativo: render por CPU) |

**Conclusión:** la lógica sola está **2.7× por encima** del presupuesto de 30 fps (≈ 11 fps de techo
de CPU con este build), en línea con la estimación inicial de 60–80 ms. Siguiente paso posible:
Fase 2b (flags de compilación → LTO/PGO → cambios al generador AOT).

### Prueba 2 — renderer en la GPU (OpenGL ES 3.2, Mali-G31)
- Parche 0003: backend PICA habilitado con `USE_OPENGLES` (antes devolvía "requires OpenGL 4.3"),
  cabecera `#version 320 es` + precisiones, `glDrawBuffers`/`glClearDepthf`, sin logic op ni LOD bias,
  texturas de sombra R32UI inmutables (`glTexStorage2D`) para `glBindImageTexture`.
- Validación: 200 frames en qemu + llvmpipe ES 3.2, 19 programas distintos compilan y enlazan.
- En la consola: `GL=OpenGL ES 3.2 v1.r13p0 renderer=Mali-G31`. Llega a la intro, al menú y al registro
  de nombre. Imagen correcta en la intro (Campo de Hyrule).

| Métrica | Valor |
|---|---|
| Lógica (pre-backend) media | **66.9 ms** (antes 89 ms con llvmpipe compitiendo por CPU) |
| Frame total, mediana | **93 ms ≈ 10.7 fps** (media 172 ms por compilación de shaders) |
| Primeros 28 frames | 117 s (compilación de shaders en Mali) |
| Audio | underruns de ALSA (el juego va por debajo de 30 Hz) |

### Prueba 3 — paralelo + caché de shaders
- El contexto GLES se entrega al hilo del renderer (`SetWorkerThreadHooks`); `Run` se ejecuta en el
  worker (`SetRunOnWorker`); ImGui crea sus objetos antes del traspaso.
- Caché de binarios de programa en `oot3d/shadercache` (`OOT3D_GL_PROGRAM_CACHE`).
- qemu: paralelo sin caídas; 14 programas en caché reutilizados en la segunda corrida.

### Infraestructura de compilación
- `.wslconfig`: 10 GB y 12 hilos (Ryzen 5 7535HS, 15 GB). ccache (20 GB) + mold.
- Lección: no restaurar el repo y re-aplicar parches; reescribe el script de auditoría y fuerza
  la recompilación de los 256 shards (que dependen de su paso de auditoría).

### Pruebas 5–9 (2026-10-25, tarde)
- **Bloqueo del paralelo resuelto.** El vigilante mostró al renderer girando en un recorrido de lista
  dentro de libGLESv2 (estructura corrupta). Con `glspy.c` (LD_PRELOAD en qemu) se encontraron 24
  llamadas GL sin contexto desde el hilo principal: `Ship::Gui::EndDraw → ImGui_ImplOpenGL3_RenderDrawData`.
  Mesa/glvnd las ignora; Mali corrompe el contexto que usa el worker. Fix: en GLES, ImGui se dibuja en el
  worker con una copia del draw data (como el backend Vulkan).
- **PGO** (GCC, perfil de ~15 min de juego en la consola, `-fprofile-correction` por volcados con hilos
  activos) + **memoria en línea** (`ReadFast`/`WriteFast` con camino rápido `always_inline`).
- **Prueba 8 (diagnóstico de GPU):** normal 131.6 ms, sin dibujar 75.2 ms, `glFinish` 30–45 ms/frame.
  `mediump` en fragmentos hace caer el compilador de Mali (`LLVM ERROR: Cannot select: intrinsic
  %llvm.bifrost.fptrunc.te`) → descartado en este driver.
- **Prueba 9:** ring de uniforms (map unsynchronized + fences): 128.9 ms (−2 %).

| Versión | Lógica | Frame p50 | fps |
|---|---|---|---|
| Prueba 4 (serie) | 82.2 ms | 147.6 ms | ~6.8 |
| Prueba 7 (paralelo + PGO + memoria) | 62.7 ms | 131.6 ms | 7.6 |
| **Prueba 9 / v1.0** | **61.5 ms** | **128.9 ms** | **7.75** |

**Pendiente:** el hilo del renderer usa ~129 ms/frame: ~40 GPU + ~22 PICA backend + ~65 sin
atribuir (UI Fast3D/N64, copias de display, subidas de textura). Medir por fases en la consola.
Fase D (`--local-state`) en evaluación x86. Menú Fn: se abre (565 primitivas) pero no se ve.

### Fase D — primer experimento: `--local-state` (descartado)
x86, misma medición de 900 frames (300 de calentamiento), throughput determinista:

| Generador | Lógica/frame | `memory_state_fingerprint` |
|---|---|---|
| normal | 8.62 ms | 4724681108082561086 |
| `--local-state` | 9.85 ms (+14 %) | 2977942875981937782 |

Más lento (commit/reload de registros en cada llamada entre funciones) y huella distinta (falta confirmar
determinismo base-vs-base). Próximos candidatos de D: flags solo cuando se leen (hoy
`Oot3dAotSetSubtractFlags(..., 0xF)` calcula NZCV completo aunque solo se use Z), costo fijo de
`Oot3dAotEnterBlock` por bloque, y despacho directo entre funciones.

### Diagnóstico de GPU en la consola (trabajo 004, 2026-10-26)
Binario de diagnóstico con variantes por variable de entorno; 300 frames (100 de calentamiento), modo
paralelo, escena del quick-state. Perfil previo (trabajo 003): ningún hilo de CPU saturado (principal ~58 %,
render ~22 %) → CPU y GPU se esperaban una a la otra.

| Variante | Frame p50 | fps | Lectura |
|---|---|---|---|
| normal (v1.0) | 129.0 ms | 7.7 | referencia |
| `TRIAEVUM_INPUT_ADMISSION=1` | 129.2 ms | 7.7 | igual que normal |
| **`TRIAEVUM_INPUT_ADMISSION=0`** | **74.8 ms** | **13.2** | **CPU y GPU en paralelo: +71 %** |
| fragmento plano | 89.4 ms | 11.2 | el TEV cuesta ~40 ms de GPU |
| scissor 1×1 | 89.9 ms | 11.1 | el costo es de píxeles, no de vértices |
| sin `gl_FragDepth` | 132.8 ms | 7.5 | sin efecto (esta escena no lo escribe) |
| sin sombras | 136.2 ms | 7.3 | sin efecto |

Causa: por defecto cada frame esperaba a que el anterior se presentara (`WaitForFramesInFlight(0)`, pensado
para bajar la latencia de entrada a 60 Hz). Con `=0` la lógica del frame N+1 corre mientras la GPU dibuja el N;
el frame queda en ~75 ms ≈ costo de CPU sola (igual que la prueba sin draws). Ahora el límite es la CPU.
La frecuencia de la GPU (devfreq `simple_ondemand`) oscila 400–520 MHz.
**v1.1.0** = mismo binario + `export TRIAEVUM_INPUT_ADMISSION=0` en el lanzador.

Confirmación (trabajo 005, binario real del juego, 600 frames): **85.1 ms p50 → 11.7 fps** (v1.0: 129 ms, 7.7 fps).
Con la espera quitada, fragmento plano (75.8 / 81.2 ms) y scissor 1×1 (82.2 ms) ya no cambian nada:
**la GPU dejó de ser el límite; ahora manda la CPU** (lógica del juego ~65–75 ms). Optimizar shaders no
da fps hasta bajar la CPU. Siguiente objetivo: fase D (traductor) y costo del backend PICA en CPU.
Nota de red: las subidas de resultados del agente pueden colgarse si el anclaje USB parpadea
(curl sin `--max-time`); se recuperaron con un trabajo de reenvío.

### Fase D — coma flotante rápida (2026-10-26)
Perfil de la consola (trabajo 003, hilo principal): código del juego traducido ~36 % de las muestras, frontend
PICA/GSP ~9 %, coma flotante emulada por software ~7 % (`Divide` de 128 bits, `RoundFinite`, `Unpack`).
VDIV, VSQRT, VCMP/VCMPE y VCVT a entero iban siempre por software. Nuevas rutas rápidas exactas en
`oot3d_native_a32_vfp_fast.h` (`Oot3dVfpDivide`, `Oot3dVfpSquareRoot`, `Oot3dVfpCompare`,
`Oot3dVfpToSigned`, `Oot3dVfpToUnsigned`), con la implementación por software como respaldo fuera de rango:
- división y raíz en doble precisión: el doble redondeo 53→24 bits es inocuo (53 ≥ 2·24+2); IXC exacto
  porque `cociente·divisor` y `raíz²` caben exactos en double;
- comparación y conversión a entero (redondeo hacia cero) sin NaN ni subnormales.
Verificación: 120 millones de casos aleatorios + bordes, todos los modos FPSCR, x86 y aarch64 (qemu):
**0 diferencias** bit a bit (valor y flags). 3.927 comparaciones del juego pasan a la ruta rápida.
Nota: `memory_state_fingerprint` del benchmark x86 **no es determinista** (mismo binario, dos huellas
distintas): no sirve como prueba de equivalencia entre versiones.

**Medición en la consola (trabajo 007, A/B alternado, 600 frames):** v1.1.0 83,3 ms ±1,4 vs coma flotante
rápida 84,4 ms ±0,7 → **sin cambio** (dentro del ruido). Causa: la categoría "coma flotante" del perfil 003
(7 %) mezclaba otras funciones del espacio de nombres `recomp::a32`; la emulación por software real era
~1,5 % y ahora ~1 % (`Divide` 0,56 → 0,30 %). Se mantiene (exacta, inofensiva). Perfil 007: código del juego
traducido **~38 %**, frontend PICA 9 % (+5 % en el hilo de render), libmali 16 % (render), libc (memcpy) 5 %.
Conclusión: el costo está en el código generado → traductor v2 (`docs/TRADUCTOR_V2.md`).
