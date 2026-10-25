#!/usr/bin/env bash
# Native x86-64 build of the same product for fast profiling inside WSL (perf).
set -euo pipefail
root=/root/oot3d
build=${BUILD_DIR:-$root/work/build-x86}
src=$(ls -d "$root"/work/gamedata/sources/* | head -n1)
program=$(ls "$root"/work/aot-cache/*/aot_program.json | head -n1)
export OOT3D_ACCEPT_EXHEADER_SHA256=dbe5fa0174d73bffb75d7cf0fbaa05d3e0ee080df0e257afc58b6c45ae5de3d0
cmake -S "$root/TriAevum" -B "$build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
    -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=mold" \
    -DCMAKE_CXX_FLAGS="-fno-omit-frame-pointer" \
    -DPython3_EXECUTABLE="$root/venv/bin/python" \
    -DOOT3D_ENABLE_VULKAN_RENDERER=OFF -DTHREE_DS_RECOMP_ENABLE_VULKAN=OFF \
    -DTHREE_DS_RECOMP_ENABLE_NRI=OFF -DTHREE_DS_RECOMP_ENABLE_SSSR=OFF \
    -DOOT3D_WHOLE_AOT_PRODUCT_MODE=ON -DOOT3D_REQUIRE_WHOLE_AOT=ON \
    -DOOT3D_REBUILD_WHOLE_AOT=ON -DOOT3D_REGENERATE_WHOLE_AOT=OFF \
    -DOOT3D_WHOLE_AOT_GENERATED_DIR="$root/work/aot-cpp" \
    -DOOT3D_WHOLE_AOT_PROGRAM="$program" \
    -DOOT3D_WHOLE_AOT_SELECTION="$root/TriAevum/tools/oot3d/native_a32_runtime/whole_aot_functions.json" \
    -DOOT3D_WHOLE_AOT_CODE_BIN="$src/code.bin" \
    -DOOT3D_WHOLE_AOT_EXHEADER="$src/exheader.bin" \
    -DOOT3D_WHOLE_AOT_MAX_PARALLEL_COMPILES="${AOT_JOBS:-10}"
time cmake --build "$build" --target oot3d_native_game --parallel "${JOBS:-11}"
file "$build/oot3d_native_game"
