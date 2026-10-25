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
