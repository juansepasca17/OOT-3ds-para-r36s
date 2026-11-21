#!/bin/bash
# probe.sh NOMBRE FRAMES [VAR=valor...]: corre el juego sin pantalla en el PC (Mesa) con --probe.
# Dentro de pn-run: /pn = binarios x86 (pocket-native, title.so, titles, sysdata), /rom = ROM, /runs = salida.
set -u
name=$1 frames=$2; shift 2
run=/runs/$name; rm -rf "$run"; mkdir -p "$run/data"
cp -r /pn/sysdata "$run/" 2>/dev/null
[ -f /runs/romfs.patch ] && [ -n "${WITH_PATCH:-}" ] && cp /runs/romfs.patch "$run/data/"
[ -n "${LANG_ID:-}" ] && printf 'language = %s\nregion = 1\n\n[options]\n' "$LANG_ID" > "$run/data/settings.toml"
cd "$run"
export EGL_PLATFORM=surfaceless ZAKURO_FAST=1 ZAKURO_DATA="$run/data" ZAKURO_RECOMPILED=${SO:-/pn/title.so} \
       POCKET_NATIVE_TITLES=${TITLES:-/pn/titles} POCKET_NATIVE_CONFIG="$run/config"
mkdir -p "$run/config"; cp /pn/settings.toml "$run/config/" 2>/dev/null
env "$@" timeout 1800 /pn/pocket-native --probe /rom/game-reframed-2.5.1.3ds "$frames" > "$run/log.txt" 2>&1
echo "exit $?" >> "$run/log.txt"
