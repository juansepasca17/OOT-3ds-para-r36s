#!/usr/bin/env bash
# Download the third-party sources and binaries this port builds against.
# Nothing here is redistributed by this repository.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

TRIAEVUM_REPO=https://github.com/coccofresco/TriAevum.git
TRIAEVUM_COMMIT=8f69a26f390bf3a500bf3149b6596c19724a5b5d   # 2026-10-22
DARKOS_REPO=https://github.com/christianhaitian/dArkOS.git
LIBMALI_URL=https://github.com/christianhaitian/rk3326_core_builds/raw/refs/heads/master/mali/aarch64/libmali-bifrost-g31-rxp0-gbm.so
LIBMALI_SHA256=2a067ea38256c3de139b2a5396d3101f7c7777b1e19d59017b2c02172500d0ea

mkdir -p "$here/repos" "$here/deps/mali"

if [[ ! -d $here/repos/TriAevum/.git ]]; then
    git clone "$TRIAEVUM_REPO" "$here/repos/TriAevum"
fi
git -C "$here/repos/TriAevum" fetch --depth 1 origin "$TRIAEVUM_COMMIT"
git -C "$here/repos/TriAevum" checkout --detach "$TRIAEVUM_COMMIT"

if [[ ! -d $here/repos/dArkOS/.git ]]; then
    git clone --depth 1 "$DARKOS_REPO" "$here/repos/dArkOS"
fi

libmali=$here/deps/mali/libmali-bifrost-g31-rxp0-gbm.so
if [[ ! -s $libmali ]]; then
    curl -fL -o "$libmali" "$LIBMALI_URL"
fi
echo "$LIBMALI_SHA256  $libmali" | sha256sum -c - || {
    echo "libmali checksum mismatch; refusing to use it" >&2
    rm -f "$libmali"
    exit 1
}
echo "sources ready under $here/repos and $here/deps"
