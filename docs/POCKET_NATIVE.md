# OoT3D en una pantalla sobre Pocket Native: estado, cambios al emulador y mediciones

Última actualización: 2026-11-21. Leer esto primero al retomar (también con /goal).

## Resumen

| | fix1 | fix2 |
|---|---|---|
| Velocidad en la casa de Link (probe, misma ruta) | 82–85 % de la 3DS | **125–130 %** |
| Velocidad media, 14 400 cuadros | 85 % | **111 %** |
| Código del mod | interpretado | **recompilado** (0,00 % interpretado) |
| Pantalla de abajo (no se ve) | dibujada a 30 fps | dibujada (saltarla rompía el mod, ver fix3) |
| Idioma | inglés | **español** (con HUD del mod) |

## Qué hay y dónde

| Pieza | Dónde |
|---|---|
| Mod Ocarina ReFramed 2.5.1, una pantalla (GPL-3.0, OTPR26/OOT3DHud) | `mods/single-screen/` (no se sube). Fuente: github.com/OTPR26/OOT3DHud/tree/v2.5.1/release-source/2.5.1/single/USA |
| ROM USA parchada (SHA-256 `c90126fe…8e30`) | `mods/single-screen/out/game-reframed-2.5.1.3ds` (no se sube) |
| Parche de español (RomFS) | `mods/single-screen/espanol/romfs.patch` (no se sube: tiene texturas del juego) |
| Kit Pocket Native 0.6.1 con nuestros cambios | `repos/pocket-native-0.6.1/` (no se sube) |
| **Nuestros cambios al kit** | `patches/pocket-native-0.6.1-reframed.patch` (se aplica limpio con `git apply` sobre el ZIP de v0.6.1) |
| Herramientas de RomFS | `scripts/romfs_ls.py` (listar/extraer), `scripts/romfs_patch.py` (hacer romfs.patch) |
| Pruebas en el PC (sin pantalla, Mesa) | `scripts/pc/` |
| Agente de pruebas de la consola | `dist/ports/PN Dev.sh` |
| Servidor de trabajos en el PC | `python -u scripts/devserver.py --root work/devserver --port 8765` |

## Cambios al emulador (Pocket Native 0.6.1), pensados para otros juegos de 3DS

