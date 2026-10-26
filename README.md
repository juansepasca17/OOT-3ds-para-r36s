# OoT3D para R36S (dArkOS RE)

Port experimental de **The Legend of Zelda: Ocarina of Time 3D** a la **R36S**
(RK3326, 4× Cortex-A35 a 1.5 GHz, Mali-G31, 1 GB de RAM) con **dArkOS RE**, basado en
[TriAevum](https://github.com/coccofresco/TriAevum) (recompilación nativa AOT de coccofresco),
con el renderer portado a **OpenGL ES 3.2**.

## Ramas

| Rama | Qué es |
|---|---|
| **`estable`** (tag `v1.1.0`) | Versión jugable recomendada: ~11,7 fps en la R36S |
| `main` | Desarrollo: optimizaciones del traductor en curso ([docs/TRADUCTOR_V2.md](docs/TRADUCTOR_V2.md)). Puede estar a medias |

## Estado (v1.0, 2026-10-25)

**Se puede jugar completo**, pero lento: **~7.75 fps** en la intro, un poco menos en Kokiri.

- ✅ Arranca, menú de inicio, selección de archivo, juego con Link, guardar y cargar.
- ✅ Español (la ROM USA trae inglés, francés y español), una sola pantalla (SingleScreen 3.0).
- ✅ GPU real (Mali-G31, GLES 3.2), lógica y dibujo en paralelo, caché persistente de shaders.
- ✅ Optimizado con PGO (perfil tomado en la consola) y acceso a memoria en línea.
- ⚠️ El sonido se entrecorta (el juego corre por debajo de 30 Hz).
- ⚠️ El menú de configuración de TriAevum (Fn o R3) se abre pero no se ve.
- ❌ Sin modo cartoon ni efectos de la versión de PC (son del renderer Vulkan; la R36S no tiene Vulkan).

| Medición en la R36S | Valor |
|---|---|
| Lógica del juego por frame | 61.5 ms (era 89 ms) |
| Frame completo (mediana) | 128.9 ms |
| Espera de GPU por frame | 30–47 ms |
| Límite si no se dibujara nada | 75 ms (~13 fps) |

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

Copiar `dist/ports/OOT3D v1.1.0.sh` y la carpeta `dist/ports/oot3d/` a `/roms/ports/` de la SD
(`EASYROMS\ports\` en Windows). Aparece en **Ports → OOT3D v1.1.0**.
- La primera vez compila shaders (unos minutos); quedan guardados en `oot3d/shadercache/`.
- **Select + Start** sale. La partida va en `oot3d/savedata/`.
- `dist/ports/OOT3D-Info.sh` registra los datos de la consola en `ports/oot3d_info.txt`.

## Qué falta (para quien lo retome)

1. **~65 ms por frame sin identificar en el hilo de dibujo** (aparte de ~40 de GPU y ~22 del backend
   PICA). Sospechosos: UI Fast3D/N64, copias de display, subidas de textura. Medir por fases.
2. **Traductor (fase D):** `--local-state` salió 14 % más lento (descartado). Siguientes ideas: calcular
   solo las flags que se leen y aligerar el costo fijo de `Oot3dAotEnterBlock` por bloque.
3. `mediump` en fragmentos hace caer el compilador de Mali (`llvm.bifrost.fptrunc.te`): no usarlo global.
4. Menú de configuración invisible en GLES; opciones para R36S (resolución, límite de FPS, cartoon liviano).

## Licencia

GPL-3.0-or-later, igual que TriAevum. *The Legend of Zelda* es una marca de Nintendo.
Este es un proyecto de fans, sin afiliación con Nintendo.
