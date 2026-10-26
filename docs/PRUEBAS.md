# Pruebas eficientes en la R36S

Cómo medir mucho en una sola pasada, con poco tiempo de consola y pocos tokens de IA.
Complementa `GUIA_PORTEO_R36S.md` (montaje de la red y del agente).

## Idea central

**Un trabajo = muchas variantes.** Cada viaje a la consola cuesta minutos: bajar el binario, arrancar el
juego y calentar. Por eso un trabajo mide todas las variantes que se puedan, alternadas, y deja todo
en `out/`. La decisión se toma con una tabla, no leyendo logs.

```
PC: editar → console_build.sh NOMBRE → job.sh (bench x N) → job.txt   (job.txt siempre al final)
Consola: agente "OOT3D Dev" descarga, mide y sube out/*
PC: summarize_results.py results/<trabajo> --base <ref>  → tabla → decidir
```

## Herramientas

| Herramienta | Para qué |
|---|---|
| `scripts/wsl/console_build.sh NOMBRE [--regen] [--no-smoke]` | Sincroniza fuentes, compila aarch64 PGO incremental, prueba en qemu, empaqueta `.gz` + `.sha` y deja símbolos para perf. Usa `--regen` solo si cambió el generador del traductor. |
| Agente: `bench NOMBRE BINARIO [VAR=valor...]` | Corre el benchmark estándar (600 frames, 100 de calentamiento, paralelo, CPU‖GPU). `BINARIO=game` usa el juego instalado. Variables: `FRAMES`, `WARMUP`, `BENCH_TIMEOUT`. |
| Agente: `perfrec NOMBRE BINARIO [VAR=valor...]` | Igual que `bench`, pero bajo `perf record -e cpu-clock:u` y deja `out/perf_NOMBRE.data`. |
| Agente: `fetch` / `send` | Descarga con sha256 (descomprime `.gz`) y sube con 5 reintentos. |
| `scripts/summarize_results.py DIR --base PREFIJO` | Tabla Markdown con p50/media/p95/fps y el cambio frente a la referencia. Promedia `X_a`, `X_b`… en una fila. |

## Plantilla de trabajo (A/B con repetición)

```bash
#!/bin/bash
# Trabajo NNN: qué se mide y por qué (una línea).
fetch oot3d_r36s-NOMBRE.sha "$DEVDIR/n.sha" || exit 1
fetch oot3d_r36s-NOMBRE.gz "$DEVDIR/oot3d_r36s_NOMBRE" "$(cat "$DEVDIR/n.sha")" || exit 1
chmod +x "$DEVDIR/oot3d_r36s_NOMBRE"
for r in a b; do                       # alternar reparte calor y estado de la consola
  bench "ref_$r" game
  bench "new_$r" "$DEVDIR/oot3d_r36s_NOMBRE"
done
bench new_flat "$DEVDIR/oot3d_r36s_NOMBRE" OOT3D_GL_FLAT_FRAGMENT=1   # variantes extra: gratis
perfrec new "$DEVDIR/oot3d_r36s_NOMBRE"; gzip -f "$JOBDIR/out/perf_new.data"
```

Resultado: `python scripts/summarize_results.py work/devserver/results/NNN-x --base ref`.

## Reglas (aprendidas a golpes)

1. **Publicar `job.txt` lo último.** Primero escribir `job.sh` y los archivos; el agente consulta cada 20 s.
2. **Comparar siempre contra una referencia del mismo trabajo**, alternada (A, B, A, B). La consola varía
   ±5 % entre trabajos (calor, frecuencia de GPU de 400 a 520 MHz).
3. **Una diferencia < 3 % es ruido** salvo que se repita en las dos rondas.
4. **Escenas:** el benchmark usa `savedata/quick.oot3dsav`. Una variante que no cambia nada puede ser
   porque la escena no usa esa función (ej. `gl_FragDepth`, sombras): anotarlo, no concluir de más.
5. **Binarios siempre en `.gz`** (148 → 47 MB; el anclaje USB da ~0,46 MB/s ≈ 100 s).
6. **No compilar x86 para validar equivalencia:** `memory_state_fingerprint` cambia entre dos corridas
   del mismo binario. Para cambios numéricos usar pruebas bit a bit (ej. `work/vfptest/`, 120 M casos
   contra el software de referencia, en x86 y en aarch64 con qemu).
7. **ccache con PGO:** requiere `ccache -o ignore_options=-fprofile-partial-training` (ccache 4.11 no conoce esa opción y no cachea nada sin esto).
8. **Cambios de cabeceras recompilan los 256 shards** (~20 min aarch64). Juntar varios cambios de
   cabecera en una sola compilación cuando se pueda; los `.cpp` sueltos tardan ~30 s.
9. **Sincronizar también lo revertido:** un archivo devuelto a su versión original ya no sale en `git diff` de Windows pero sigue cambiado en el árbol de WSL (`console_build.sh` ya lo cubre).
10. **Rutas absolutas** en los scripts de WSL (los scripts hacen `cd` al directorio del juego).
11. **Si la consola no responde**, anotarlo en `docs/PENDIENTE_CONFIRMAR.md` y seguir con trabajo de PC.

## Ahorrar tokens

- Leer resultados con `summarize_results.py`, nunca el JSON completo (120 KB cada uno).
- Filtrar logs al guardarlos: `grep -E '\[gpu\]|\[hang\]|failed|Signal|error'`.
- Perfiles: agrupar por categoría (código del juego, frontend PICA, coma flotante, libmali…) antes de
  mirar funciones sueltas. Comando en `docs/BITACORA.md` (sección de perfiles).
- Un solo script por paso (`console_build.sh`), no comandos largos improvisados que se rompen con las
  comillas de Windows → WSL.

## Estado de referencia (2026-10-26)

| Versión | p50 | fps | Nota |
|---|---|---|---|
| v1.0.0 | 129 ms | 7,7 | CPU y GPU por turnos |
| v1.1.0 | 85 ms | 11,7 | `TRIAEVUM_INPUT_ADMISSION=0`; ahora el límite es la CPU |
| main (coma flotante rápida) | 84 ms | 11,8 | Sin cambio medible |

Plan y tareas pendientes: `docs/TRADUCTOR_V2.md`.