| # | Qué | Por qué | Archivos | Resultado |
|---|---|---|---|---|
| 1 | `svcOpenProcess` (0x33) y `svcControlProcessMemory` (0x70; PROTECT no hace nada) | Los mods de código estilo Magikoopa/randomizer (cargador en `.text` que marca su código como ejecutable) llaman a estos SVC al arrancar; sin ellos el juego hace `svcBreak` | `engine/core/src/kernel/svc.rs` | El juego con el mod arranca |
| 2 | El cargador copia lo que la imagen de código trae después de `.data` dentro de `.bss` | Esos mods agrandan `.bss` en el exheader y ponen su código ahí (aquí `0x5C7000`); la consola y Azahar copian la imagen entera, Pocket Native solo los segmentos | `engine/core/src/loader.rs` | El código del mod existe en memoria |
| 3 | El recompilador ve el código del mod: el texto se extiende hasta el final de la imagen, con **huecos** (`Segment::holes`) sobre `.rodata/.data/.bss` y sobre tramos de ≥256 ceros | Sin huecos, las funciones Thumb seguían "decodificando" ceros (`lsls r0,r0,#0`) y datos: 23 M de instrucciones y 530 MiB de C | `recompiler/src/image.rs`, `discover.rs` (+ constructores en `codegen/*`, `cro.rs`) | Mod recompilado: **+52 % de velocidad** en juego. Bonus: el análisis del juego base baja de 6,5 M a 1,3 M instrucciones decodificadas |
| 4 | **Opcional, apagado por defecto (`ZAKURO_HIDE_BOTTOM=1`)**. Pantalla de abajo oculta: si el layout no la muestra, cada dibujo al framebuffer de abajo se omite uno por uno (aunque se mezcle con los de arriba). Seguro: si ese buffer llega a la pantalla de arriba, se apaga solo | El salto de Pocket Native se apaga para siempre cuando un juego dibuja ambas pantallas entre dos transferencias (`both_screens`), como hace este mod | `engine/gpu/src/lib.rs` (`draws_hidden_bottom`), `engine/core/src/lib.rs` (`present_panel`) | La de abajo deja de dibujarse en "Top only" |
| 5 | `romfs.patch` en `games/<id>/data/`: piezas escritas sobre el RomFS (nivel 3), también pasado el final | Cambiar archivos del RomFS sin reconstruir la ROM; los juegos leen el RomFS como bloque crudo | `engine/core/src/services/fs.rs` (`RomFsPatch`) + `scripts/romfs_patch.py` | Español con las texturas del HUD del mod (3 MB) |
| 6 | Log periódico: `interpreted X% of the instructions` cada 5 s y, con `ZAKURO_INTERP_STATS=1`, las direcciones más interpretadas cada 30 s | Medir el intérprete aunque el juego se corte con una señal (antes solo salía al cerrar limpio) | `engine/core/src/lib.rs`, `frontend/src/lib.rs` | Midió 0,00 % con fix2 |
| 8 | Programas rechazados por Mali **sin mensaje** (link con log vacío) no se marcan en disco (`.refused`); solo se evitan en esa sesión | Pocket Native los marcaba para siempre: en cada partida siguiente ese sombreado iba a la CPU (15 fps) | `engine/gpu/src/raster/gles/programs.rs` (`refuse`, `REFUSED_NOW`) | Se reintenta en la próxima sesión |
| 9 | Un enlace fallido solo manda a la CPU **esa combinación**; sin `make_room()` (soltar todas las texturas y programas) cuando el driver no dio motivo | Antes: un fallo mandaba el sombreado de vértices de Link (3674 líneas) a la CPU para todas las combinaciones y vaciaba la caché → parpadeo, mundo que desaparece, 9–15 fps | `engine/gpu/src/raster/gles.rs` | fix6: 100 % de velocidad toda la partida |
| 10 | El traductor directo a AArch64 (`RECOMP_A64`) no toma las funciones del mod ni las del juego que saltan al mod (524 de 13 363); van por C | Los ganchos del mod devuelven flags y retornan a `lr+0xC`; el camino en C está verificado (PC: imagen idéntica a interpretado). Medida de seguridad | `recompiler/src/codegen/a64.rs` (`worth`) | Sin costo medible (probe 127–133 %) |
| 11 | `RECOMP_EXTRA=0` deja el código del mod al intérprete | Para A/B "mod recompilado vs interpretado" | `recompiler/src/image.rs` | Herramienta de diagnóstico |
| 12 | **Scissor de la GPU (PICA `0x065`–`0x067`), modo incluir**: el rectángulo de dibujo se recorta también al scissor, no solo al viewport. Modo excluir: aviso, se dibuja entero | Pocket Native no lo implementaba; Ocarina ReFramed repite los dibujos de la pantalla de abajo sobre la de arriba recortados con scissor → paneles duplicados en la selección de archivo | `engine/gpu/src/raster.rs`, `registers.rs` | Selección de archivo limpia (PC). Útil para cualquier juego que use scissor |
| 13 | `scripts/device/run.sh` exporta `ZAKURO_HIDE_BOTTOM=1` | Con fix5/6 resuelto, saltar la pantalla de abajo sí funciona (la culpa de fix2 era Mali) | kit | Probe: 126–135 % → 131–144 %, hilo gles −7 puntos |
| 7 | Kit: `CARGO_NET_RETRY=10`, `CARGO_HTTP_MULTIPLEXING=false` en el contenedor | La red de Docker Desktop corta descargas de crates | `scripts/build.ps1` | Builds estables |

Para otro juego con un mod de código igual: aplicar el parche, compilar con el kit y listo; los cambios
1–3 son genéricos. El 4 sirve a cualquier juego en "Top only". El 5 sirve para traducciones y mods de RomFS.

## Español
- `games/0004000000033500/data/settings.toml` → `language = 5` (también en el menú: System → Language).
- La ROM USA trae un solo `message/us/us.qm` con inglés, francés y español; el mod solo cambió el inglés.
- El mod cambió texturas solo en `menu/01_US_ENGLISH`; `romfs.patch` las copia a `07_US_SPANISH`
  (`hud_all00`, `cam_interface00`) y `misc/us/spanish/gameover.qsp`. Comparación de originales:
  `cam_interface00` y `gameover.qsp` son idénticos entre inglés y español (copia sin pérdida);
  `hud_all00` no: **las etiquetas del botón de acción salen en inglés** ("Put Away", etc.).
- Comando: `python scripts/romfs_patch.py <rom parchada> romfs.patch /menu/07_US_SPANISH/hud_all00.ctxb=<hud del mod> ...`

## Cómo compilar
Docker Desktop abierto. Para la consola (PowerShell, desde `repos/pocket-native-0.6.1`):
`scripts\build.ps1 <rom parchada> -Out <carpeta> -Precache` (~10 min).
Para el PC: `docker run ... pocket-native-build:<hash> bash /pc/inside_x86.sh /rom/<rom>` (ver `scripts/pc/`).
Si `cargo` o `docker build` fallan por DNS, reintentar: es la red de Docker Desktop, intermitente.

