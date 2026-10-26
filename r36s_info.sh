#!/bin/bash
# r36s_info.sh — diagnóstico de una R36S (u otra consola RK3326 con ArkOS/dArkOS) para planear un port.
# Solo LEE información; no cambia nada.
# Uso: copiar a la carpeta "ports" de la SD, abrir desde Ports y luego leer ports/r36s_info.txt.

OUT="$(cd "$(dirname "$0")" && pwd)/r36s_info.txt"
exec > "$OUT" 2>&1
section() { printf '\n===== %s =====\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

section "fecha"; date

section "sistema"
cat /etc/os-release 2>/dev/null
grep -hi title /usr/share/plymouth/themes/text.plymouth 2>/dev/null
cat /home/ark/.config/.VERSION 2>/dev/null
uname -a
ldd --version 2>/dev/null | head -n1

section "modelo / device tree"
tr -d '\0' < /proc/device-tree/model 2>/dev/null; echo
tr -d '\0' < /proc/device-tree/compatible 2>/dev/null; echo
ls /boot/*.dtb 2>/dev/null
grep -iE "dtb|fdt" /boot/boot.ini 2>/dev/null

section "cpu"
lscpu 2>/dev/null | grep -E "Model name|CPU\(s\)|max MHz|min MHz|Flags"
for f in scaling_available_frequencies scaling_available_governors scaling_governor scaling_max_freq; do
  printf '%s: %s\n' "$f" "$(cat /sys/devices/system/cpu/cpu0/cpufreq/$f 2>/dev/null)"
done

section "memoria"
free -m
cat /proc/swaps
df -h /tmp 2>/dev/null | tail -n1

section "gpu y drivers"
for f in /sys/devices/platform/*gpu*/devfreq/*/{available_frequencies,governor,max_freq}; do
  [ -f "$f" ] && printf '%s: %s\n' "$f" "$(cat "$f")"
done
ls -l /usr/lib/aarch64-linux-gnu/ | grep -iE "libmali|libEGL|libGLES|libvulkan|libgbm" 2>/dev/null
ls /usr/share/vulkan/icd.d/ /etc/vulkan/icd.d/ 2>/dev/null && echo "(hay ICD de Vulkan registrado)" || echo "sin ICD de Vulkan registrado"
ls /usr/lib/aarch64-linux-gnu/dri/ 2>/dev/null | head
have glxinfo && glxinfo -B 2>/dev/null | head -n 12
have es2_info && es2_info 2>/dev/null | head -n 12

section "variables graficas del sistema"
grep -rsE "SDL_|EGL|MESA|LIBGL" /etc/environment /etc/profile.d/ 2>/dev/null

section "sdl2"
ls -l /usr/lib/aarch64-linux-gnu/libSDL2* 2>/dev/null
ls -l /usr/lib/arm-linux-gnueabihf/libSDL2* 2>/dev/null | head -n 3

section "userspace 32 bits (armhf)"
ls -d /usr/lib/arm-linux-gnueabihf 2>/dev/null && ls /usr/lib/arm-linux-gnueabihf | wc -l

section "pantalla"
cat /sys/class/graphics/fb0/virtual_size 2>/dev/null
cat /sys/class/drm/*/modes 2>/dev/null

section "controles"
grep -E "^N:|^H:" /proc/bus/input/devices 2>/dev/null
ls /dev/input/js* 2>/dev/null

section "portmaster"
ls -d /opt/system/Tools/PortMaster /opt/tools/PortMaster /roms/ports/PortMaster 2>/dev/null
ls /roms/ports 2>/dev/null | head -n 40

section "red y ssh (para pruebas sin pasar la SD)"
ip -brief addr 2>/dev/null || ifconfig 2>/dev/null
ls /sys/class/net 2>/dev/null
iw dev 2>/dev/null | grep -E "Interface|ssid"
(systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null) | sed 's/^/ssh: /'
echo "-- drivers de red del kernel (que adaptador USB funcionaria) --"
moddir=/lib/modules/$(uname -r)
for m in 8188eu r8188eu rtl8188fu 8188fu rtl8xxxu 8821cu 88x2bu rtl8192cu mt7601u mt76x0u mt76x2u \
         r8152 asix ax88179_178a cdc_ether rndis_host usbnet cdc_ncm; do
  if grep -qw "$m" /proc/modules 2>/dev/null; then echo "$m: cargado"
  elif find "$moddir" -name "$m.ko*" 2>/dev/null | grep -q .; then echo "$m: disponible"
  elif grep -qiE "CONFIG_.*$(echo "$m" | tr 'a-z' 'A-Z')=y" "/boot/config-$(uname -r)" 2>/dev/null; then echo "$m: integrado"
  else echo "$m: no"; fi
done
grep -sE "dr_mode|otg" /proc/device-tree/*usb*/dr_mode /sys/kernel/debug/usb/*/mode 2>/dev/null
lsusb 2>/dev/null
have python3 && python3 --version

section "almacenamiento"
df -h

section "fin"
sync
