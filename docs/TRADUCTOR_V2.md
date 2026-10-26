# Traductor v2 — rehacer a fondo el código generado

Documento vivo: investigación, diseño, forma de probar y estado. Rama de trabajo: `main`.
La versión jugable y estable está en la rama **`estable`** (= tag `v1.1.0`, 11,7 fps).

## 1. Por qué

En la v1.1.0 la CPU es el límite (~85 ms/frame en la consola). Perfil del hilo principal (trabajo 003):

| Categoría | % de muestras |
|---|---|
| Código del juego traducido (`Execute_*`) | ~36 % |
| Frontend PICA/GSP (órdenes de dibujo) | ~9 % |
| Coma flotante por software | ~1,5 % (el 7 % inicial era una categoría mal agrupada; ver BITACORA) |
| libc (memcpy/memset), audio, otros | resto |

El código traducido está repartido en miles de funciones: no hay un punto caliente, el costo es
**estructural**. Lo hace así el generador `tools/oot3d/native_a32_runtime/whole_aot_cpp.py`.

## 2. Cómo es hoy el código generado (y lo que cuesta)

Ejemplo real, `FUN_004a0338` (la función más caliente):

```cpp
uint32_t& r0 = state.R[0];   // registros = referencias a memoria
...
block_004A0338:
    if (!Oot3dAotEnterBlock(context, frame, state, 0x004A0338U, ...)) ...   // costo fijo por bloque
    uint8_t value; if (!context.Memory.ReadFast<uint8_t>(r0 + 0x100U, &value)) ...
    r2 = value;
    Oot3dAotSetSubtractFlags(flags, r2, 0, 0xF);   // NZCV completos
    if (flags.Z()) return Oot3dAotReturned(r14);    // ...pero solo se lee Z
```

| # | Costo estructural | Por qué cuesta |
|---|---|---|
| E1 | **Registros como referencias a `state.R[]`** | Cada escritura a memoria del juego (`memcpy` a `uint8_t*`) *puede* pisar `state.R`, así que el compilador guarda y recarga registros alrededor de cada store. Sin registros reales. |
| E2 | **`Oot3dAotEnterBlock` en cada bloque** | Lee y escribe `BlocksRemaining`/`BlocksConsumed` y revisa un callback, en bloques de 4–6 instrucciones. |
| E3 | **Flags NZCV completos** aunque solo se lea uno | Ya existe un análisis de vida por flag (`whole_aot_optimization_ir.py`) que se usa a medias. |
| E4 | **Contabilidad por escritura** (`WriteFast`) | `++mWriteGeneration` y `entry.WriteGeneration` en cada store (para detectar memoria cambiada). |
| E5 | **Llamadas entre funciones** | Pasan el estado completo; `--local-state` (registros locales) fue 14 % más lento porque guarda/recarga los 15 registros en cada llamada. |

## 3. Diseño propuesto (por etapas, cada una medible por separado)

| Etapa | Cambio | Ganancia estimada | Riesgo |
|---|---|---|---|
| **T1** | Registros en variables locales **solo en funciones hoja** (sin llamadas): sin E5, sin E1 | 5–10 % | Bajo |
| **T2** | ABI por vida de registros en llamadas directas: pasar/guardar solo los registros vivos (el IR ya calcula uso/definición) | 5–10 % | Medio |
| **T3** | Flags solo cuando se leen (E3) con el IR de vida por flag | 2–5 % | Bajo |
| **T4** | `EnterBlock` solo en cabeceras de bucle y llamadas (E2); el presupuesto de bloques se cuenta por lotes | 3–8 % | Medio: el presupuesto reparte el tiempo entre hilos del juego. **Puede cambiar el comportamiento** |
| **T5** | Contabilidad de escrituras por página en vez de por store (E4) | 2–4 % | Medio |
| **T6** | Despacho directo entre funciones conocidas (sin `FindDispatchEntry`) | 1–2 % | Bajo |
| **T7** | **Fastmem**: reservar 4 GB y acceder como `base + dirección` (1 instrucción en vez de 2 cargas de tabla + rama); fallos de página con SIGSEGV | 5–15 % (inferencia) | Medio-alto: mapear regiones 3DS, MMIO |

Acumulado optimista: **~25–40 % menos tiempo de CPU** → ~15–18 fps. Las etapas que cambien
comportamiento observable (T4) se anotan en `docs/PENDIENTE_CONFIRMAR.md` antes de publicarlas.

## 4. Cómo probar en el PC (lo máximo posible sin consola)

La huella de memoria del benchmark **no es determinista** (dos corridas del mismo binario difieren),
así que no sirve para comparar traductores. Pruebas, de la más barata a la más cara:

1. **Pruebas unitarias del generador** (`test_whole_aot_cpp.py`, Python, segundos).
2. **Pruebas diferenciales por función** (nuevo, prioridad): un binario x86 enlaza el código
   generado viejo y el nuevo en espacios de nombres distintos. Se ejecuta cada función desde estados
   capturados del juego real y se comparan registros, flags, memoria escrita y salida. Encuentra
   el primer error exacto en segundos, sin consola. Los estados se capturan una vez con
   `TRIAEVUM_*` block-entry callbacks.
