# Prompt mejorado — Port de Ocarina of Time 3D (TriAevum) a R36S con dArkOS RE

> Usa este texto para retomar el proyecto en una sesión nueva o para dárselo a otro agente.

---

## Objetivo

Portar **TriAevum** (recompilación nativa AOT de *The Legend of Zelda: Ocarina of Time 3D*, repo
`coccofresco/TriAevum`) a una consola **R36S** con **dArkOS RE** (`southoz/dArkOSRE-R36`, basado en
dArkOS de christianhaitian, Debian *trixie*). La entrega es una carpeta lista para copiar a la
tarjeta SD (`ports/oot3d/` + `OOT3D.sh`) que se lance desde el menú *Ports* de EmulationStation.

## Hardware y sistema de destino (no negociable)

| Elemento | Valor |
|---|---|
| SoC | Rockchip RK3326, 4× Cortex-A35 a 1.5 GHz (en orden, 32 KB de caché L1-I) |
| RAM | 1 GB compartida con la GPU |
| GPU | Mali-G31 MP2, driver **libmali blob** `libmali-bifrost-g31-rxp0-gbm.so` → **solo OpenGL ES 3.2 + EGL/GBM (KMSDRM)**. No hay OpenGL de escritorio, ni Vulkan, ni X11 |
| Pantalla | 640×480 |
| SO | dArkOS RE (Debian trixie aarch64, glibc 2.41, userspace armhf opcional), SDL2 propio compilado con KMSDRM |
| Controles | D-pad, 2 sticks analógicos, A/B/X/Y, L1/L2/R1/R2, L3/R3, Select, Start, Fn |

## Entrada del usuario

- ROM propia: `rom/Legend of Zelda, The - Ocarina of Time 3D (USA) (En,Fr,Es) (Rev 1).cci`
  - Desencriptada (NCCH NoCrypto), `CTR-P-AQEE`, Title ID `0004000000033500`.
  - SHA-1 `50d6b33de7298d397fa9f0dde78f8b0f23256564` = No-Intro USA Rev 1 (registro 1259), versión que TriAevum soporta.

## Requisitos de producto

1. **Rendimiento: 30 fps estables como mínimo** en juego normal (Kokiri, Campo de Hyrule, mazmorras).
   El juego original de 3DS corre a 30 Hz, así que 30 fps equivale a velocidad completa.
2. **Una sola pantalla**: perfil TopScreen con el atlas SingleScreen 3.0 que trae el repo
   (inventario, mapa y ocarina en la pantalla superior, sin pantalla táctil).
3. **Modo cartoon** (*toon shading* + contorno) como en la versión de PC, reimplementado en GLES
   con un costo que respete los 30 fps. Se puede activar o desactivar.
4. **Menú de configuración** accesible con un combo de botones, con opciones de calidad de vida:
   resolución interna, toon y contorno, contador de FPS, salto de frames, sombras, filtrado,
   cámara invertida, botones de objetos (D-pad y gatillos), autoguardado, guardado rápido, brillo y gamma.
5. **Lanzador `.sh`** compatible con PortMaster y dArkOS: governor de CPU en *performance*,
   variables de SDL, log en `log.txt`, salida limpia con Select+Start.
6. Nada de código ni assets de Nintendo en el repositorio. Los datos del juego se extraen de la ROM
   del usuario y solo se guardan en su carpeta privada.

## Restricciones técnicas conocidas (verificadas en el código, oct 2026)

- TriAevum genera **12,419 funciones C++** (256 *shards*) a partir de `code.bin` + ExHeader de la ROM
  (`tools/oot3d/native_a32_runtime/generate_whole_aot_cpp.py`, Forge `tools/triaevum_release/forge.py`).
- Ya existe un **port ARM64 a Switch** (`scripts/switch/*`, SDL2 + OpenGL, sin Vulkan) y uno a
  **Android** (Vulkan). El de Switch es la plantilla: `-DOOT3D_ENABLE_VULKAN_RENDERER=OFF`,
  `-DOOT3D_WHOLE_AOT_PRODUCT_MODE=ON`.
- El backend OpenGL PICA (`runtime/three_ds_recomp/src/fast/backends/gfx_opengl_pica.cpp`,
  `renderer3ds/pica_gl_shader_dialect.cpp`) usa **GLSL 4.30 de escritorio** con SSBO `std430`:
  hay que traducirlo a **GLSL ES 3.20**.
- El *toon shading* y el contorno solo existen en el backend Vulkan: hay que portarlos.
- Costo de CPU medido por el proyecto en un PC de escritorio: unos 5.3 ms por actualización
  (4.75 ms de ejecución AOT). En un A35 eso equivale a unos 60–80 ms, **2 a 3 veces por encima del
  presupuesto de 33 ms**. El generador AOT necesita optimizaciones fuertes: fastmem sin
  comprobaciones de límites, menos tráfico de flags, despacho directo, `-mcpu=cortex-a35`, PGO y
  LTO, y orden del código pensado para la caché de instrucciones.

## Forma de trabajo

- Compilar de forma cruzada en **WSL2 Debian trixie** (clang + sysroot arm64 multiarch), con el
  mismo glibc que dArkOS.
- Construir primero una **referencia x86-64** en WSL (OpenGL vía WSLg) para crear savestates
  deterministas y comparar resultados.
- **Puerta de rendimiento antes de pulir**: medir ms por actualización de la lógica en la R36S
  real con un renderer nulo y un savestate. No avanzar a pulir gráficos hasta bajar de unos 25 ms.
- Cada paso deja evidencia: logs, hashes y mediciones, en `docs/BITACORA.md`.
- Si algún objetivo resulta imposible, decirlo con números y proponer alternativas
  (20–25 fps estables, menor resolución, salto de frames), en lugar de fingir que se cumplió.
