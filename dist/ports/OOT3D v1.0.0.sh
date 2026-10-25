#!/bin/bash
# Ocarina of Time 3D (TriAevum) para R36S / dArkOS RE.
# Version 1.0.0 (2026-10-25): PGO + paralelo + memoria en linea + ring de uniforms.
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
echo "== OOT3D prueba 5 $(date) =="

if [ ! -f "$GAMEDIR/game/oot3d_native_process_manifest.json" ]; then
  echo "Faltan los datos del juego en $GAMEDIR/game/"
  exit 1
fi
$ESUDO chmod +x "$GAMEDIR/oot3d_r36s"

CPU_GOV=/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
GPU_GOV=/sys/devices/platform/ff400000.gpu/devfreq/ff400000.gpu/governor
OLD_CPU_GOV=$(cat "$CPU_GOV" 2>/dev/null)
OLD_GPU_GOV=$(cat "$GPU_GOV" 2>/dev/null)
echo performance | $ESUDO tee "$CPU_GOV" >/dev/null 2>&1
echo performance | $ESUDO tee "$GPU_GOV" >/dev/null 2>&1
echo "cpu: $(cat $CPU_GOV) $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)  gpu: $(cat $GPU_GOV 2>/dev/null)"
free -m

# GPU real: SDL del sistema (KMSDRM) + EGL/GLES de Mali. Solo libs propias del juego en libs/.
export LD_LIBRARY_PATH="$GAMEDIR/libs:$LD_LIBRARY_PATH"
export SDL_GAMECONTROLLERCONFIG="${sdl_controllerconfig:-$SDL_GAMECONTROLLERCONFIG}"
# Shaders compilados guardados: la compilación lenta ocurre una sola vez.
mkdir -p "$GAMEDIR/shadercache"
export OOT3D_GL_PROGRAM_CACHE="$GAMEDIR/shadercache"
echo "-- entorno gráfico --"
env | grep -E '^(SDL_VIDEO|EGL|LD_LIBRARY)' | sort

COMMON=(
  --a32-process-manifest "$GAMEDIR/game/oot3d_native_process_manifest.json"
  --resource-root "$GAMEDIR/resources.o2r"
  --config "$GAMEDIR/config/oot3d_native_game.json"
  --controls-config "$GAMEDIR/config/oot3d_controls.json"
  --ui-profile topscreen
  --topscreen-config "$GAMEDIR/config/topscreen_ui.json"
  --topscreen-texture-overrides "$GAMEDIR/config/atlas_overrides.o3tu"
  --save-data "$GAMEDIR/savedata"
  --quick-state "$GAMEDIR/savedata/quick.oot3dsav"
  --renderer opengl
  --gameplay-timing native30_no_interpolation
  --width 640 --height 480
)

# Mensajes en la pantalla de texto (se ven antes de que el juego tome la pantalla).
msg() {
  printf '\033c\n\n  Ocarina of Time 3D - R36S\n\n  %s\n' "$1" | $ESUDO tee /dev/tty1 >/dev/null 2>&1
  echo "[msg] $1"
}
first_run=""
[ -z "$(ls -A "$GAMEDIR/shadercache" 2>/dev/null)" ] && first_run=" Primera vez: compila shaders, puede tardar."

MODE=(--parallel-presentation); export TRIAEVUM_PARALLEL_PRESENTATION=1; mode_name="paralelo"
# El log se vuelca a la SD cada 10 s: sobrevive aunque se apague la consola.
( while sleep 10; do sync; done ) &
SYNC_PID=$!

# 2) Juego normal. Select+Start cierra el juego.
msg "Cargando Ocarina of Time 3D...$first_run (Select+Start: salir)"
sleep 2
echo "---- juego ($mode_name) ----"
if [ -n "$controlfolder" ]; then
  $GPTOKEYB "oot3d_r36s" &
  pm_platform_helper "$GAMEDIR/oot3d_r36s" >/dev/null 2>&1
fi
"$GAMEDIR/oot3d_r36s" "${COMMON[@]}" "${MODE[@]}"
echo "exit code juego: $?"

[ -n "$OLD_CPU_GOV" ] && echo "$OLD_CPU_GOV" | $ESUDO tee "$CPU_GOV" >/dev/null 2>&1
[ -n "$OLD_GPU_GOV" ] && echo "$OLD_GPU_GOV" | $ESUDO tee "$GPU_GOV" >/dev/null 2>&1
kill $SYNC_PID 2>/dev/null
echo "== fin $(date) =="
sync
[ -n "$controlfolder" ] && pm_finish
printf "\033c" > /dev/tty1 2>/dev/null
