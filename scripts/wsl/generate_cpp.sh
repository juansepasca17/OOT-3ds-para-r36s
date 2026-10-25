#!/usr/bin/env bash
# Emit the 256 affinity-sharded whole-AOT C++ files from the audited program.
set -euo pipefail
root=/root/oot3d
program=$(ls "$root"/work/aot-cache/*/aot_program.json | head -n1)
code=$(ls "$root"/work/gamedata/sources/*/code.bin | head -n1)
out=$root/work/aot-cpp
cd "$root/TriAevum"
echo "program: $program"
time "$root/venv/bin/python" tools/oot3d/native_a32_runtime/generate_whole_aot_cpp.py \
    --program "$program" \
    --selection tools/oot3d/native_a32_runtime/whole_aot_functions.json \
    --code "$code" \
    --output "$out" \
    --shards 256 \
    --shard-strategy affinity
ls "$out" | wc -l
du -sh "$out"
