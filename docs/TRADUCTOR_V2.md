# Traductor v2 — rehacer a fondo el código generado

Documento vivo: investigación, diseño, forma de probar y estado. Rama de trabajo: `main`.
La versión jugable y estable está en la rama **`estable`** (= tag `v1.1.0`, 11,7 fps).

## 1. Por qué

En la v1.1.0 la CPU es el límite (~85 ms/frame en la consola). Perfil del hilo principal (trabajo 003):

| Categoría | % de muestras |
|---|---|
| Código del juego traducido (`Execute_*`) | ~36 % |
| Frontend PICA/GSP (órdenes de dibujo) | ~9 % |
| Coma flotante por software | ~7 % (atacado en v1.2, ver BITACORA) |
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

## 5. Estado

| Fecha | Paso | Resultado |
|---|---|---|
| 2026-10-26 | Rama `estable` = v1.1.0; este documento | — |
| 2026-10-26 | Coma flotante rápida (previo a T1) | Exacta (120 M casos); medición en consola pendiente |
