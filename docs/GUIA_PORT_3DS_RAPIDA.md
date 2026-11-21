# Guía rápida: portar un juego de 3DS a la R36S con Pocket Native

Lo aprendido con OoT3D (fix1 → fix8), ordenado para que el próximo juego (Majora's Mask 3D,
Mario & Luigi, etc.) salga en 2–3 versiones y no en 8. Es para una IA o una persona que retome.

## Regla de oro: medir en el PC, confirmar en la consola

Una versión en la consola cuesta ~30 min (compilar, mandar, jugar, leer el log). En el PC, un probe
sin pantalla cuesta 2 min y es repetible. **Ninguna versión va a la consola sin haber pasado el
probe del PC** con capturas en los mismos cuadros (`ZAKURO_CLOCK` + `ZAKURO_SHOT_AT`).

## 0. Antes de empezar (10 min, decide si vale la pena)

| Pregunta | Dónde mirarlo | Si sale mal |
|---|---|---|
| ¿Pocket Native lo corre? | `docs/compatibility.md` del kit, `titles/<id>/profile.toml` | "Broken" = presupuesta mucho más trabajo |
| ¿Hay mod de una pantalla? ¿Es parche de ROM o fork de emulador? | GBAtemp, GameBanana, GitHub del mod | fork de emulador = hay que portar su lógica, mucho más caro |
| ¿El mod pone código propio pasada la sección `.data`? (exheader con `.bss` agrandada, `code.ips` grande) | `romfs_ls.py` y el exheader | con nuestro parche ya funciona |
| ¿Qué región? | ver abajo | — |

**Región (europea o americana):** para Pocket Native da igual en rendimiento (la 3DS no tiene 50 Hz).
Elige por **mods y perfiles**: usa la región que el mod soporte mejor y que tenga perfil en `titles/`.
Idioma: la USA suele traer inglés/francés/**español latino**, y la EUR inglés/alemán/francés/italiano/
**español de España**. Ojo: los mods de HUD suelen cambiar **solo las texturas en inglés** (como
ReFramed), así que en cualquier región el español necesita un `romfs.patch` como el de OoT3D.

## 1. Montaje (una vez por PC, ya hecho en este)

- Docker Desktop, kit Pocket Native 0.6.1 + `patches/pocket-native-0.6.1-reframed.patch`.
- Imagen `pn-run:1` para probar en el PC (`scripts/pc/Containerfile.run`).
- Tailscale en el PC y en la consola: el anclaje USB del celular **no deja** que la consola vea el
  PC por la red de la casa. Firewall: permitir Python en redes privadas.
- `scripts/devserver.py` + `PN Dev.sh` en la consola (cambiar `TITLE` en el `.sh` para otro juego).

## 2. Primera versión (v1): base sin mods

1. Compila la ROM sin mod con el kit (`scripts\build.ps1 rom.3ds -Out build -Precache`).
2. PC: `scripts/pc/inside_x86.sh` + `probe.sh base 21600` → ¿arranca? ¿llega a jugar? Mira 8 capturas.
3. Consola: un trabajo `play` de 15 min. Del log saca la velocidad, el hilo `pocket-native` (CPU),
   `waiting on gpu` (GPU) y los avisos (`unimplemented svc`, `could not link`, `letting go`).

## 3. Segunda versión (v2): con el mod, todo junto

1. Parcha la ROM (xdelta) y compila con nuestro parche (ya trae los SVC 0x33/0x70, el código del mod
   recompilado, el scissor y las protecciones contra los fallos de Mali).
2. PC, A/B obligatorio: `title_x86.sh rom mod` y `title_x86.sh rom interp RECOMP_EXTRA=0`. Probe a
   los dos con el mismo reloj y compara capturas. Si difieren en algo más que partículas, el código
   del mod se traduce mal: revisa sus ganchos (`hooks.s`: flags, `lr` modificado).
3. Consola: probe A/B sin jugar (`scripts/pc/job_ab_probe.sh`) + una partida en el mismo trabajo.

## 4. Señales en el log y qué hacer

| Señal | Causa | Arreglo (ya en el parche, o qué tocar) |
|---|---|---|
| `unimplemented svc 0x..` y luego `svcBreak` | SVC que el juego o el mod necesita | implementarlo en `engine/core/src/kernel/svc.rs` |
| el mod salta a memoria vacía | código del mod pasado `.data` | el cargador lo copia a `.bss` (cambio 2) |
| `interpreted X%` alto | código fuera de `.text` | el recompilador lo toma (cambio 3) |
| `could not link a program,` con mensaje vacío | Mali no enlaza un sombreado largo | solo esa combinación va a la CPU (cambios 8–9) |
| `letting go of N textures` | lo de arriba sin el parche: parpadeo y 15 fps | cambio 9 |
| paneles duplicados o menús fuera de lugar | el juego o el mod usa el scissor de la GPU | cambio 12 (`ZAKURO_SCISSOR_LOG=1` para ver los recortes) |
| `waiting on gpu` > 20 % y GPU a ~400 MHz | límite de GPU y temperatura | `ZAKURO_HIDE_BOTTOM=1`, `drops_when_off` en el perfil |
| CPU `pocket-native` 99 % y 15 fps fijos | límite de CPU | código interpretado, `perf`, overrides en C |
| `bottom screen skipping off, both screens` | un mod que compone las dos pantallas | normal; usar `ZAKURO_HIDE_BOTTOM=1` |

## 5. Lo que NO hacer (costó versiones en OoT3D)

- Juntar en una versión un cambio de rendimiento con uno de imagen sin el A/B del PC. fix2 mezcló
  tres cambios y luego costó tres versiones saber cuál rompía qué.
- Culpar al último cambio sin leer el log completo: el parpadeo de fix2 era Mali, no la pantalla de
  abajo.
- Fiarse de 8 capturas: el probe no abre menús. Pide al usuario una partida corta en los menús.
- Dejar que la consola se apague por el anclaje: avisar antes de mandar trabajos largos.

## 6. Notas por juego

- **Majora's Mask 3D:** mismo motor que OoT3D, y Pocket Native ya lo jugó en un Miyoo Flip (GPU más
  fuerte que la R36S). El mod de una pantalla conocido es **un fork de Azahar**, no un parche de ROM,
  así que primero busca si OTPR26 u otro sacó una versión como parche de código. Espera el mismo
  sombreado pesado de Link (fallos de Mali) y el mismo uso de scissor: el parche actual debería
  servir casi tal cual.
- **Mario & Luigi:** *Dream Team* figura como **Broken** (pantalla negra, reporte 0.2, viejo:
  reprobar). *Paper Jam*, *Superstar Saga + Bowser's Minions* y *Bowser's Inside Story + Bowser Jr.*
  tienen perfil pero ningún reporte. Son juegos 2D/2.5D con mucha pantalla táctil: la versión de una
  pantalla dependerá de un mod (o de mapear toques a botones en el perfil). Empieza por v1 (sin mod)
  para ver si arranca.

## 7. Modelo y esfuerzo

Opus en esfuerzo high para el /goal. Sube a xhigh solo para diagnosticar (comparar logs, leer el
recompilador). El trabajo mecánico (empaquetar, documentar) lo hace cualquier modelo.
