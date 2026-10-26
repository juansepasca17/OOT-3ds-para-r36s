#!/usr/bin/env bash
# One step from edited sources to a console-ready test binary:
#   bash scripts/wsl/console_build.sh NAME [--regen] [--no-smoke]
# 1. copies the changed TriAevum files (git diff vs 8f69a26) into the WSL tree,
# 2. --regen: regenerates the whole-AOT C++ (only when the generator changed),
# 3. incremental aarch64 PGO build (ccache; only touched shards recompile),
# 4. qemu smoke run (20 frames, parallel, CPU/GPU overlap) unless --no-smoke,
# 5. strip + gzip + sha256 into work/devserver/files/oot3d_r36s-NAME.{gz,sha},
# 6. unstripped copy into the perf symfs at the path jobs install it to
#    (oot3d/dev/oot3d_r36s_NAME), so perf reports resolve symbols.
# No x86 build: its memory fingerprint is not deterministic (docs/PRUEBAS.md).
set -uo pipefail
name=${1:?usage: console_build.sh NAME [--regen] [--no-smoke]}; shift
regen=0; smoke=1
for arg in "$@"; do
  case $arg in --regen) regen=1 ;; --no-smoke) smoke=0 ;; *) echo "unknown $arg" >&2; exit 2 ;; esac
done
root=/root/oot3d
project="/mnt/c/Users/shjua/Documents/Juan se/Apps de claude/OOT 3ds"
here="$project/scripts/wsl"
files="$project/work/devserver/files"
started=$(date +%s)
step() { echo "[$(( $(date +%s) - started ))s] $*"; }

step "sync"
for f in $(cd "$project/repos/TriAevum" && git diff --name-only); do
  sed 's/\r$//' "$project/repos/TriAevum/$f" > /tmp/sync.tmp
  cmp -s /tmp/sync.tmp "$root/TriAevum/$f" || { cp /tmp/sync.tmp "$root/TriAevum/$f"; echo "  updated $f"; }
done
if [ "$regen" = 1 ]; then
  step "regenerate whole-AOT C++"
  bash "$here/generate_cpp.sh" > "$root/work/generate-cpp.log" 2>&1 || { tail "$root/work/generate-cpp.log"; exit 1; }
fi
export OOT3D_ACCEPT_EXHEADER_SHA256=dbe5fa0174d73bffb75d7cf0fbaa05d3e0ee080df0e257afc58b6c45ae5de3d0
step "aarch64 PGO build"
cmake --build "$root/work/build-pgo" --target oot3d_native_game --parallel "${JOBS:-10}" \
  > "$root/work/console-build.log" 2>&1 || { grep -E "error|FAILED" "$root/work/console-build.log" | head -20; exit 1; }
install -m755 "$root/work/build-pgo/oot3d_native_game" "$root/work/dist-pgo-sw/oot3d_r36s"
if [ "$smoke" = 1 ]; then
  step "qemu smoke"
  ( cd "$root" && TRIAEVUM_INPUT_ADMISSION=0 PAR=1 FRAMES=20 WARMUP=5 TIMEOUT=1200 \
      bash scripts/wsl/qemu_smoke.sh "$root/work/dist-pgo-sw" > "$root/work/smoke-$name.log" 2>&1 )
  grep -q "exit=0" "$root/work/smoke-$name.log" || { echo "SMOKE FAILED"; tail -20 "$root/work/smoke-$name.log"; exit 1; }
fi
step "package"
aarch64-linux-gnu-strip -o "/tmp/oot3d_$name" "$root/work/build-pgo/oot3d_native_game"
gzip -6 -c "/tmp/oot3d_$name" > "$files/oot3d_r36s-$name.gz.tmp" && mv -f "$files/oot3d_r36s-$name.gz.tmp" "$files/oot3d_r36s-$name.gz"
sha256sum "$files/oot3d_r36s-$name.gz" | cut -c1-64 > "$files/oot3d_r36s-$name.sha"
mkdir -p "$root/work/symfs/roms/ports/oot3d/dev"
cp -f "$root/work/build-pgo/oot3d_native_game" "$root/work/symfs/roms/ports/oot3d/dev/oot3d_r36s_$name"
step "ready: oot3d_r36s-$name.gz ($(du -h "$files/oot3d_r36s-$name.gz" | cut -f1)) sha $(cat "$files/oot3d_r36s-$name.sha")"
