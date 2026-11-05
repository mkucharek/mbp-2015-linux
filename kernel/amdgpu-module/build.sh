#!/usr/bin/env bash
# Build only amdgpu.ko for the running kernel from a patched source tree, then strip and
# compress it the way the distro ships its modules (zstd on Arch, xz on Fedora).
# Output: out/amdgpu.ko.zst or out/amdgpu.ko.xz next to this script.
#   bash build.sh /path/to/linux-source          (needs the headers package of the kernel)
#   KVER=<version> bash build.sh ...             build for an installed kernel that isn't running
# The source tree must match the kernel: the same version plus the distro's patches,
# with kernel/amdgpu-si-reset-on-init.patch applied on top. Only drivers/gpu/drm/ is used.
# On Fedora, build-fedora.sh prepares the source and calls this script.
set -euo pipefail

src=$(realpath "${1:?usage: $0 /path/to/linux-source}")
here=$(cd "$(dirname "$0")" && pwd)
kver=${KVER:-$(uname -r)}
kdir=/usr/lib/modules/$kver/build
mdir=$src/drivers/gpu/drm/amd/amdgpu

[[ -f $kdir/Makefile ]] || { echo "headers for $kver not found at $kdir (Arch: <kernel>-headers, Fedora: kernel-devel-$kver)" >&2; exit 1; }
[[ -d $mdir ]] || { echo "no amdgpu source at $mdir" >&2; exit 1; }

# Compress like the distro's own amdgpu module
stock=$(modinfo -k "$kver" -n amdgpu)
case $stock in
  *.ko.zst) ext=zst ;;
  *.ko.xz)  ext=xz ;;
  *) echo "unexpected module format: $stock" >&2; exit 1 ;;
esac

# amdgpu's trace headers set TRACE_INCLUDE_PATH to ../../drivers/gpu/drm/amd/..., which is
# resolved relative to include/trace. Add $src/include/trace so it resolves inside $src.
mkdir -p "$src/include/trace"
make -C "$kdir" M="$mdir" KCFLAGS="-I$src/include/trace" -j"$(nproc)" modules

mkdir -p "$here/out"
rm -f "$here/out"/amdgpu.ko*
cp "$mdir/amdgpu.ko" "$here/out/amdgpu.ko"
strip --strip-debug "$here/out/amdgpu.ko"
case $ext in
  zst) zstd -q -f -19 --rm "$here/out/amdgpu.ko" -o "$here/out/amdgpu.ko.zst" ;;
  # the kernel's own xz settings (scripts/Makefile.modinst); its decompressor needs CRC32
  xz)  xz -f --check=crc32 --lzma2=dict=1MiB "$here/out/amdgpu.ko" ;;
esac

echo "built: $here/out/amdgpu.ko.$ext"
modinfo "$here/out/amdgpu.ko.$ext" | grep -E '^(vermagic|srcversion)'
