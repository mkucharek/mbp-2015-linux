#!/bin/bash
# Ubuntu kernel + MTRR resume patch: fixes the ~15 s wake from S3 sleep on this Mac
# (Apple firmware alters CPU MTRRs during sleep; see ../hardware.md (Sleep) and mtrr-resume.patch).
# Builds the SAME Ubuntu kernel you run (exact source + config), plus the patch, named
# <version>-mtrr (e.g. 7.0.0-38-mtrr). The stock kernel stays installed as a fallback.
#
#   bash build-kernel.sh prepare        # download source + check the patch applies (no sudo)
#   bash build-kernel.sh build          # prepare + build packages, ~1-1.5 h (asks sudo once for build tools)
#   sudo bash build-kernel.sh install   # install the built kernel (becomes the GRUB default)
#   sudo bash build-kernel.sh remove    # remove patched kernel(s); boot the stock kernel first
#
# After an Ubuntu kernel update the new stock kernel is newer and becomes the default again
# (slow wake returns, nothing breaks). To keep the fix: run build + install again.
# Override the target version: KVER=7.0.0-41 bash build-kernel.sh build
set -euo pipefail
export LC_ALL=C
HERE=$(cd "$(dirname "$0")" && pwd)
PATCH="$HERE/mtrr-resume.patch"
SUFFIX=mtrr
USER_HOME=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
WORK="${KBUILD_DIR:-$USER_HOME/kernel-build}"
ARCHIVE=http://archive.ubuntu.com/ubuntu/pool/main/l
CMD=${1:-}

# Newest installed stock kernel, e.g. 7.0.0-38
KVER=${KVER:-$(ls /boot/vmlinuz-*-generic | sed 's|/boot/vmlinuz-||; s|-generic$||' | sort -V | tail -1)}
KREL="$KVER-$SUFFIX"                 # 7.0.0-38-mtrr
SRCDIR="$WORK/src-$KVER"
OBJDIR="$WORK/build-$KVER"

prepare() {
    mkdir -p "$WORK"; cd "$WORK"
    local pkgver src dsc
    pkgver=$(dpkg-query -W -f='${Version}' "linux-image-$KVER-generic")
    src=$(apt-cache show "linux-headers-$KVER-generic=$pkgver" | awk '/^Source:/{print $2; exit}')
    dsc="${src}_${pkgver}.dsc"
    echo "=== Kernel $KVER-generic: source package $src $pkgver"
    if [ ! -d "$SRCDIR" ]; then
        [ -s "$dsc" ] || curl -sfO "$ARCHIVE/$src/$dsc"
        # download every file listed in the .dsc and verify its SHA256
        awk '/^Checksums-Sha256:/{on=1; next} /^[A-Z]/{on=0} on && NF==3 {print $1, $3}' "$dsc" |
        while read -r sum file; do
            [ -s "$file" ] || { echo "downloading $file"; curl -sfO "$ARCHIVE/$src/$file"; }
            echo "$sum  $file" | sha256sum -c --quiet || { echo "checksum FAILED: $file"; exit 1; }
        done
        echo "=== Unpacking to $SRCDIR"
        dpkg-source --no-check -x "$dsc" "$SRCDIR" >/dev/null
    fi
    cd "$SRCDIR"
    if patch -p1 -R --dry-run -s -f < "$PATCH" >/dev/null 2>&1; then
        echo "=== Patch already applied"
    elif patch -p1 --dry-run -s -f < "$PATCH"; then
        patch -p1 -s < "$PATCH"
        echo "=== Patch applied cleanly"
    else
        echo "=== Patch does NOT apply to $KVER. Check if it was merged upstream (notes, section 5)."
        exit 1
    fi
}

