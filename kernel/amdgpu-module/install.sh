#!/usr/bin/env bash
# Install or remove the patched amdgpu module as an override of the distro's one.
#   sudo bash install.sh          install out/amdgpu.ko.{zst,xz} into updates/, rebuild initramfs
#   sudo bash install.sh remove   delete the override, rebuild initramfs (back to stock)
#   bash install.sh status        show which amdgpu module is active
#   KVER=<version> ...            act on an installed kernel that isn't running
# depmod searches updates/ before the distro's kernel/ tree, and the initramfs tools copy the
# module depmod resolves, so the override also lands in the initramfs if amdgpu is in there.
# Reboot afterwards. The initramfs is rebuilt with Omarchy's limine-update if it exists,
# otherwise with dracut (Fedora); set REBUILD to use something else.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
kver=${KVER:-$(uname -r)}
mods=/usr/lib/modules/$kver/updates

if [[ -n ${REBUILD:-} ]]; then
  rebuild=$REBUILD
elif command -v limine-update >/dev/null; then
  rebuild=limine-update
else
  rebuild="dracut -f --kver $kver"
fi

override() { ls "$mods"/amdgpu.ko.* 2>/dev/null | head -1; }

status() {
  local o
  o=$(override)
  echo "kernel         : $kver"
  echo "depmod resolves: $(modinfo -k "$kver" -n amdgpu)"
  if [[ $kver == "$(uname -r)" ]]; then
    echo "loaded srcver  : $(cat /sys/module/amdgpu/srcversion 2>/dev/null || echo n/a)"
    echo "loaded taint   : $(cat /sys/module/amdgpu/taint 2>/dev/null) (O = out-of-tree, the patched one)"
  fi
  echo "override file  : $( [[ -n $o ]] && echo "$o, srcversion $(modinfo -F srcversion "$o")" || echo none)"
}

case ${1:-install} in
  install)
    [[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
    src=$(ls "$here"/out/amdgpu.ko.* 2>/dev/null | head -1)
    [[ -n $src ]] || { echo "build first: bash build.sh <source>" >&2; exit 1; }
    [[ $(modinfo -F vermagic "$src") == "$kver "* ]] || { echo "vermagic mismatch: $src is built for another kernel" >&2; exit 1; }
    rm -f "$mods"/amdgpu.ko.*
    install -Dm644 "$src" "$mods/$(basename "$src")"
    depmod "$kver"
    # modinfo prints /lib/modules/...; /lib is a symlink to /usr/lib
    [[ $(realpath "$(modinfo -k "$kver" -n amdgpu)") == "$(realpath "$mods/$(basename "$src")")" ]] || { echo "depmod does not prefer the override" >&2; exit 1; }
    $rebuild
    echo "installed $mods/$(basename "$src"); reboot to use it"
    ;;
  remove)
    [[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
    rm -f "$mods"/amdgpu.ko.*
    depmod "$kver"
    $rebuild
    echo "override removed; reboot to return to the stock module"
    ;;
  status) status ;;
  *) echo "usage: $0 [install|remove|status]" >&2; exit 2 ;;
esac
