#!/usr/bin/env bash
# Install or remove the guard for the patched amdgpu module (Arch-based distros with systemd).
#   sudo bash install.sh          install
#   sudo bash install.sh remove   remove
# Installs:
#   /usr/local/bin/amdgpu-override-check
#   amdgpu-override-check.service  (boot: s2idle, plain suspend, no hibernate if the module isn't loaded)
#   amdgpu-override-notify.service (user units, all users: desktop notification in that case)
#   /etc/pacman.d/hooks/amdgpu-override.hook (warns after a kernel update)
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)

case ${1:-install} in
  install)
    install -Dm755 "$here/amdgpu-override-check" /usr/local/bin/amdgpu-override-check
    install -Dm644 "$here/amdgpu-override-check.service" /etc/systemd/system/amdgpu-override-check.service
    install -Dm644 "$here/amdgpu-override-notify.service" /etc/systemd/user/amdgpu-override-notify.service
    install -Dm644 "$here/amdgpu-override.hook" /etc/pacman.d/hooks/amdgpu-override.hook
    systemctl daemon-reload
    systemctl enable amdgpu-override-check.service
    systemctl --global enable amdgpu-override-notify.service
    echo "installed; active from the next boot"
    ;;
  remove)
    systemctl disable amdgpu-override-check.service 2>/dev/null || true
    systemctl --global disable amdgpu-override-notify.service 2>/dev/null || true
    rm -f /usr/local/bin/amdgpu-override-check \
          /etc/systemd/system/amdgpu-override-check.service \
          /etc/systemd/user/amdgpu-override-notify.service \
          /etc/pacman.d/hooks/amdgpu-override.hook
    systemctl daemon-reload
    echo "removed"
    ;;
  *) echo "usage: $0 [install|remove]" >&2; exit 2 ;;
esac
