# Retomar el proyecto desde GitHub

**Estado:** proyecto **cerrado** el 2026-10-26 en la **v1.2.1** (rama `estable`, tag `v1.2.1`).
El entorno de compilación del autor se borró: todo lo necesario para volver a empezar está en este repo.

| Qué | Dónde |
|---|---|
| Cambios sobre TriAevum (un solo parche, 29 archivos) | `patches/triaevum-r36s.patch`, sobre TriAevum `8f69a26` (verificado: se aplica limpio) |
| Lanzador para la R36S | `dist/ports/OOT3D v1.2.1.sh` |
| Scripts de compilación, pruebas y despliegue | `scripts/`, `scripts/wsl/` |
| Historia de cada prueba y medición | `docs/BITACORA.md` |
| Plan técnico del traductor v2 (detalle de cada etapa) | `docs/TRADUCTOR_V2.md` |
| Cómo probar rápido (PC, qemu, consola por red) | `docs/PRUEBAS.md` |
| Guía para portar otros juegos a la R36S con IA | `GUIA_PORTEO_R36S.md` + `r36s_info.sh` |

## 1. Reconstruir el entorno (≈ 1–2 h la primera vez)

1. **Windows + WSL2 Debian 13** con `.wslconfig` de al menos 10 GB de RAM y todos los hilos.
2. Instalar las dependencias y descargar las fuentes: sección *Compilar desde cero* del `README.md`
   (`scripts/fetch_sources.sh` clona TriAevum en el commit fijado y descarga libmali con su SHA-256).
3. Aplicar el parche: `git -C repos/TriAevum apply ../../patches/triaevum-r36s.patch`.
4. **ccache con PGO:** `ccache -o ignore_options=-fprofile-partial-training` (si no, no cachea nada).
5. Datos del juego desde **tu propio** cartucho desencriptado: `scripts/prepare_gamedata.py`
   (ver README). Este repo no contiene ROM, datos ni binarios.
6. Compilar para la R36S: `scripts/wsl/build_aarch64.sh` (o `build_pgo.sh` con un perfil propio) y
   preparar la carpeta con `scripts/wsl/stage_port.sh`. Una compilación completa tarda ~30 min.
7. Copiar `OOT3D v1.2.1.sh` y la carpeta `oot3d/` a `/roms/ports/` de la SD.

Pruebas sin mover la SD: `docs/PRUEBAS.md` (anclaje USB del celular + `scripts/devserver.py` + agente
`dist/ports/OOT3D Dev.sh`). En Windows hace falta la regla de firewall descrita en `GUIA_PORTEO_R36S.md`.

## 2. Dónde quedó

- En partida real: **7–9 fps de lógica estables, picos de 14,2** (el benchmark de la demo del menú da 15,9;
  sobrestima). El original va a 30. El límite es la **CPU** (~38 % es código del juego traducido).
- Opciones en el juego: Fn → Game → R36S performance (dibujo a medio ritmo, audio simple, audio estirado,
  contador de FPS).
- Hecho del plan v2: **A5** (benchmark del PC determinista, `scripts/wsl/det_run.sh`).

## 3. Plan que quedó sin hacer (en orden)

Cada paso se valida en el PC (misma huella de memoria con `det_run.sh` = mismo comportamiento) y se mide
en la consola con A/B alternado antes del siguiente.

### Fase 0 — preparación
| Paso | Qué | Esfuerzo |
|---|---|---|
| A5b | Benchmark de **partida real**: `--input-timeline` que cargue una partida existente hasta Link jugando (la secuencia `title_to_existing_save.json` creó partida nueva: revisar el espacio elegido) | Bajo–medio |
| A4 | Banco diferencial: traductor viejo y nuevo en un binario (renombrar espacio de nombres con `-DGeneratedWholeAot=...Ref`), misma función con mismos datos, comparar registros y memoria | Medio |

### Fase 1 — traductor v2, partes seguras
| Paso | Qué | Ganancia | Riesgo |
|---|---|---|---|
| T1 | Registros como **variables locales** en funciones sin llamadas | 5–10 % | Bajo |
| T3 | Flags calculadas solo cuando se leen (`whole_aot_optimization_ir.py` ya tiene la vida por flag) | 2–5 % | Bajo |

### Fase 2 — partes grandes
| Paso | Qué | Ganancia | Riesgo |
|---|---|---|---|
| T2 | En llamadas, guardar/recargar solo los registros que usa la función llamada (MOD/REF por el grafo de llamadas) | 5–10 % | Medio |
| T7 | Memoria directa de 4 GB (`base + dirección`, 1 instrucción; fallos de página por SIGSEGV) | 5–15 % | Medio–alto |

### Fase 3 — resto
| Paso | Qué | Nota |
|---|---|---|
| T4 | Presupuesto de bloques por lotes | **Puede cambiar el reparto de tiempo entre hilos del juego** |
| T5 | Contabilidad de escrituras por página | — |
| T6 | Llamadas directas sin tabla de búsqueda | — |

### Fase 4 — cierre
Recompilar el perfil PGO con el código nuevo, corregir lo que salga jugando y publicar.

**Expectativa:** Fase 1 ≈ 8–10 fps; Fase 2 ≈ 9–12; Fase 3 ≈ 10–13 (en partida). 30 fps no es alcanzable
en este hardware con este enfoque.

**Ya probado y descartado** (no repetir): `--local-state` global (−14 %), `__restrict` en el estado (sin
efecto), `mediump` global (crash del compilador Mali), coma flotante rápida (~0 %), frontend PICA en otro
núcleo y "menos actores" (costo/riesgo). Detalle en `docs/BITACORA.md`.

## 4. Prompt para retomar con una IA

```text
Retomamos el port de OoT3D a la R36S desde GitHub (juansepasca17/OOT-3ds-para-r36s).
Lee RETOMAR.md, docs/TRADUCTOR_V2.md, docs/PRUEBAS.md y el final de docs/BITACORA.md.
Reconstruye el entorno (sección 1), compila y verifica que coincide con la v1.2.1 antes de cambiar nada.
Sigue el plan de la sección 3 en orden; valida cada paso con det_run.sh y mide en la consola con A/B.
Pregúntame antes de cualquier sacrificio de jugabilidad o imagen. Responde en español y con tablas.
```
