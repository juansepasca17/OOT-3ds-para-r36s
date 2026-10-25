#!/usr/bin/env bash
# Boot the staged aarch64 port under qemu-user with the same environment OOT3D.sh uses.
set -uo pipefail
G=${1:-/root/oot3d/work/dist/oot3d}
frames=${FRAMES:-40}
warmup=${WARMUP:-10}
cd "$G"
export LD_LIBRARY_PATH="$G/libs"
export SDL_VIDEODRIVER=offscreen SDL_AUDIODRIVER=dummy
export __EGL_VENDOR_LIBRARY_FILENAMES="$G/libs/egl_vendor.d/50_mesa.json"
export LIBGL_DRIVERS_PATH="$G/libs/dri" GALLIUM_DRIVER=llvmpipe LIBGL_ALWAYS_SOFTWARE=1 EGL_PLATFORM=surfaceless
export MESA_GL_VERSION_OVERRIDE=4.5 MESA_GLSL_VERSION_OVERRIDE=450 TRIAEVUM_PARALLEL_PRESENTATION=0
missing=$(LD_LIBRARY_PATH="$G/libs" qemu-aarch64 -L /usr/aarch64-linux-gnu /lib/ld-linux-aarch64.so.1 --list "$G/oot3d_r36s" 2>&1 | grep "not found")
[ -n "$missing" ] && echo "MISSING: $missing"
time timeout "${TIMEOUT:-1800}" "$G/oot3d_r36s" \
    --a32-process-manifest "$G/game/oot3d_native_process_manifest.json" \
    --resource-root "$G/resources.o2r" \
    --config "$G/config/oot3d_native_game.json" \
    --controls-config "$G/config/oot3d_controls.json" \
    --ui-profile topscreen \
    --topscreen-config "$G/config/topscreen_ui.json" \
    --topscreen-texture-overrides "$G/config/atlas_overrides.o3tu" \
    --save-data "$G/savedata" \
    --quick-state "$G/savedata/quick.oot3dsav" \
    --renderer opengl \
    --gameplay-timing native30_no_interpolation \
    --throughput-benchmark --disable-audio \
    --width 400 --height 240 \
    --frames "$frames" --benchmark-warmup-frames "$warmup" \
    --output /tmp/bench_qemu.json ${EXTRA_ARGS:-}
echo "exit=$?"
cat /tmp/bench_qemu.json 2>/dev/null | head -c 3000
