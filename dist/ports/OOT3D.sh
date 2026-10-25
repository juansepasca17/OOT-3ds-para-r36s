#!/bin/bash
# Ocarina of Time 3D (TriAevum) para R36S / dArkOS RE.
# Copiar este archivo y la carpeta "oot3d" a /roms/ports/ (o /roms2/ports/ con dos SD).

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

# PortMaster (opcional): da GPTOKEYB, info del dispositivo y pm_finish.
if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder=""
fi
[ -n "$controlfolder" ] && source "$controlfolder/control.txt" && get_controls

GAMEDIR="$(cd "$(dirname "$0")/oot3d" && pwd)"
cd "$GAMEDIR" || exit 1
exec > "$GAMEDIR/log.txt" 2>&1
echo "== OOT3D $(date) =="

if [ ! -f "$GAMEDIR/game/oot3d_native_process_manifest.json" ]; then
  echo "Faltan los datos del juego en $GAMEDIR/game/" | tee /dev/tty1
  sleep 5
  exit 1
fi

# Rendimiento: los 4 núcleos al máximo mientras se juega.
CPU_GOV=/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
GPU_GOV=$(ls /sys/devices/platform/*gpu*/devfreq/*/governor 2>/dev/null | head -n1)
OLD_CPU_GOV=$(cat "$CPU_GOV" 2>/dev/null)
OLD_GPU_GOV=$([ -n "$GPU_GOV" ] && cat "$GPU_GOV")
echo performance | sudo tee "$CPU_GOV" >/dev/null 2>&1
[ -n "$GPU_GOV" ] && echo performance | sudo tee "$GPU_GOV" >/dev/null 2>&1

export LD_LIBRARY_PATH="$GAMEDIR/libs:$LD_LIBRARY_PATH"
export SDL_VIDEODRIVER=KMSDRM
export SDL_GAMECONTROLLERCONFIG_FILE="${sdl_controllerconfig:-/opt/inttools/gamecontrollerdb.txt}"

"$GAMEDIR/oot3d_r36s" \
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
  --width 640 --height 480

# Restaurar governors.
[ -n "$OLD_CPU_GOV" ] && echo "$OLD_CPU_GOV" | sudo tee "$CPU_GOV" >/dev/null 2>&1
[ -n "$GPU_GOV" ] && [ -n "$OLD_GPU_GOV" ] && echo "$OLD_GPU_GOV" | sudo tee "$GPU_GOV" >/dev/null 2>&1
[ -n "$controlfolder" ] && pm_finish
printf "\033c" > /dev/tty1
