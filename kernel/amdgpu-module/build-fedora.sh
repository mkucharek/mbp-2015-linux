#!/usr/bin/env bash
# Fedora: get the source of an installed kernel, apply the amdgpu fix and build the module.
#   bash build-fedora.sh                     for the running kernel
#   KVER=<version> bash build-fedora.sh      for another installed kernel (e.g. right after
#                                            `dnf upgrade`, before rebooting into it)
# Then: sudo [KVER=<version>] bash install.sh, and reboot.
# Needs: sudo dnf install kernel-devel-<version> gcc make flex bison elfutils-libelf-devel openssl-devel dwarves git-core
# Downloads Fedora's kernel source package (~160 MB) to $SRCDIR (default ~/src/fedora-kernel),
# unpacks linux-<x.y.z>.tar.xz, and applies Fedora's patch-<x.y>-redhat.patch, as the
# kernel.spec does, then kernel/amdgpu-si-reset-on-init.patch. Uses git apply, since Fedora
# doesn't install patch(1) by default.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
fix=$here/../amdgpu-si-reset-on-init.patch
kver=${KVER:-$(uname -r)}            # e.g. 7.2.15-300.fc45.x86_64
nvr=${kver%.*}                       # 7.2.15-300.fc45
ver=${nvr%%-*}                       # 7.2.15
srcdir=${SRCDIR:-$HOME/src/fedora-kernel}
tree=$srcdir/linux-$nvr

[[ -f /usr/lib/modules/$kver/build/Makefile ]] || { echo "missing headers: sudo dnf install kernel-devel-$kver" >&2; exit 1; }

mkdir -p "$srcdir"
cd "$srcdir"
if [[ ! -d $tree ]]; then
  srpm=kernel-$nvr.src.rpm
  [[ -f $srpm ]] || dnf download --source "kernel-$nvr"
  rm -rf "srpm-$nvr" "$tree.tmp"
  mkdir "srpm-$nvr"
  (cd "srpm-$nvr" && rpm2cpio "../$srpm" | cpio -idm --quiet)
  mkdir "$tree.tmp"
  tar -xf "srpm-$nvr/linux-$ver.tar.xz" -C "$tree.tmp" --strip-components=1
  # its own repository, so git apply works relative to the tree even if $srcdir is inside one
  git -C "$tree.tmp" init -q
  for p in "srpm-$nvr"/patch-*-redhat.patch; do
    if [[ -s $p ]]; then git -C "$tree.tmp" apply "$(realpath "$p")"; fi
  done
  git -C "$tree.tmp" apply "$(realpath "$fix")"
  rm -rf "$tree.tmp/.git"
  mv "$tree.tmp" "$tree"
  # the tree is all that's needed for rebuilds; drop the 160 MB package and its contents
  rm -rf "srpm-$nvr" "$srpm"
  echo "prepared $tree"
fi

KVER=$kver bash "$here/build.sh" "$tree"
echo "next: sudo KVER=$kver bash $here/install.sh"
