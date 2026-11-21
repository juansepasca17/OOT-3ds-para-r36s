# Cómo compilar OoT3D en una pantalla para la R36S (desde cero)

Resultado: la carpeta `Pocket Native` lista para `/roms/ports/` de la SD. Probado en Windows 11.
Tiempo: ~1 h la primera vez (casi todo descargas), ~10 min las siguientes.

## 0. Lo que hace falta

| Qué | Para qué | De dónde |
|---|---|---|
| ROM USA desencriptada de **tu** cartucho (`.3ds`, SHA-256 `a12d30e6…54cb`) | el juego | tu consola (GodMode9) |
| Docker Desktop | el kit compila dentro de un contenedor Linux | docker.com (gratis para uso personal) |
| xdelta3 | aplicar el parche del mod | github.com/jmacd/xdelta/releases |
| Python 3 | el parche de español (`scripts/romfs_patch.py`) | python.org |
| git | aplicar nuestro parche al kit | git-scm.com |
| Ocarina ReFramed 2.5.1, "Single Screen ROM Patches" | el mod de una pantalla | github.com/OTPR26/OOT3DHud/releases |
| Pocket Native 0.6.1, código fuente | el kit | github.com/whovian64/pocket-native/releases/tag/v0.6.1 |

La forma corta: el kit ya modificado está en el release `pocket-native-fix8`
(`PocketNative-kit-OoT3D-fix8.zip`). Con eso te saltas el paso 2.

## 1. Parchar la ROM con el mod

```powershell
xdelta3 -d -s "tu-rom.3ds" "North-America\patch.xdelta" "rom-reframed.3ds"
```
El resultado debe tener SHA-256 `c90126fe31b94948aa5618801c4582cae9aafaeed3903b2dc29a7e8497148e30`
(`Get-FileHash rom-reframed.3ds`). Si no coincide, tu ROM no es la USA Rev 1 desencriptada.

## 2. Preparar el kit con nuestros arreglos

```powershell
# descomprime pocket-native-0.6.1.zip y entra en la carpeta
git init; git apply ruta\a\patches\pocket-native-0.6.1-reframed.patch
```
Debe aplicarse sin errores (14 archivos). **Nunca ejecutes "Update Pocket Native"**: baja la versión
original y borra los arreglos.

## 3. Compilar

1. Abre Docker Desktop y espera a que diga "Engine running".
2. Arrastra `rom-reframed.3ds` sobre `Build a game.bat`, o en PowerShell, desde la carpeta del kit:
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\build.ps1 "C:\ruta\rom-reframed.3ds" -Out build -Precache
   ```
3. La primera vez arma el contenedor (~2 GB de descarga). Después: recompilador (~1 min), juego
   (~2–7 min) y shaders.
4. Sale `build\Pocket Native\`: el lanzador `.sh` y la carpeta `pocket-native` con
   `games\0004000000033500\` (`title.so`, `game.3ds`, `sysdata`, `vertex`).

Si falla con `Could not resolve host` / `spurious network error`: es la red de Docker Desktop, que
es intermitente. Precarga las librerías y repite:
```powershell
docker run --rm -v "${PWD}:/src:ro" -v pocket-native-work:/work -e CARGO_HOME=/work/cargo -w /src pocket-native-build:6b528ebba1c4 cargo fetch --locked
```

## 4. Configuración para una pantalla

En `build\Pocket Native\pocket-native\config\settings.toml` (créalo si no existe):
```toml
layout = "TopOnly"
right_stick = "CStick"   # stick derecho = cámara libre; L2/R2 = ZL/ZR (ítems del mod)
frame_cap = 30
power = "Performance"
show_fps = true
```
El `run.sh` del kit ya exporta `ZAKURO_HIDE_BOTTOM=1`, para no dibujar la pantalla de abajo.

## 5. Español (opcional)

1. Idioma: `games\0004000000033500\data\settings.toml` → `language = 5`, o en el juego:
   FN → System → Language → Spanish.
2. HUD del mod en español: el mod solo cambió texturas en `menu/01_US_ENGLISH`. Se copian a la
   carpeta del español con un parche de RomFS (no hace falta reconstruir la ROM):
   ```powershell
   python scripts\romfs_ls.py rom-reframed.3ds --extract /menu/01_US_ENGLISH/hud_all00.ctxb hud.ctxb
   python scripts\romfs_ls.py rom-reframed.3ds --extract /menu/01_US_ENGLISH/cam_interface00.ctxb cam.ctxb
   python scripts\romfs_ls.py rom-reframed.3ds --extract /misc/us/english/gameover.qsp gameover.qsp
   python scripts\romfs_patch.py rom-reframed.3ds romfs.patch /menu/07_US_SPANISH/hud_all00.ctxb=hud.ctxb /menu/07_US_SPANISH/cam_interface00.ctxb=cam.ctxb /misc/us/spanish/gameover.qsp=gameover.qsp
   ```
   Copia `romfs.patch` a `games\0004000000033500\data\`. Las etiquetas del botón de acción quedan en
   inglés (vienen dibujadas en la textura HD del mod).

## 6. A la SD

Copia el contenido de `build\Pocket Native\` a `/roms/ports/` y expulsa la SD con seguridad.
La primera vez que arranca compila shaders durante varios minutos (B se lo salta), y los primeros
ratos el modelo de Link tarda unos segundos en verse mientras Mali enlaza su sombreado. Eso se
guarda y no vuelve a pasar.

## 7. Probar sin mover la SD (opcional, para desarrollar)

Ver `docs/POCKET_NATIVE.md` → "Cómo probar": pruebas sin pantalla en el PC (`scripts/pc/`) y en la
consola por red (Tailscale + `scripts/devserver.py` + `PN Dev.sh`).