3. **Trazas de bloques** (`compare_block_traces.py` ya existe): mismo arranque con ambos traductores
   y primer bloque donde divergen.
4. **Determinismo del benchmark x86**: encontrar qué lo hace no determinista (hilos de
   presentación, reloj real) y fijarlo (`--serial-presentation`, tiempo simulado). Con eso la huella
   vuelve a ser una prueba de equivalencia de punta a punta.
5. **qemu aarch64**: arranque y 20 frames (detecta crashes de la build ARM).
6. **Consola**: solo para medir velocidad, siempre A/B alternado (`docs/PRUEBAS.md`).

Tiempos del PC (Ryzen 5 7535HS, 6 núcleos/12 hilos, WSL con 10 GB):
regenerar C++ ~75 s; un shard ~70 s a `-O3` con PGO; los 256 shards ~35 min aarch64.
Para iterar rápido: x86 sin PGO a `-O1` para las pruebas diferenciales, y ccache en todas las builds.

## 6. Bases y herramientas para la reescritura

| Base | Qué aporta | Estado |
|---|---|---|
| `whole_aot_optimization_ir.py` (ya en TriAevum) | Uso/definición de registros, vida por flag, regiones del CFG | Existe; se usa a medias |
| `run_llvm_aot_pilot.py` (ya en TriAevum) | Compila un shard a LLVM IR y **cuenta el tráfico al estado guest** (loads/stores a `state.R`) | Métrica de PC para E1/E5 sin consola |
| `compare_block_traces.py` (ya en TriAevum) | Primer bloque donde divergen dos ejecuciones | Existe |
| Savestate determinista + `--load-state` | Así el proyecto original obtiene huellas idénticas entre corridas | Falta un checkpoint propio (A5) |
| Recompiladores de referencia | XenonRecomp: `__restrict` + registros no volátiles como locales; N64Recomp: memoria con base fija, sin comprobación por bloque; Remill: memoria por intrínsecos sin alias con el estado; dynarmic: pasos de IR (get/set de registros, constantes, flags muertos) y **fastmem** (base de 4 GB, 1 instrucción por acceso); gbarecomp (ARM→C++ en shards): replay con huella por frame y oráculo | Investigado 2026-10-26 |

## 7. Sacrificios y técnicas de rendimiento (fuera del traductor)

El juego corre con `native30_no_interpolation`: un frame del host = un frame lógico del juego. Por
debajo de 30 fps el juego va **más lento que en tiempo real**, no salta frames. Por eso bajar
gráficos no ayuda: el costo está en la lógica del juego (CPU).

| Técnica | Ganancia | Costo / riesgo | Veredicto |
|---|---|---|---|
| Frontend PICA (9 %) a otro núcleo (la consola tiene 4 y se usan ~1,5) | 5–9 % | Arquitectura: sincronizar órdenes de dibujo | Viable, medio |
| Audio en real (en el benchmark está apagado): mezcla más simple o a menor frecuencia | 1–3 % | Calidad de audio | Viable; requiere permiso |
| Saltarse la preparación de dibujo del juego un frame de cada dos | 15–25 % | Animaciones a 15 fps; parches al juego (decomp) | Sacrificio fuerte; requiere permiso |
| Menos actores o menos distancia de dibujo (parches al juego) | Variable | Cambia el juego | Último recurso |
| Bajar resolución, sombras o efectos | ~0 % | Se ve peor | Descartado (la GPU no es el límite) |
| Overclock de CPU o GPU | ~0–5 % | Calor, estabilidad, permisos de root | Descartado por ahora |

## 8. Otros pendientes (fuera de rendimiento)

| Código | Qué | Estado |
|---|---|---|
| D1 | Frontend PICA (órdenes de dibujo) en otro núcleo | **Aprobado**; activado, desactivable en el menú |
| D2 | Audio más simple en partida real | **Aprobado**; activado por defecto, desactivable en el menú |
| D3 | Preparar el dibujo 1 de cada 2 frames | **Aprobado**; activado por defecto, desactivable en el menú |
| C1 | **Menú Fn invisible en GLES** (prioridad: sin él no se pueden desactivar D1–D3): se abre y dibuja 565 primitivas, pero no aparece. Depurable en el PC con qemu y capturas del framebuffer | Pendiente |
| C2 | Opciones de calidad de vida en el menú (idioma, controles, rendimiento) | Después de C1 |

## 5. Estado

| Fecha | Paso | Resultado |
|---|---|---|
| 2026-10-26 | Rama `estable` = v1.1.0; este documento | — |
| 2026-10-26 | Coma flotante rápida (previo a T1) | Exacta (120 M casos); en consola sin cambio (−1,3 %, ruido) |
| 2026-10-26 | `__restrict` en `state`/`context` (idea de XenonRecomp) | **Sin efecto**: shard 243 aarch64 pasa de 20.618 a 20.688 `ldr` y de 12.435 a 12.473 `str`. Cada acceso a memoria tiene una ruta lenta con llamada (`ReadFastChecked`) y GCC asume que una llamada puede tocar `state`. Revertido. Confirma que hacen falta registros locales de verdad (T1/T2) |
