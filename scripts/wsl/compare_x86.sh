#!/usr/bin/env bash
# Translator experiment: build x86 with baseline and alternative generated C++,
# run the same deterministic benchmark and compare guest time + memory fingerprint.
set -u
root=/root/oot3d
run() {  # $1=build dir, $2=label
  local G=$root/work/dist-sw B=$1/oot3d_native_game
  export SDL_VIDEODRIVER=offscreen SDL_AUDIODRIVER=dummy EGL_PLATFORM=surfaceless GALLIUM_DRIVER=llvmpipe LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=4 TRIAEVUM_PARALLEL_PRESENTATION=0
  rm -rf /tmp/sd-$2; mkdir -p /tmp/sd-$2
  ( cd $G && taskset -c 0-5 $B --a32-process-manifest $G/game/oot3d_native_process_manifest.json --resource-root $G/resources.o2r \
    --config $G/config/oot3d_native_game.json --controls-config $G/config/oot3d_controls.json --ui-profile topscreen \
    --topscreen-config $G/config/topscreen_ui.json --topscreen-texture-overrides $G/config/atlas_overrides.o3tu \
    --save-data /tmp/sd-$2 --quick-state /tmp/sd-$2/q.oot3dsav --renderer opengl --gameplay-timing native30_no_interpolation \
    --serial-presentation --throughput-benchmark --disable-audio --width 400 --height 240 \
    --frames 900 --benchmark-warmup-frames 300 --output $root/work/cmp-$2.json > $root/work/cmp-$2.log 2>&1 )
  python3 - "$root/work/cmp-$2.json" "$2" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); b=d['benchmark_window']; p=b['pre_backend_cpu']
def find(x,k):
    if isinstance(x,dict):
        for kk,v in x.items():
            if kk==k: return v
            r=find(v,k)
            if r is not None: return r
print(sys.argv[2], 'guest/frame %.2f ms' % (p['guest_seconds']/b['measured_frames']*1000),
      'pre_backend %.2f ms' % p['mean_ms'], 'mem_fp', find(d,'memory_state_fingerprint'), 'content_fp', find(d,'memory_content_fingerprint'))
PY
}
"$@"