build() {
    [ "$(id -u)" -ne 0 ] || { echo "Run 'build' as your normal user, not with sudo"; exit 1; }
    local missing=()
    for p in build-essential bc bison flex libssl-dev libelf-dev libdw-dev gawk zstd cpio kmod rsync fakeroot dpkg-dev debhelper python3; do
        dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "=== Installing build tools: ${missing[*]}"
        sudo apt-get install -y --no-install-recommends "${missing[@]}"
    fi
    prepare

    echo "=== Config: Ubuntu's /boot/config-$KVER-generic, minus Rust and debug info"
    mkdir -p "$OBJDIR"
    cp "/boot/config-$KVER-generic" "$OBJDIR/.config"
    scripts/config --file "$OBJDIR/.config" \
        --disable RUST \
        --disable DEBUG_INFO_DWARF5 --disable DEBUG_INFO_DWARF4 \
        --disable DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT --enable DEBUG_INFO_NONE \
        --disable DEBUG_INFO_BTF --disable DEBUG_INFO_BTF_MODULES \
        --set-str SYSTEM_TRUSTED_KEYS "" --set-str SYSTEM_REVOCATION_KEYS "" \
        --set-str LOCALVERSION ""
    # KERNELVERSION + LOCALVERSION give Ubuntu-style naming: 7.0.0-38-mtrr
    local mk=(make O="$OBJDIR" KERNELVERSION="${KVER%-*}" LOCALVERSION="-${KVER##*-}-$SUFFIX")
    "${mk[@]}" olddefconfig >/dev/null
    local rel; rel=$("${mk[@]}" -s kernelrelease)
    [ "$rel" = "$KREL" ] || { echo "Unexpected kernel release '$rel' (wanted $KREL)"; exit 1; }
    grep -q '^CONFIG_DEBUG_INFO_NONE=y' "$OBJDIR/.config" && ! grep -q '^CONFIG_RUST=y' "$OBJDIR/.config" \
        || { echo "Config adjustments did not stick"; exit 1; }

    echo "=== Building $KREL with $(nproc) jobs (~1-1.5 h). Log: $WORK/build-$KREL.log"
    local t0=$SECONDS
    nice -n 10 "${mk[@]}" -j"$(nproc)" bindeb-pkg > "$WORK/build-$KREL.log" 2>&1 \
        || { tail -30 "$WORK/build-$KREL.log"; echo "=== BUILD FAILED, see log"; exit 1; }
    echo "=== Built in $(( (SECONDS-t0)/60 )) min:"
    ls -1 "$WORK"/linux-image-"$KREL"_*.deb "$WORK"/linux-headers-"$KREL"_*.deb
    echo "Next: sudo bash $0 install"
}

install_kernel() {
    [ "$(id -u)" -eq 0 ] || { echo "Run with sudo"; exit 1; }
    local img hdr
    img=$(ls -t "$WORK"/linux-image-"$KREL"_*.deb 2>/dev/null | head -1)
    hdr=$(ls -t "$WORK"/linux-headers-"$KREL"_*.deb 2>/dev/null | head -1)
    [ -n "$img" ] && [ -n "$hdr" ] || { echo "No packages for $KREL in $WORK; run build first"; exit 1; }
    # Only image + headers: never install the linux-libc-dev package the build also produces
    echo "=== Installing $(basename "$img") + $(basename "$hdr")"
    dpkg -i "$img" "$hdr"
    echo "=== Checks"
    dkms status | grep "$KREL" || echo "WARNING: no DKMS module built for $KREL (facetimehd camera)"
    lsinitramfs "/boot/initrd.img-$KREL" | grep -cE '/(radeon|i915)\.ko' | sed 's/^/GPU drivers in initramfs (want 2): /'
    echo "GRUB default: $(grep -m1 -oE "vmlinuz-[^ ]+" /boot/grub/grub.cfg)"
    echo "=== Done. Reboot, check 'uname -r' = $KREL, then: sudo bash $HERE/../sleep-test.sh deep 10"
    echo "    Problems? Pick the -generic kernel in GRUB (Advanced options), then: sudo bash $0 remove"
}

remove_kernel() {
    [ "$(id -u)" -eq 0 ] || { echo "Run with sudo"; exit 1; }
    case "$(uname -r)" in *-"$SUFFIX") echo "Running a patched kernel now; boot the -generic one first"; exit 1;; esac
    local pkgs; pkgs=$(dpkg-query -W -f='${Package}\n' "linux-image-*-$SUFFIX" "linux-headers-*-$SUFFIX" 2>/dev/null || true)
    [ -n "$pkgs" ] || { echo "No patched kernels installed"; exit 0; }
    echo "=== Removing: $pkgs"
    # shellcheck disable=SC2086
    dpkg --purge $pkgs
    echo "=== Done (build files stay in $WORK; delete them to free space)"
}

case "$CMD" in
    prepare) prepare ;;
    build)   build ;;
    install) install_kernel ;;
    remove)  remove_kernel ;;
    *) sed -n '2,15p' "$0"; exit 1 ;;
esac
