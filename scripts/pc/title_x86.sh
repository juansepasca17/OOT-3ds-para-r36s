#!/bin/bash
# title_x86.sh <rom> <nombre> [VAR=valor...]: solo recompila el juego para x86 (sin pocket-native),
# p. ej. RECOMP_EXTRA=0 para dejar el código del mod al intérprete. Deja /out/x86/title-<nombre>.so
set -euo pipefail
rom=$1 name=$2; shift 2
cd /src
id=$(python3 tools/title_id.py "$rom")
cargo build --release --locked -p recomp3ds --bin 3dsrecomp 2>&1 | grep -E '^error|Finished'
env "$@" RECOMP_CFLAGS=-DRECOMP_FASTMEM CC=gcc "$CARGO_TARGET_DIR/release/3dsrecomp" build "$rom" "/work/recomp-x86-$name/$id" 2>&1 | tail -2
cp "/work/recomp-x86-$name/$id/$id.so" "/out/x86/title-$name.so"
ls -l /out/x86/title-$name.so
