#!/usr/bin/env bash
# Cross-compile the TriAevum whole-AOT product (OpenGL renderer) for the R36S.
set -euo pipefail
root=/root/oot3d
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
build=${BUILD_DIR:-$root/work/build-aarch64}
src=$(ls -d "$root"/work/gamedata/sources/* | head -n1)
program=$(ls "$root"/work/aot-cache/*/aot_program.json | head -n1)
export OOT3D_ACCEPT_EXHEADER_SHA256=dbe5fa0174d73bffb75d7cf0fbaa05d3e0ee080df0e257afc58b6c45ae5de3d0

cmake -S "$root/TriAevum" -B "$build" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$here/aarch64-dArkOS.cmake" \
    -DCMAKE_BUILD_TYPE=Release \
    -DPython3_EXECUTABLE="$root/venv/bin/python" \
    -DOOT3D_ENABLE_VULKAN_RENDERER=OFF \
    -DTHREE_DS_RECOMP_ENABLE_VULKAN=OFF \
    -DTHREE_DS_RECOMP_ENABLE_NRI=OFF \
    -DTHREE_DS_RECOMP_ENABLE_SSSR=OFF \
    -DOOT3D_WHOLE_AOT_PRODUCT_MODE=ON \
    -DOOT3D_REQUIRE_WHOLE_AOT=ON \
    -DOOT3D_REBUILD_WHOLE_AOT=ON \
    -DOOT3D_REGENERATE_WHOLE_AOT=OFF \
    -DOOT3D_WHOLE_AOT_GENERATED_DIR="$root/work/aot-cpp" \
    -DOOT3D_WHOLE_AOT_PROGRAM="$program" \
    -DOOT3D_WHOLE_AOT_SELECTION="$root/TriAevum/tools/oot3d/native_a32_runtime/whole_aot_functions.json" \
    -DOOT3D_WHOLE_AOT_CODE_BIN="$src/code.bin" \
    -DOOT3D_WHOLE_AOT_EXHEADER="$src/exheader.bin" \
    -DOOT3D_WHOLE_AOT_MAX_PARALLEL_COMPILES="${AOT_JOBS:-4}"

time cmake --build "$build" --target oot3d_native_game --parallel "${JOBS:-8}"
file "$build/oot3d_native_game"