## Cómo probar
- **PC, primero (no gasta tiempo de la consola):** imagen `pn-run:1` (`scripts/pc/Containerfile.run`,
  Ubuntu 24.04 + Mesa llvmpipe) y `scripts/pc/probe.sh NOMBRE CUADROS [VAR=valor]`. El probe del
  propio Pocket Native juega solo (A/Start), llega a la casa de Link en ~10 000 cuadros, guarda 8
  capturas y un informe. `LANG_ID=5 WITH_PATCH=1` para español.
- **Consola, por red:** Tailscale (IPs de Tailscale del PC y la consola en `pocket-native/dev/agent.conf`, no en el repo); la consola va por
  anclaje USB del celular con datos móviles. Trabajo = `work/devserver/job.txt` + `job.sh`.
  Helpers del agente: `fetch`, `send`, `backup`/`restore`, `play NOMBRE SEGUNDOS`, `lastlog`.
- **A/B sin jugar en la consola:** `scripts/pc/job_ab_probe.sh` (probe con `ZAKURO_CLOCK` fijo, datos
  copiados sin la partida del usuario). Mide igual que un jugador pero repetible.

## Mediciones

### fix1-01 (jugando, 8 min, inglés)
| Situación | fps | CPU hilo pocket-native |
|---|---|---|
| Interiores / inicio | 29–30 | 45–55 % |
| Exteriores | 25–30 | 90–95 % |
| Zonas pesadas y menú de pausa | 15 fijo | 99 % |

### ab-fix2-01 (probe, misma ruta, reloj fijo, 14 400 cuadros)
| | fix1 | fix2 |
|---|---|---|
| Tiempo | 282 s | 215 s |
| Velocidad media | 85 % | 111 % |
| Casa de Link (últimos 10 tramos) | 82–85 % | 125–130 % |
| GPU (hilo gles) | 30–36 % | 40–44 % (más cuadros por segundo) |

### Ronda 2: lo que salió mal con fix2 y cómo se arregló
| Versión | Cambio | Resultado jugando |
|---|---|---|
| fix2 | mod recompilado + español + pantalla de abajo oculta | parpadeo, menús duplicados, 9–15 fps tras ~1,5 min |
| fix3 | pantalla de abajo otra vez dibujada | igual (la marca `.refused` de fix2 seguía) |
| fix4 | borrar `.refused` y no marcar fallos sin mensaje | varios enlaces fallidos → `make_room` → parpadeo |
| fix5i | motor fix5 + mod interpretado | sin parpadeo, más lento |
| fix6 | motor fix5 + mod recompilado con ganchos en C | **100 % de velocidad, 23–30 fps, sin parpadeo** |
| **fix7 (instalado)** | + scissor + pantalla de abajo oculta | 100 %, 25–30 fps; probe 131–144 % |

Causa real: el driver Mali no logra enlazar a veces el sombreado de Link (3674 líneas + 789 de color)
y Pocket Native reaccionaba vaciando todo y mandando ese sombreado a la CPU para siempre.
La selección de archivo duplicada ocurre también con el mod interpretado: es de Pocket Native con
este mod, no de nuestros cambios (pendiente).

Diagnóstico en el PC sin consola: `scripts/pc/title_x86.sh <rom> interp RECOMP_EXTRA=0` y
`SO=/pn/title-interp.so probe.sh ...` con `ZAKURO_CLOCK` y `ZAKURO_SHOT_AT` para comparar capturas.

## Pendiente, en orden
1. Medir jugando exteriores (campo de Hyrule) y el menú de pausa con fix6.
1b. ~~Selección de archivo duplicada~~ → arreglado con el scissor (fix7). El recuadro con el inventario táctil en algunas cinemáticas lo dibuja el mod a propósito (sale igual interpretado).
1c. Gatillos L2/R2 (ZL/ZR) que a veces no responden (reportado con fix5i).
2. Opciones del juego en el menú (perfil `titles/0004000000033500/profile.toml`) según esa medición:
   pases caros con `drops_when_off` si la GPU pasa a ser el límite.
3. Etiquetas del botón de acción en español: editar `hud_all00` HD del mod con las del original.
4. Fallos gráficos del menú de pausa (prioridad baja).

Reglas: medir A/B antes y después; preguntar antes de sacrificar imagen o jugabilidad; no publicar
un release sin permiso.
