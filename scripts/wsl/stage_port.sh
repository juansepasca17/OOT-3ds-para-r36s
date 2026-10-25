#!/usr/bin/env bash
# Assemble ports/oot3d for dArkOS: binary, game data from the user's ROM, configs, resources
# and the bundled runtime libraries (SDL2 + Mesa llvmpipe for the CPU benchmark build).
set -euo pipefail
root=/root/oot3d
repo=$root/TriAevum
build=${BUILD_DIR:-$root/work/build-aarch64}
out=${1:-$root/work/dist/oot3d}
src=$(ls -d "$root"/work/gamedata/sources/* | head -n1)
manifest=$(ls "$root"/work/gamedata/titles/*/*/process-manifest.json | head -n1)

rm -rf "$out"
mkdir -p "$out"/{game,config,savedata,libs/dri}
[[ ${STAGE_MODE:-gpu} == software ]] || rmdir "$out/libs/dri"

install -m 0755 "$build/oot3d_native_game" "$out/oot3d_r36s"
aarch64-linux-gnu-strip "$out/oot3d_r36s"

# Game data (private, from the user's own ROM).
cp "$src/code.bin" "$src/exheader.bin" "$src/romfs.bin" "$out/game/"
"$root/venv/bin/python" - "$manifest" "$out/game/oot3d_native_process_manifest.json" <<'EOF'
import json, sys
m = json.load(open(sys.argv[1]))
def fix(node):
    if isinstance(node, dict):
        for key, value in node.items():
            if key in ("code_bin_path", "exheader_path", "romfs_image_path") and isinstance(value, str):
                node[key] = value.rsplit("/", 1)[-1]
            else:
                fix(value)
    elif isinstance(node, list):
        for item in node:
            fix(item)
fix(m)
json.dump(m, open(sys.argv[2], "w"), indent=2)
EOF

# Single-screen UI (SingleScreen 3.0 atlas shipped by TriAevum) and controller profile.
"$root/venv/bin/python" "$repo/tools/oot3d/decomp_support/scripts/build_topscreen_texture_override_pack.py" \
    --singlescreen-ui-atlas "$repo/runtime/triaevum_resources/topscreen/singlescreen-3.0/custom_ui01.ctxb" \
    --output "$out/config/atlas_overrides.o3tu"
install -m 0644 "$repo/config/topscreen_ui.switch.json" "$out/config/topscreen_ui.json"
install -m 0644 "$repo/config/oot3d_controls.switch.json" "$out/config/oot3d_controls.json"
install -m 0644 "$repo/config/oot3d_native_game.throughput.json" "$out/config/oot3d_native_game.json"
printf '{\n  "format": "triaevum_game_language_v1",\n  "selected": "es"\n}\n' > "$out/config/game_language.json"

work=$(mktemp -d)
mkdir -p "$work/shaders/opengl"
install -m 0644 "$repo/runtime/three_ds_recomp/src/fast/shaders/opengl/default.shader.glsl" "$work/shaders/opengl/"
(cd "$work" && cmake -E tar cf resources.o2r --format=zip shaders)
install -m 0644 "$work/resources.o2r" "$out/resources.o2r"
rm -rf "$work"

lib=/usr/lib/aarch64-linux-gnu
if [[ ${STAGE_MODE:-gpu} == software ]]; then
    # Runtime libraries not guaranteed on dArkOS: Debian's SDL2 (offscreen driver) and Mesa llvmpipe.
    for so in libSDL2-2.0.so.0 libEGL_mesa.so.0 libgallium-*.so libLLVM.so.* libglapi.so.0 \
              libspdlog.so.* libfmt.so.* libzip.so.* libtinyxml2.so.* libopusfile.so.* libGLEW.so.* \
              libGLX_mesa.so.0 libGL.so.1 libGLX.so.0 libGLdispatch.so.0 libOpenGL.so.0 libEGL.so.1 \
              libdrm.so.2 libgbm.so.1 libexpat.so.1 libz3.so.* libxml2.so.* libsensors.so.* libelf.so.* \
              libedit.so.* libbsd.so.* libmd.so.* libicuuc.so.* libicudata.so.* libLLVM-*.so*; do
        for f in $lib/$so; do [ -e "$f" ] && cp -L "$f" "$out/libs/"; done
    done
    cp -L "$lib"/dri/swrast_dri.so "$out/libs/dri/" 2>/dev/null || true
    cp -L "$lib"/dri/libdril_dri.so "$out/libs/dri/" 2>/dev/null || true
    mkdir -p "$out/libs/egl_vendor.d"
    echo '{ "file_format_version" : "1.0.0", "ICD" : { "library_path" : "libEGL_mesa.so.0" } }'         > "$out/libs/egl_vendor.d/50_mesa.json"

    # Keep only libraries the binary (and Mesa) actually load, under their SONAME.
    declare -A keep
    queue=("$out/oot3d_r36s" "$out/libs/libEGL_mesa.so.0" "$out"/libs/libgallium-*.so "$out"/libs/dri/*.so)
    for k in libEGL_mesa.so.0 libEGL.so.1 libGL.so.1 libGLX.so.0 libGLX_mesa.so.0 libGLdispatch.so.0 libOpenGL.so.0; do keep[$k]=1; queue+=("$out/libs/$k"); done
    for g in "$out"/libs/libgallium-*.so; do keep[$(basename "$g")]=1; done
    while ((${#queue[@]})); do
        f=${queue[0]}; queue=("${queue[@]:1}")
        [ -f "$f" ] || continue
        for need in $(aarch64-linux-gnu-readelf -d "$f" 2>/dev/null | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'); do
            [[ -n ${keep[$need]:-} ]] && continue
            if [ -f "$out/libs/$need" ]; then keep[$need]=1; queue+=("$out/libs/$need"); fi
        done
    done
    for f in "$out"/libs/*.so*; do
        [[ -n ${keep[$(basename "$f")]:-} ]] || rm -f "$f"
    done

fi

# Bundle the remaining dependency closure; dArkOS (trixie) already provides the core runtime.
core='^(ld-linux-aarch64\.so\.1|libc\.so\.6|libm\.so\.6|libgcc_s\.so\.1|libstdc\+\+\.so\.6|libpthread\.so\.0|libdl\.so\.2|librt\.so\.1)$'
[[ ${STAGE_MODE:-gpu} == software ]] || core='^(ld-linux-aarch64\.so\.1|libc\.so\.6|libm\.so\.6|libgcc_s\.so\.1|libstdc\+\+\.so\.6|libpthread\.so\.0|libdl\.so\.2|librt\.so\.1|libSDL2-2\.0\.so\.0|libGLESv2\.so\.2|libEGL\.so\.1)$'
while :; do
    added=0
    for f in "$out/oot3d_r36s" "$out"/libs/*.so*; do
        for need in $(aarch64-linux-gnu-readelf -d "$f" 2>/dev/null | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'); do
            [[ $need =~ $core ]] && continue
            [ -e "$out/libs/$need" ] && continue
            found=$(find "$lib" -name "$need" 2>/dev/null | head -n1)
            if [ -n "$found" ]; then cp -L "$found" "$out/libs/"; added=1
            else echo "WARNING: $need not found in sysroot"; fi
        done
    done
    ((added)) || break
done

du -sh "$out" "$out/libs"; ls "$out/libs"
