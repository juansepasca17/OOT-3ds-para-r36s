#!/usr/bin/env bash
# Generate TriAevum's structural whole-AOT IR (and generated C++) from the prepared ROM inputs.
set -euo pipefail
root=/root/oot3d
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
prepared=$(ls -d "$root"/work/gamedata/titles/*/* | head -n1)
cd "$root/TriAevum"
for patch in "$here"/patches/*.patch; do
    git apply --check "$patch" 2>/dev/null && git apply "$patch" && echo "applied $(basename "$patch")"
done
# Qualified USA Rev 1 ExHeader: same entrypoint/text size as the EUR contract.
export OOT3D_ACCEPT_EXHEADER_SHA256=dbe5fa0174d73bffb75d7cf0fbaa05d3e0ee080df0e257afc58b6c45ae5de3d0
echo "prepared: $prepared"
time "$root/venv/bin/python" -m tools.triaevum_release.forge prepare-aot-ir \
    --prepared-directory "$prepared" \
    --cache-root "$root/work/aot-cache"
