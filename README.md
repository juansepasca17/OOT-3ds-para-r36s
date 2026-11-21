# OoT3D para R36S (dArkOS RE)

> **Nueva versión (2026-11-21): una pantalla y 30 fps.** Basada en Pocket Native con el mod
> Ocarina ReFramed: 30 fps en interiores, 25–30 en exteriores, HUD en una pantalla y español.
> Descarga e instrucciones: [release pocket-native-fix8](https://github.com/juansepasca17/OOT-3ds-para-r36s/releases/tag/pocket-native-fix8).
> Detalle técnico y cambios al emulador: rama [`pocket-native`](https://github.com/juansepasca17/OOT-3ds-para-r36s/tree/pocket-native), `docs/POCKET_NATIVE.md`.
>
> La versión de abajo (TriAevum, v1.2.1) quedó cerrada el 2026-10-26. Para retomarla: [RETOMAR.md](RETOMAR.md).

Port experimental de **The Legend of Zelda: Ocarina of Time 3D** a la **R36S**
(RK3326, 4× Cortex-A35 a 1.5 GHz, Mali-G31, 1 GB de RAM) con **dArkOS RE**, basado en
[TriAevum](https://github.com/coccofresco/TriAevum) (recompilación nativa AOT de coccofresco),
con el renderer portado a **OpenGL ES 3.2**.

## Ramas

| Rama | Qué es |
|---|---|
| **`pocket-native`** (release `pocket-native-fix8`) | **Recomendada.** Pocket Native + Ocarina ReFramed: una pantalla, 30 fps, español |
| **`estable`** (tag `v1.2.1`) | Versión jugable recomendada: ~15,9 fps de lógica en la R36S, HUD y menú Fn visibles |
| `main` | Igual que `estable` + el benchmark determinista (A5). Plan sin hacer: [RETOMAR.md](RETOMAR.md) |

## Estado (v1.2.1, 2026-10-26)

**Se puede jugar completo.** Va por debajo de los 30 fps originales: el juego corre más lento que en tiempo real.

- ✅ Arranca, menú de inicio, selección de archivo, juego con Link, guardar y cargar.
- ✅ Español (la ROM USA trae inglés, francés y español), una sola pantalla (SingleScreen 3.0).
- ✅ GPU real (Mali-G31, GLES 3.2), CPU y GPU en paralelo, caché persistente de shaders, PGO.
- ✅ **HUD visible** (corazones, rupias, botones) y **menú Fn visible y legible** (v1.2.0).
- ✅ Menú Fn → Game → **R36S performance**: *Half-rate drawing*, *Simple audio*, *Audio stretching* (activados) y *Show FPS* (apagado).
- ✅ Preset gráfico **Toon** (cel-shading) en Fn → Video → Graphics preset.
- ⚠️ Con *Half-rate drawing* la imagen se actualiza a la mitad (~7 fps visibles); se puede apagar.
- ⚠️ Los guardados rápidos (*save states*) del menú no funcionan con OpenGL (solo con Vulkan).

| Versión | ms por frame | fps de lógica | Cambio principal |
|---|---|---|---|
| v1.0.0 | 129 | 7,7 | Port inicial (GLES, paralelo, PGO) |
| v1.1.0 | 82–85 | 12,2 | CPU y GPU en paralelo (`TRIAEVUM_INPUT_ADMISSION=0`) |
| v1.2.0 | 69,8 | 14,3 | Dibujo a medio ritmo + audio simple; HUD y menú arreglados |
| **v1.2.1** | **62,9** | **15,9** | Sin cuadros negros; contador de FPS; audio estirado (−4,5 % si está activo). (MAximos, usualmente va entre 7 y 8 estables, o entre 5 y 7 sin frameskip |

Mediciones en la consola con el agente de pruebas por red, A/B alternado y con audio (demo de la pantalla de título).

### Novedades de la v1.2.1
- **Sin cuadros negros** con el dibujo a medio ritmo: los frames vacíos se detectan por número de dibujos y se
  mantiene la última imagen, como en la pantalla de una 3DS.
- **Contador de FPS** (Fn → Game → R36S performance → Show FPS): velocidad del juego e imágenes por segundo.
- **Audio estirado** (WSOLA, como los emuladores): el sonido no se corta cuando el juego va lento.

### Novedades de la v1.2.0
- **HUD y menú Fn invisibles: arreglado.** La GPU emulada (PICA) dejaba enlazado su *vertex array* y la interfaz
  dibujaba con atributos ajenos que apuntaban a búferes ya borrados; el driver descartaba esos dibujos.
- **Menú legible a 640×480**: texturas de la interfaz con mipmaps y `OOT3D_MENU_SCALE=1.6` en el lanzador.
- **Dibujo a medio ritmo** (+15,8 %): el traductor permite que el host salte `Gameplay_Draw` uno de cada dos
  frames; el frame siguiente no se presenta, así no hay parpadeo negro.
- **Audio simple** (~1 %): mezcla sin interpolación.
- Opciones guardadas en `oot3d/config/r36s_perf.json`.

El detalle de cada prueba está en [docs/BITACORA.md](docs/BITACORA.md); el plan, en [PLAN.md](PLAN.md).
Para portar **otros** juegos a la R36S con ayuda de una IA: [GUIA_PORTEO_R36S.md](GUIA_PORTEO_R36S.md)
y el script de diagnóstico [r36s_info.sh](r36s_info.sh).

## Qué NO contiene este repo

- Ninguna ROM ni datos del juego. Necesitas un volcado **desencriptado** de **tu propio** cartucho
  (USA o Europa; probado con USA Rev 1).
- Ningún binario: el ejecutable contiene el código del juego traducido, así que cada persona debe
  compilarlo con su propia ROM.
- Binarios de terceros con licencia cerrada (libmali se descarga desde su repositorio original).

## Compilar desde cero

Probado en **WSL2 Debian 13 (trixie)** en Windows; el mismo glibc 2.41 que dArkOS RE.
Recomendado: 10 GB de RAM y todos los hilos para WSL (`.wslconfig`).

```bash
# 1. Dependencias (como root en Debian trixie)
dpkg --add-architecture arm64 && apt-get update
apt-get install -y build-essential crossbuild-essential-arm64 cmake ninja-build python3-venv git \
  pkg-config xxd ccache mold qemu-user qemu-user-binfmt nlohmann-json3-dev \
  libsdl2-dev:arm64 libspdlog-dev:arm64 libzip-dev:arm64 libtinyxml2-dev:arm64 zlib1g-dev:arm64 \
  libopusfile-dev:arm64 libgles-dev:arm64 libegl-dev:arm64 libgbm-dev:arm64 libdrm-dev:arm64 \
  libvulkan-dev:arm64 libglew-dev:arm64 libgl-dev:arm64

# 2. Fuentes: TriAevum en el commit fijado, dArkOS y libmali (con SHA-256 verificado)
bash scripts/fetch_sources.sh
git -C repos/TriAevum apply ../../patches/triaevum-r36s.patch
python3 -m venv venv && venv/bin/pip install capstone==5.0.7 numpy Pillow

# 3. Datos de TU ROM (extraer, verificar y adaptar USA → runtime canónico)
venv/bin/python -I scripts/prepare_gamedata.py --repo repos/TriAevum --rom <tu_rom>.cci --out work/gamedata

# 4. IR AOT y 256 archivos C++ del juego (~6 min en total)
bash scripts/wsl/prepare_aot_ir.sh
bash scripts/wsl/generate_cpp.sh

# 5. Compilar para la R36S (~25 min con 12 hilos; luego ccache baja los cambios a segundos)
bash scripts/wsl/build_aarch64.sh      # o build_pgo.sh (ver abajo)

# 6. Armar la carpeta del port
STAGE_MODE=gpu bash scripts/wsl/stage_port.sh work/dist/oot3d
```

Los scripts de `scripts/wsl/` asumen el árbol en `/root/oot3d` (`TriAevum/`, `work/`, `venv/`, `scripts/`);
ajusta `root=` si lo pones en otro lado.

**PGO** (opcional, ~25 % menos de lógica): `PGO_MODE=generate bash scripts/wsl/build_pgo.sh`, jugar
10–15 min en la consola con `GCOV_PREFIX=<carpeta en la SD>`, copiar los `.gcda` de vuelta a sus rutas y
`PGO_MODE=use bash scripts/wsl/build_pgo.sh`.

**Prueba en el PC sin consola:** `scripts/wsl/qemu_smoke.sh` arranca el binario ARM64 en qemu con
OpenGL por software (`STAGE_MODE=software`). `scripts/wsl/glspy.c` detecta llamadas GL hechas sin
contexto (con Mesa pasan desapercibidas, pero en Mali corrompen el driver).

## Instalar en la R36S

Copiar `dist/ports/OOT3D v1.2.1.sh` y la carpeta `dist/ports/oot3d/` a `/roms/ports/` de la SD
(`EASYROMS\ports\` en Windows). Aparece en **Ports → OOT3D v1.2.1**.
- La primera vez compila shaders (unos minutos); quedan guardados en `oot3d/shadercache/`.
- **Select + Start** sale. La partida va en `oot3d/savedata/`.
- `dist/ports/OOT3D-Info.sh` registra los datos de la consola en `ports/oot3d_info.txt`.

## Qué falta (para quien lo retome)

Todo el plan, con pasos, comandos y trampas conocidas, está en [docs/TRADUCTOR_V2.md](docs/TRADUCTOR_V2.md).
La forma de probar rápido (PC, qemu y consola por red) está en [docs/PRUEBAS.md](docs/PRUEBAS.md).

1. **Traductor v2**: el límite es la CPU y el ~38 % es código del juego traducido. Etapas: registros como
   variables locales (T1), flags solo cuando se leen (T3), llamadas por vida de registros (T2), memoria
   directa de 4 GB (T7). `__restrict` ya se probó y no sirve.
2. Descartados por costo/riesgo: frontend PICA en otro núcleo y "menos actores".
3. `mediump` en fragmentos hace caer el compilador de Mali (`llvm.bifrost.fptrunc.te`): no usarlo global.
4. Menú del port en inglés (el juego sí está en español).

Hola soy el del futuro para quien lo retome de verdad, yo no lo voy a hacer realmente ya no.
Use un recompilador mejor, y ya.

Exacto: no encontré un repo del port de OoT como tal. Es una compilación de Pocket Native para ese juego, así que la base es la herramienta y no un proyecto de OoT.

Esta es la lista de herramientas y proyectos que aparecen en el `CREDITS.md` de tu carpeta:

**Cadena principal (de la que sale el port)**
1. [fearkov/zakuro](https://github.com/fearkov/zakuro): emulador de 3DS, la base de todo (MIT).
2. [fearkov/3dsrecomp](https://github.com/fearkov/3dsrecomp): recompilador AOT de fearkov, el que genera el `title.so` (MIT).
3. [WINDROID-EMU/3dsrecomp](https://github.com/WINDROID-EMU/3dsrecomp): de genrogamer, une Zakuro con 3dsrecomp. Pocket Native parte de aquí.
4. [whovian64/pocket-native](https://github.com/whovian64/pocket-native): el fork final, con soporte para handhelds (R36S, Anbernic, etc.) y Android.

**Piezas que usa**
- [Azahar](https://github.com/azahar-emu/azahar): sus listas de compatibilidad sirven para los perfiles por juego en `titles/`.
- [citra_system_archives](https://github.com/B3n30/citra_system_archives) de B3n30 (GPL-2.0): fuente de sistema libre para los juegos que usan la fuente compartida de 3DS.
- [Symphonia](https://github.com/pdeljanix/Symphonia): decodificador de audio AAC (MPL-2.0). El enlace real que da el archivo es `pdeljanic/Symphonia`; revísalo si lo vas a abrir, porque lo cito de memoria del texto.
- M PLUS Rounded 1c: fuente del menú (OFL 1.1).
- Unas 70 crates de Rust, listadas en `THIRD_PARTY_LICENSES.txt`.

**Contribuidores de Pocket Native**: gopnikcosmoslav2077 (port a Android), AeolusUX, iArti, Sekyleky, kxn203, Kvn0l, peuic, sabogalc, trbocode, kadeshar y ecer96.

Corrección sobre el enlace de Symphonia: en `CREDITS.md` aparece como `github.com/pdeljanic/Symphonia`, no como lo escribí arriba. Mejor búscalo por nombre antes de abrirlo.

Lo interesante para tu port: Pocket Native ya resuelve R36S con dArkOS, y tiene perfiles por título (`profile.toml`) y un `run.sh` que maneja KMS, núcleos de CPU y el cambio de VT. Si quieres, comparo su `run.sh` con tu launcher, o miro cómo Pocket Native maneja el rendimiento en R36S.


## Licencia

GPL-3.0-or-later, igual que TriAevum. *The Legend of Zelda* es una marca de Nintendo.
Este es un proyecto de fans, sin afiliación con Nintendo.
