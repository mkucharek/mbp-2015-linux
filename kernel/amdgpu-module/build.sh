#!/usr/bin/env bash
# Build only amdgpu.ko for the running kernel from a patched source tree, then strip and
# zstd-compress it like Arch kernels ship it. Output: out/amdgpu.ko.zst next to this script.
#   bash build.sh /path/to/linux-source          (needs the headers package of the running kernel)
# The source tree must match the running kernel: the same version plus the distro's patches,
# with kernel/amdgpu-si-reset-on-init.patch applied on top. Only drivers/gpu/drm/ is used.
set -euo pipefail

src=$(realpath "${1:?usage: $0 /path/to/linux-source}")
here=$(cd "$(dirname "$0")" && pwd)
kver=${KVER:-$(uname -r)}
kdir=/usr/lib/modules/$kver/build
mdir=$src/drivers/gpu/drm/amd/amdgpu

[[ -d $kdir ]] || { echo "headers for $kver not found at $kdir" >&2; exit 1; }
[[ -d $mdir ]] || { echo "no amdgpu source at $mdir" >&2; exit 1; }

# amdgpu's trace headers set TRACE_INCLUDE_PATH to ../../drivers/gpu/drm/amd/..., which is
# resolved relative to include/trace. Add $src/include/trace so it resolves inside $src.
mkdir -p "$src/include/trace"
make -C "$kdir" M="$mdir" KCFLAGS="-I$src/include/trace" -j"$(nproc)" modules

mkdir -p "$here/out"
cp "$mdir/amdgpu.ko" "$here/out/amdgpu.ko"
strip --strip-debug "$here/out/amdgpu.ko"
zstd -q -f -19 --rm "$here/out/amdgpu.ko" -o "$here/out/amdgpu.ko.zst"

echo "built: $here/out/amdgpu.ko.zst"
modinfo "$here/out/amdgpu.ko.zst" | grep -E '^(vermagic|srcversion)'
