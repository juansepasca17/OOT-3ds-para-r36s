#!/bin/bash
# Recopila informacion de la R36S para el port de OoT3D. Solo lee, no cambia nada.
# Resultado: oot3d_info.txt junto a este archivo (carpeta ports de la SD).

OUT="$(cd "$(dirname "$0")" && pwd)/oot3d_info.txt"
exec > "$OUT" 2>&1

section() { printf '\n===== %s =====\n' "$1"; }

section "fecha"; date
section "sistema"
cat /etc/os-release 2>/dev/null
cat /usr/share/plymouth/themes/text.plymouth 2>/dev/null | grep -i title
ls /home/ark/.config/.VERSION* /usr/share/dArkOS* 2>/dev/null
cat /home/ark/.config/.VERSION 2>/dev/null
uname -a
section "glibc"; ldd --version 2>/dev/null | head -n1
section "modelo / device tree"
tr -d '\0' < /proc/device-tree/model 2>/dev/null; echo
tr -d '\0' < /proc/device-tree/compatible 2>/dev/null; echo
ls /boot/*.dtb 2>/dev/null
cat /boot/boot.ini 2>/dev/null | grep -iE "dtb|fdt"
section "cpu"
lscpu 2>/dev/null
for p in /sys/devices/system/cpu/cpu0/cpufreq/*; do
  [ -f "$p" ] && printf '%s: %s\n' "$(basename "$p")" "$(cat "$p" 2>/dev/null)"
done
section "memoria"; free -m; cat /proc/swaps; ls /sys/block | grep zram
section "gpu"
ls /sys/devices/platform/ | grep -i gpu
for f in /sys/devices/platform/*gpu*/devfreq/*/{available_frequencies,available_governors,governor,max_freq}; do
  [ -f "$f" ] && printf '%s: %s\n' "$f" "$(cat "$f")"
done
ls -l /usr/lib/aarch64-linux-gnu/libMali* /usr/lib/aarch64-linux-gnu/libmali* \
      /usr/lib/aarch64-linux-gnu/libGLESv2* /usr/lib/aarch64-linux-gnu/libEGL* 2>/dev/null
section "sdl2"
ls -l /usr/lib/aarch64-linux-gnu/libSDL2* 2>/dev/null
section "pantalla"
cat /sys/class/graphics/fb0/virtual_size 2>/dev/null
cat /sys/class/drm/*/modes 2>/dev/null
section "controles"
cat /proc/bus/input/devices 2>/dev/null | grep -E "^N:|^H:"
section "portmaster"
ls -d /opt/system/Tools/PortMaster /opt/tools/PortMaster /roms/ports/PortMaster 2>/dev/null
section "almacenamiento"; df -h
section "fin"
sync
