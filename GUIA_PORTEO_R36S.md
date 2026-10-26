# Guía de porteo de juegos a la R36S (con IA)

> Guía general para portar juegos a la **R36S** (Rockchip RK3326) con **ArkOS / dArkOS / dArkOS RE**,
> pensada para pasársela a una IA (Claude Code u otra) al inicio de cada port. Resume lo aprendido
> portando *Ocarina of Time 3D* ([OOT-3ds-para-r36s](https://github.com/juansepasca17/OOT-3ds-para-r36s)).
> No contiene datos personales: los datos de **tu** consola salen de `r36s_info.sh`.

---

## 0. Instrucciones para la IA (léelas primero)

1. **Antes de nada, pide los datos de la consola.** Pide al usuario que corra `r36s_info.sh` (sección 8)
   y que te pase `ports/r36s_info.txt`. No adivines modelo, versión del sistema, drivers ni rutas.
2. **Pregunta cómo se va a probar:**
   - *"¿Puedes conectar la R36S por WiFi (adaptador USB-OTG) y activar SSH?"* → pruebas en 1 minuto, logs directos.
   - Si no: *"Vamos a probar pasando la SD; voy a juntar varias pruebas por cada vuelta y avisarte cuándo
     retirarla."* Minimiza las vueltas (sección 5).
3. **Evalúa la viabilidad con honestidad antes de compilar** (sección 3) y da una estimación de fps.
4. **Primero la prueba de rendimiento (CPU), después los gráficos y el pulido.**
5. **Mide antes de optimizar** y cambia una cosa a la vez.
6. **No borres el entorno de compilación** ni datos del usuario sin confirmación explícita.
7. Si publicas en GitHub: **sin ROMs, sin datos extraídos, sin binarios con código del juego, sin datos
   personales**; revisa antes de cada push.

---

## 1. Hardware de la R36S

| Componente | Dato típico | Consecuencia |
|---|---|---|
| SoC | Rockchip RK3326 | Igual familia que RG351, Odroid Go Advance/Super |
| CPU | 4× Cortex-A35, 1.3–1.5 GHz, en orden | ~10–15× más lento por núcleo que un PC actual: **la CPU suele ser el límite** |
| GPU | Mali-G31 MP2, ~520 MHz | Gama muy baja; **OpenGL ES 3.2** con el driver propietario (libmali) |
| RAM | 1 GB (~900 MB útiles) + zram | Cuidado con assets grandes y texturas |
| Pantalla | 640×480 (algunos paneles a 77 Hz) | 30 fps puede no dividir el refresco: usar limitador propio |
| Controles | D-pad, 2 sticks, ABXY, L1/L2/R1/R2, L3/R3, Select, Start, Fn | Fn suele llegar a SDL como **guide** |
| Arquitectura | aarch64 (+ userspace armhf en muchos sistemas) | armhf si el código asume punteros de 32 bits |

Clones y revisiones (V12, V20, V21…) cambian panel y device tree: por eso el script de diagnóstico.

## 2. Software típico (dArkOS / ArkOS)

- **Base Debian** (dArkOS: trixie, glibc 2.41; ArkOS antiguo: glibc más vieja). Compila contra la misma
  versión (contenedor/WSL de esa Debian) o enlaza estático.
- **GPU por libmali** (blob de ARM) expuesto como `libEGL`/`libGLESv2`. **No hay OpenGL de escritorio.**
  En RK3326 normalmente **no hay Vulkan registrado** aunque el blob exporte símbolos `vk*`.
- **SDL2 del sistema con KMSDRM**: úsalo para la GPU real.
- Puede existir `/etc/profile.d/*.sh` que fuerce `SDL_VIDEO_EGL_DRIVER` → si llevas tu propio EGL, sobrescríbelo.
- **PortMaster** (`control.txt`, `$GPTOKEYB`, `$ESUDO`, `pm_finish`) y ports en `/roms/ports/`
  (en Windows la partición se ve como `EASYROMS`).

## 3. ¿Es viable? Árbol de decisión

1. **¿Ya existe en PortMaster?** (repo PortsMaster/PortMaster-New, `ports.json`). Si sí, usarlo.
2. **Tipo de proyecto:**
   - Decomp / source port nativo → el más viable.
   - Recompilación estática → viable, pero CPU pesada.
   - Solo emulación de consolas modernas (3DS, Switch, PS2…) → no viable en RK3326.
   - Binario x86 cerrado → box64 + gl4es solo si es liviano.
3. **API gráfica:** GLES2/3 = fácil · GL escritorio = gl4es (≤ GL 2.1) o portar · Vulkan = portar a GLES.
4. **CPU:** ms/frame medidos en PC × 10–15 ≈ ms en el A35. 30 fps = 33 ms **en total**.
5. **¿Hay un port ARM ya hecho** (Switch, Android, Raspberry)? Suele ser la mejor base.

## 4. Flujo de trabajo recomendado

| Fase | Qué | Notas |
|---|---|---|
| 0 | Diagnóstico de la consola (`r36s_info.sh`) | Modelo, sistema, driver, SDL, red |
| 1 | Investigar repos y forks recientes | Fijar un commit para reproducibilidad |
| 2 | Entorno de compilación cruzada | WSL2/contenedor con la Debian de la consola, `crossbuild-essential-arm64`, libs `:arm64`, **ccache + mold** |
| 3 | Preparar datos del juego desde el volcado del usuario | Verificar hash y región primero |
| 4 | Compilar aarch64 y **probar en qemu-user** | Libs faltantes y crashes antes de tocar la SD |
| 5 | **Puerta de CPU**: benchmark sin gráficos en la consola | Si no da, decirlo antes de seguir |
| 6 | Renderer GLES 3.2 sobre Mali/KMSDRM | Caché de shaders desde el inicio |
| 7 | Empaquetar estilo PortMaster | `.sh` + carpeta del juego |
| 8 | Optimizar midiendo | Perfil → cambio → medir |

## 5. Protocolo de pruebas (ahorra tiempo y tokens)

**Con WiFi + SSH:** `scp` del binario, ejecutar por SSH, leer logs al instante. Configurarlo vale la pena
si se esperan muchas pruebas.

**Pasando la SD — reglas:**
- **Varias pruebas por vuelta**: el `.sh` ejecuta variantes en secuencia (activadas por variables de entorno),
  cada una con `timeout`, y al final abre el juego.
- **Nunca dejar al usuario esperando a ciegas**: mensaje en pantalla antes de cada fase
  (`printf '...' | sudo tee /dev/tty1`) con duración estimada.
- **Vigilante**: si nada avanza en N segundos, volcar el backtrace de cada hilo al log y cortar.
- **Respaldo**: si la variante nueva falla, abrir la configuración que ya funcionaba.
- **Log persistente**: `( while sleep 10; do sync; done ) &` (apagar con el botón pierde lo no escrito).
- **Conservar datos del usuario** (partidas, caché de shaders) al reemplazar archivos.
- **Verificar la copia** (`cmp`, `diff -rq`) y avisar cuándo puede **expulsar y retirar** la SD.
- **Probar en qemu antes de cada vuelta**: cada error que se escapa cuesta una vuelta completa.

Esqueleto de `.sh` con estas ideas:

```bash
#!/bin/bash
# Lanzador de un port para dArkOS/ArkOS con PortMaster (esqueleto).
if [ -d /opt/system/Tools/PortMaster/ ]; then controlfolder=/opt/system/Tools/PortMaster
elif [ -d /opt/tools/PortMaster/ ]; then controlfolder=/opt/tools/PortMaster
else controlfolder=""; fi
[ -n "$controlfolder" ] && source "$controlfolder/control.txt" && get_controls
ESUDO=${ESUDO:-sudo}
GAMEDIR="$(cd "$(dirname "$0")/mijuego" && pwd)"; cd "$GAMEDIR" || exit 1
> log.txt && exec > >(tee log.txt) 2>&1
( while sleep 10; do sync; done ) & SYNC_PID=$!
msg() { printf '\033c\n\n  %s\n' "$1" | $ESUDO tee /dev/tty1 >/dev/null 2>&1; echo "[msg] $1"; }
echo performance | $ESUDO tee /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor >/dev/null 2>&1
export LD_LIBRARY_PATH="$GAMEDIR/libs:$LD_LIBRARY_PATH"
export SDL_GAMECONTROLLERCONFIG="${sdl_controllerconfig:-$SDL_GAMECONTROLLERCONFIG}"

msg "1/2 Prueba (max 3 min)..."
timeout 180 ./mijuego --benchmark --output bench.json; echo "exit prueba: $?"

msg "2/2 Abriendo el juego (Select+Start: salir)"
[ -n "$controlfolder" ] && $GPTOKEYB "mijuego" &
./mijuego; echo "exit juego: $?"
kill $SYNC_PID 2>/dev/null; sync
[ -n "$controlfolder" ] && pm_finish
```

### Pruebas por red sin SD: servidor de trabajos + agente (probado)

Funciona aunque la consola no tenga WiFi: **anclaje USB del celular** (el celular conectado al WiFi de la
casa) → la consola sale por `usb0` y llega a la PC. La PC **no** puede entrar a la consola (red del
celular aparte), así que la conexión la inicia la consola:

- **PC:** `python scripts/devserver.py` (puerto 8765, token en `work/devserver/token.txt`). El trabajo
  actual es `job.txt` (id) + `job.sh`; los archivos van en `files/` (comprimir con gzip: el binario de
  148 MB baja a 47 MB); los resultados llegan a `results/<id>/`; `heartbeat.txt` muestra si el agente vive.
- **Consola:** `OOT3D Dev.sh` en Ports (lee `oot3d/dev/agent.conf` con `SERVER` y `TOKEN`). Consulta cada
  20 s, ejecuta cada trabajo nuevo una vez, sube `job.log` + `out/*`. Start cierra (solo en espera).
  Helpers para los trabajos: `fetch NOMBRE DESTINO [sha256]`, `send ARCHIVO`, `oot3d_env`.
- **Firewall de Windows:** aunque Python figure "permitido", la red como **Pública** descartaba la
  entrada. Diagnóstico rápido: desde WSL `curl http://<IP-PC>:8765/ping` (timeout = bloqueado,
  403 = abierto). Solución (el usuario, en cmd de administrador):
  `netsh advfirewall firewall add rule name="OOT3D devserver" dir=in action=allow protocol=TCP localport=8765 remoteip=localsubnet,10.0.0.0/8 profile=any`
- Velocidad medida por anclaje USB: **~0.46 MB/s** → enviar solo lo que cambió y comprimido.
- dArkOS RE trae **Tailscale** (`tailscale0`): instalándolo también en la PC, funcionaría desde cualquier red.

## 6. Errores a evitar

**Compilación y entorno**
- Usar **ccache + mold** desde el inicio; subir RAM/hilos del entorno (`.wslconfig` en Windows).
- No restaurar el repo y re-aplicar parches entre compilaciones: cambia fechas y recompila todo.
  Copiar solo los archivos que cambiaron.
- En Windows/Git Bash: `MSYS_NO_PATHCONV=1` al pasar rutas Linux a `wsl.exe`; normalizar CRLF
  (`sed 's/\r$//'`) en scripts que corren en Linux; escribir código con un editor, no con heredocs
  (los `\n` pueden convertirse en saltos reales).
- `/tmp` del entorno puede borrarse al reiniciarlo: guarda resultados en disco.

**OpenGL ES en Mali**
- **Ninguna llamada GL desde un hilo sin el contexto actual.** Mesa la ignora; **Mali se corrompe y cuelga**.
  Detectarlo en el PC con un shim `LD_PRELOAD` que intercepte `gl*` y avise si
  `eglGetCurrentContext() == EGL_NO_CONTEXT`.
- Si el contexto vive en un hilo de render, **todo** lo que dibuja (UI incluida, ej. ImGui) debe ir ahí.
- `precision mediump` global en fragment shaders puede **hacer caer el compilador de Mali**.
- En GLES no existen `glDrawBuffer`, `glClearDepth`, logic ops ni `GL_TEXTURE_LOD_BIAS`; las texturas para
  `glBindImageTexture` deben ser inmutables (`glTexStorage2D`); shaders con `#version 3x0 es` y
  `precision` explícita para enteros e imágenes.
- **Caché de binarios de shaders** (`glProgramBinary`) desde el día uno: compilar en Mali tarda segundos.
- Para probar sin pantalla con Mesa: SDL `offscreen`, `EGL_PLATFORM=surfaceless`, `SDL_HINT_EGL_DEVICE`
  apuntando al dispositivo de software y `SDL_VIDEO_EGL_DRIVER` al EGL propio.

**Rendimiento**
- Separar **lógica**, **CPU del renderer** y **GPU**: variante sin dibujar + `glFinish` cronometrado.
- Paralelizar lógica/dibujo solo rinde si el dibujo no domina.
- **PGO (GCC)**: perfil tomado en la consola con `GCOV_PREFIX`, volcado periódico (`__gcov_dump` +
  `__gcov_reset`) porque los ports se cierran matándolos; usar con `-fprofile-correction`.
- Opciones experimentales de compiladores/recompiladores: medir en el PC (x86) y verificar resultados
  idénticos antes de llevarlas a la consola.

**Rendimiento: lo que más rindió (caso OoT3D, de 7,7 a ~16 fps de lógica en benchmark)**
- **Que la CPU y la GPU trabajen a la vez.** Si cada frame espera a que el anterior se presente, sus tiempos
  se **suman**. Con dos hilos (lógica + render) y sin esa espera: **+71 %**. Pista: ningún hilo al 100 % y
  `glFinish` esperando decenas de ms.
- **Medir antes de optimizar shaders.** Variantes de diagnóstico (fragmento plano, scissor 1×1, sin sombras)
  dicen si el costo es de píxeles, de vértices o de CPU. Cuando la CPU es el límite, la GPU no importa.
- **Frameskip "de juego":** saltarse la función que *prepara* el dibujo uno de cada dos frames ahorra CPU
  (+16 %). Trampas:
  - la consola original presenta la imagen **un frame después** de dibujarla, y ese desfase **cambia**
    entre escenas (menús frente a partida): no adivinar qué frame ocultar;
  - detectar el frame vacío por **su contenido** (número de dibujos: 1–4 frente a decenas) y mantener la
    última imagen, como hace la pantalla real; nunca ocultar dos seguidos, para no congelar escenas pobres.
- **Medir con una escena de partida, no con la demo del menú.** La demo daba ~16 fps y la partida real 7–9.
- Clasificar un perfil por **espacio de nombres** engaña: verificar qué funciones caen en cada categoría
  antes de estimar una ganancia (una "coma flotante 7 %" resultó ser ~1,5 %).
- `__restrict` en el estado de un recompilador estático no sirve si cada acceso a memoria tiene una ruta lenta
  con llamada: el compilador asume que la llamada puede tocar el estado.
- En un generador de código, cambiar **una sola función** (p. ej. una "compuerta" a la entrada) recompila un
  archivo, no todos: diseñar los cambios para no tocar cabeceras incluidas por todo el código generado.

**Estado GL compartido entre subsistemas**
- Si dos partes del renderer usan GL (escena emulada + interfaz), cada una debe **restaurar su VAO** y sus
  atributos. Un VAO ajeno con atributos activos que apuntan a búferes borrados hace que el driver **descarte
  dibujos en silencio**: el HUD y el menú "funcionaban pero no se veían".
- Interfaz diseñada para 1080p en una pantalla de 640×480: generar **mipmaps** de las texturas de UI (si no,
  las letras reducidas 10× desaparecen) y una **escala** de interfaz configurable.
- Depurar UI sin mando: una variable de entorno que abra el menú en el frame N + `--screenshot-sequence`.
  Si en el emulador se ve pero en la consola no, mirar estado GL y driver; si tampoco se ve, es código.

**Audio**
- Si el juego va más lento que el tiempo real, el audio se corta. Técnica de emuladores: **estiramiento de
  tiempo (WSOLA)**, que alarga el sonido sin cambiar el tono. Hacer barata la búsqueda de empalme (rango
  corto, muestreo espaciado): la primera versión costó 9 % y la ajustada 4,5 %.
- Desactivar la interpolación del mezclador es casi gratis y apenas se nota.

**Determinismo (para comparar versiones en el PC)**
- Correr dos veces el mismo binario y comparar la huella de memoria. Si difieren, repetir con `setarch -R`
  (sin ASLR): si entonces coinciden, se cuelan **direcciones del host** en la memoria del juego.
- Localizar con hashes por página de 4 KiB y comparar bytes. Caso real: un struct del DSP de audio sin
  inicializar copiaba su relleno (basura de pila) a la memoria compartida.

**Pruebas en la consola**
- Un trabajo = muchas variantes **alternadas** (A, B, A, B) y una tabla automática al final; diferencias < 3 %
  son ruido salvo que se repitan.
- Al sincronizar fuentes con otro entorno, incluir los archivos **revertidos** (ya no salen en `git diff`).
- Publicar el id del trabajo **después** de escribir el script; revisar que el script es el nuevo.
- Las subidas por anclaje USB pueden colgarse: tiempo límite y reintentos.

**Comunicación**
- Decir los fps esperados desde el principio; distinguir "probado en consola" de "probado en emulador".
- Toda opción que cambie la experiencia (frameskip, audio) va al menú del juego, activable y desactivable.

## 7. Herramientas útiles

`qemu-aarch64` + binfmt · Mesa llvmpipe · shim `LD_PRELOAD` para GL · vigilante con backtraces
(`tgkill` + `backtrace_symbols_fd`) · `addr2line -f -C` · `nm -D`/`objdump` del driver · `perf` en x86 ·
ccache · mold · **perf para arm64 en la consola** (paquete Debian + librerías, `-e cpu-clock:u`, símbolos
con `--symfs` en el PC) · capturas `--screenshot-sequence` · registro de transferencias de pantalla.

En este repo: `scripts/devserver.py` + agente `OOT3D Dev.sh` (pruebas por red; funciones `bench`, `perfrec`),
`scripts/wsl/console_build.sh` (compilar y empaquetar en un paso), `scripts/summarize_results.py` (tabla A/B),
`scripts/wsl/det_run.sh` (huella determinista) y `docs/PRUEBAS.md` (protocolo completo).

## 8. Script de diagnóstico de la consola

`r36s_info.sh` (en este repo) solo **lee** información. Copiarlo a `ports/`, abrirlo desde **Ports** y
pasarle `ports/r36s_info.txt` a la IA. Incluye: sistema y versión, modelo/device tree, CPU, RAM/zram,
GPU y driver (libmali, Vulkan, DRI), variables gráficas forzadas por el sistema, SDL2, userspace armhf,
pantalla, controles, PortMaster, **red y SSH** (para decidir el protocolo de pruebas) y almacenamiento.

## 9. Prompt de arranque

```text
Quiero portar <JUEGO> a mi R36S. Lee primero GUIA_PORTEO_R36S.md.
1. Pídeme ports/r36s_info.txt (r36s_info.sh) antes de asumir nada de la consola.
2. Pregúntame si pruebo por WiFi+SSH o pasando la SD, y adapta las pruebas.
3. Busca ports existentes (PortMaster, ARM, Android, Switch) y evalúa la viabilidad con fps estimados.
4. Primero una prueba de rendimiento de CPU en la consola; los gráficos y el pulido después.
5. Junta varias pruebas por vuelta de SD, con mensajes en pantalla, timeouts y respaldo.
6. Publica sin ROMs, binarios del juego ni datos personales. No borres el entorno sin mi confirmación.
```
