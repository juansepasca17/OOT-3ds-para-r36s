# A5: deterministic x86 run from boot; prints process/memory fingerprints.
# Usage: FRAMES=300 WARMUP=100 BUILD=/root/oot3d/work/build-x86 bash det_run.sh LABEL [VAR=value...]
# Same binary + same frames => same fingerprints (since the DSP status fix, 2026-10-26).
# OOT3D_DUMP_PAGE_HASHES=<file> [OOT3D_DUMP_PAGE=<hex addr>] locate differing guest pages.
mkdir -p /root/oot3d/work/det
set -u
label=$1; shift
G=/root/oot3d/work/dist-sw; B=${BUILD:-/root/oot3d/work/build-x86}/oot3d_native_game
rm -rf /root/oot3d/work/det/det-$label; mkdir -p /root/oot3d/work/det/det-$label
cd $G && env SDL_VIDEODRIVER=offscreen SDL_AUDIODRIVER=dummy EGL_PLATFORM=surfaceless GALLIUM_DRIVER=llvmpipe LIBGL_ALWAYS_SOFTWARE=1 \
  TRIAEVUM_PARALLEL_PRESENTATION=0 OOT3D_HALF_RATE_DRAW=0 OOT3D_AUDIO_STRETCH=0 OOT3D_R36S_CONFIG=/root/oot3d/work/det/det-$label/r.json "$@" \
  timeout 900 taskset -c 0-5 $B --a32-process-manifest $G/game/oot3d_native_process_manifest.json --resource-root $G/resources.o2r \
  --config $G/config/oot3d_native_game.json --controls-config $G/config/oot3d_controls.json --ui-profile topscreen \
  --topscreen-config $G/config/topscreen_ui.json --topscreen-texture-overrides $G/config/atlas_overrides.o3tu \
  --save-data /root/oot3d/work/det/det-$label --quick-state /root/oot3d/work/det/det-$label/q.oot3dsav --renderer opengl --gameplay-timing native30_no_interpolation \
  --serial-presentation --throughput-benchmark --disable-audio --width 400 --height 240 \
  --frames ${FRAMES:-600} --benchmark-warmup-frames ${WARMUP:-100} --output /root/oot3d/work/det/det-$label/out.json > /root/oot3d/work/det/det-$label/log.txt 2>&1
python3 - /root/oot3d/work/det/det-$label/out.json $label <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
def find(x,k):
    if isinstance(x,dict):
        for kk,v in x.items():
            if kk==k: return v
            r=find(v,k)
            if r is not None: return r
print(sys.argv[2], 'proc', find(d,'process_state_fingerprint'), 'mem', find(d,'memory_state_fingerprint'), 'content', find(d,'memory_content_fingerprint'), 'guest_frame', find(d,'guest_frame'))
PY
