#!/bin/bash
# inside_x86.sh <rom>: dentro del contenedor del kit, compila pocket-native y el juego para x86_64,
# para probar en el PC (Mesa) antes de mandar a la consola. Deja todo en /out/x86.
set -euo pipefail
rom="$1"
cd /src
id=$(python3 tools/title_id.py "$rom")
echo "== x86: recompilador y pocket-native"
cargo build --release --locked -p recomp3ds --bin 3dsrecomp
cargo build --release --locked -p pocket-native
echo "== x86: recompilando el juego"
overrides=()
[ -d "titles/$id/overrides" ] && overrides=(--overrides "titles/$id/overrides")
RECOMP_CFLAGS=-DRECOMP_FASTMEM CC=gcc "$CARGO_TARGET_DIR/release/3dsrecomp" build "$rom" "/work/recomp-x86/$id" "${overrides[@]}" 2>&1 | tail -5
mkdir -p /out/x86
cp "$CARGO_TARGET_DIR/release/pocket-native" /out/x86/
cp "/work/recomp-x86/$id/$id.so" /out/x86/title.so
cp -r titles /out/x86/ 2>/dev/null || true
ls -l /out/x86
