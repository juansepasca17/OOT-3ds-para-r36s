#!/usr/bin/env bash
# Generate TriAevum's structural whole-AOT IR (and generated C++) from the prepared ROM inputs.
set -euo pipefail
root=/root/oot3d
prepared=$(ls -d "$root"/work/gamedata/titles/*/* | head -n1)
cd "$root/TriAevum"
echo "prepared: $prepared"
time "$root/venv/bin/python" -m tools.triaevum_release.forge prepare-aot-ir \
    --prepared-directory "$prepared" \
    --cache-root "$root/work/aot-cache"
