#!/usr/bin/env bash
# Install or remove the patched amdgpu module as an override of the distro's one.
#   sudo bash install.sh          install out/amdgpu.ko.zst into updates/, rebuild initramfs + UKI
#   sudo bash install.sh remove   delete the override, rebuild initramfs + UKI (back to stock)
#   bash install.sh status        show which amdgpu module is active
# depmod searches updates/ before the distro's kernel/ tree, and mkinitcpio's kms hook copies
# the module depmod resolves, so the override also lands in the initramfs. Reboot afterwards.
# Rebuilding the boot image uses Omarchy's limine-update; set REBUILD to use something else.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
kver=${KVER:-$(uname -r)}
dst=/usr/lib/modules/$kver/updates/amdgpu.ko.zst
rebuild=${REBUILD:-limine-update}

status() {
  echo "kernel         : $kver"
  echo "depmod resolves: $(modinfo -k "$kver" -n amdgpu)"
  echo "loaded srcver  : $(cat /sys/module/amdgpu/srcversion 2>/dev/null || echo n/a)"
  echo "override file  : $( [[ -e $dst ]] && modinfo -F srcversion "$dst" || echo none)"
}

case ${1:-install} in
  install)
    [[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
    [[ -f $here/out/amdgpu.ko.zst ]] || { echo "build first: bash build.sh <source>" >&2; exit 1; }
    [[ $(modinfo -F vermagic "$here/out/amdgpu.ko.zst") == "$kver "* ]] || { echo "vermagic mismatch: built for another kernel" >&2; exit 1; }
    install -Dm644 "$here/out/amdgpu.ko.zst" "$dst"
    depmod "$kver"
    # modinfo prints /lib/modules/...; /lib is a symlink to /usr/lib on Arch
    [[ $(realpath "$(modinfo -k "$kver" -n amdgpu)") == "$(realpath "$dst")" ]] || { echo "depmod does not prefer the override" >&2; exit 1; }
    $rebuild
    echo "installed $dst; reboot to use it"
    ;;
  remove)
    [[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
    rm -f "$dst"
    depmod "$kver"
    $rebuild
    echo "override removed; reboot to return to the stock module"
    ;;
  status) status ;;
  *) echo "usage: $0 [install|remove|status]" >&2; exit 2 ;;
esac
