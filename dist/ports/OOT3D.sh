#!/bin/bash
# Ocarina of Time 3D (TriAevum) para R36S / dArkOS RE.
# FASE ACTUAL: prueba de rendimiento de CPU (sin imagen). Corre ~1-3 minutos y vuelve al menú.
# Copiar este archivo y la carpeta "oot3d" a /roms/ports/.

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder=""
fi
if [ -n "$controlfolder" ]; then
  source "$controlfolder/control.txt"
  [ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
  get_controls
fi
ESUDO=${ESUDO:-sudo}

GAMEDIR="$(cd "$(dirname "$0")/oot3d" && pwd)"
cd "$GAMEDIR" || exit 1
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1
echo "== OOT3D benchmark $(date) =="

if [ ! -f "$GAMEDIR/game/oot3d_native_process_manifest.json" ]; then
  echo "Faltan los datos del juego en $GAMEDIR/game/"
  exit 1
fi
$ESUDO chmod +x "$GAMEDIR/oot3d_r36s"

CPU_GOV=/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
OLD_CPU_GOV=$(cat "$CPU_GOV" 2>/dev/null)
echo performance | $ESUDO tee "$CPU_GOV" >/dev/null 2>&1
echo "cpu governor: $(cat $CPU_GOV) freq: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)"
free -m

# Sin pantalla: SDL offscreen + OpenGL por software (Mesa llvmpipe) incluidos en libs/.
export LD_LIBRARY_PATH="$GAMEDIR/libs:$LD_LIBRARY_PATH"
export SDL_VIDEODRIVER=offscreen
export SDL_AUDIODRIVER=dummy
export __EGL_VENDOR_LIBRARY_FILENAMES="$GAMEDIR/libs/egl_vendor.d/50_mesa.json"
export LIBGL_DRIVERS_PATH="$GAMEDIR/libs/dri"
export EGL_PLATFORM=surfaceless
# En dArkOS libEGL.so apunta a libMali: forzar el EGL/GL incluidos.
export SDL_VIDEO_EGL_DRIVER="$GAMEDIR/libs/libEGL.so.1"
export SDL_VIDEO_GL_DRIVER="$GAMEDIR/libs/libGL.so.1"
export GALLIUM_DRIVER=llvmpipe
export LIBGL_ALWAYS_SOFTWARE=1
export LP_NUM_THREADS=2
export MESA_GL_VERSION_OVERRIDE=4.5
export MESA_GLSL_VERSION_OVERRIDE=450
# El contexto GL vive en el hilo principal: presentación en serie.
export TRIAEVUM_PARALLEL_PRESENTATION=0

echo "-- entorno gráfico --"
env | grep -E '^(SDL_|EGL|__EGL|LD_LIBRARY|LIBGL|GALLIUM|MESA)' | sort
grep -rsE 'SDL_|EGL' /etc/environment /etc/profile.d/ 2>/dev/null | head -n 20

run_bench() {
  local name=$1; shift
  echo "---- $name ----"
  local timer=""
  [ -x /usr/bin/time ] && timer="/usr/bin/time -v"
  $timer "$GAMEDIR/oot3d_r36s" \
    --a32-process-manifest "$GAMEDIR/game/oot3d_native_process_manifest.json" \
    --resource-root "$GAMEDIR/resources.o2r" \
    --config "$GAMEDIR/config/oot3d_native_game.json" \
    --controls-config "$GAMEDIR/config/oot3d_controls.json" \
    --ui-profile topscreen \
    --topscreen-config "$GAMEDIR/config/topscreen_ui.json" \
    --topscreen-texture-overrides "$GAMEDIR/config/atlas_overrides.o3tu" \
    --save-data "$GAMEDIR/savedata" \
    --quick-state "$GAMEDIR/savedata/quick.oot3dsav" \
    --renderer opengl \
    --gameplay-timing native30_no_interpolation \
    --throughput-benchmark \
    --disable-audio --serial-presentation \
    --width 400 --height 240 \
    --output "$GAMEDIR/bench_$name.json" "$@"
  echo "exit code: $?"
  [ -f "$GAMEDIR/bench_$name.json" ] && cat "$GAMEDIR/bench_$name.json"
}

# Arranque + intro del título (Link cabalgando por el Campo de Hyrule).
run_bench intro --frames 900 --benchmark-warmup-frames 300

[ -n "$OLD_CPU_GOV" ] && echo "$OLD_CPU_GOV" | $ESUDO tee "$CPU_GOV" >/dev/null 2>&1
echo "== fin $(date) =="
sync
[ -n "$controlfolder" ] && pm_finish
