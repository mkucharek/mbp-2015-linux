#!/bin/bash
# Fedora only. Snapshots with snapper on Fedora's default btrfs layout (subvolumes "root" on / and "home" on /home):
#  - root: a pre/post snapshot pair around every dnf transaction, including Discover's (PackageKit
#    uses libdnf5 too, so the libdnf5 actions plugin runs for it), plus one snapshot a day as a fallback.
#    Keeps the last 20 update snapshots (10 pairs) and 7 daily ones.
#  - home: hourly snapshots; keeps 24 hourly, 7 daily and 2 weekly ones.
# /boot is ext4 and isn't snapshotted: kernels aren't rolled back with the system.
# Snapshots are on the same disk: they don't replace a backup to another disk.
# Restore steps are in fedora.md ("Snapshots").
# Run with:   sudo bash snapper-fedora.sh        Undo: sudo bash snapper-fedora.sh undo (deletes all snapshots)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo"; exit 1; }
[ -e /etc/fedora-release ] || { echo "Fedora only (dnf5, its actions plugin and Fedora's btrfs layout); Omarchy sets up snapper itself"; exit 1; }

ACTIONS=/etc/dnf/libdnf5-plugins/actions.d/snapper.actions
HELPER=/usr/local/libexec/dnf-snapper
admin=${SUDO_USER:-}

if [ "${1:-}" = "undo" ]; then
    echo "=== Undo: remove the dnf hook, the snapper configs and ALL their snapshots"
    read -r -p "Delete all snapshots of / and /home? [y/N] " a
    [ "$a" = y ] || exit 1
    rm -f "$ACTIONS" "$HELPER"
    systemctl disable --now snapper-timeline.timer snapper-cleanup.timer 2>/dev/null || true
    for c in home root; do
        snapper -c "$c" delete-config 2>/dev/null && echo "deleted config $c" || true
    done
    echo "=== Done (snapper and btrfs-assistant are still installed: sudo dnf remove snapper btrfs-assistant libdnf5-plugin-actions)"
    exit 0
fi

echo "=== Packages"
dnf install -y snapper btrfs-assistant libdnf5-plugin-actions

echo "=== snapper configs"
for c in root:/ home:/home; do
    name=${c%%:*} path=${c#*:}
    [ "$(findmnt -n -o FSTYPE "$path")" = btrfs ] || { echo "$path is not btrfs"; exit 1; }
    if snapper -c "$name" get-config >/dev/null 2>&1; then
        echo "config $name exists"
    else
        snapper -c "$name" create-config "$path"
        echo "created config $name for $path"
    fi
done

snapper -c root set-config \
    TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes \
    TIMELINE_LIMIT_HOURLY=0 TIMELINE_LIMIT_DAILY=7 TIMELINE_LIMIT_WEEKLY=0 \
    TIMELINE_LIMIT_MONTHLY=0 TIMELINE_LIMIT_YEARLY=0 \
    NUMBER_CLEANUP=yes NUMBER_LIMIT=20 NUMBER_LIMIT_IMPORTANT=10
snapper -c home set-config \
    TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes \
    TIMELINE_LIMIT_HOURLY=24 TIMELINE_LIMIT_DAILY=7 TIMELINE_LIMIT_WEEKLY=2 \
    TIMELINE_LIMIT_MONTHLY=0 TIMELINE_LIMIT_YEARLY=0
# Let the admin user list snapshots and open them in the file manager without sudo.
# File permissions inside the snapshots stay as they were (other users' homes stay private).
if [ -n "$admin" ]; then
    for c in root home; do
        snapper -c "$c" set-config ALLOW_USERS="$admin" SYNC_ACL=yes
    done
fi
systemctl enable --now snapper-timeline.timer snapper-cleanup.timer

echo "=== dnf/Discover hook: $ACTIONS"
install -d /usr/local/libexec
cat > "$HELPER" <<'EOF'
#!/bin/sh
# Called by the libdnf5 actions plugin (snapper.actions) around every transaction, from dnf or
# from Discover/PackageKit (also for updates installed on restart).
#   dnf-snapper pre <pid>          creates the pre snapshot, prints tmp.snapper_pre=<number>
#   dnf-snapper post [<pre number>] creates the matching post snapshot (none if the pre one failed)
# Falls back to --no-dbus if snapperd can't be reached. Never fails the transaction.
snap() { snapper -c root "$@" 2>/dev/null || snapper --no-dbus -c root "$@"; }
case "$1" in
    pre)
        cmd=$(ps -o command= -p "$2" 2>/dev/null)
        case "$cmd" in
            *packagekit*) desc="Discover/PackageKit" ;;
            "") desc="dnf" ;;
            *) desc=$(echo "$cmd" | cut -c1-100) ;;
        esac
        n=$(snap create -t pre -c number -p -d "$desc") && echo "tmp.snapper_pre=$n"
        ;;
    post)
        [ -n "${2:-}" ] && snap create -t post -c number --pre-number "$2"
        echo tmp.snapper_pre
        ;;
esac
exit 0
EOF
chmod 755 "$HELPER"
install -d "$(dirname "$ACTIONS")"
cat > "$ACTIONS" <<EOF
# snapper pre/post snapshots around every transaction (see $HELPER). Installed by snapper-fedora.sh.
pre_transaction::::$HELPER pre \${pid}
post_transaction::::$HELPER post \${tmp.snapper_pre}
EOF
command -v restorecon >/dev/null && restorecon -F "$HELPER" "$ACTIONS" || true

echo "=== Keep plocate's nightly index out of the snapshots"
if ! grep -q '^PRUNENAMES.*\.snapshots' /etc/updatedb.conf; then
    if grep -q '^PRUNENAMES' /etc/updatedb.conf; then
        sed -i 's/^PRUNENAMES *= *"/&.snapshots /' /etc/updatedb.conf
    else
        echo 'PRUNENAMES = ".snapshots"' >> /etc/updatedb.conf
    fi
fi
grep '^PRUNENAMES' /etc/updatedb.conf

echo "=== First snapshots"
snapper -c root create -c number -d "after snapper-fedora.sh"
snapper -c home create -c timeline -d "after snapper-fedora.sh"
snapper -c root list | tail -3
snapper -c home list | tail -3
echo "=== Done. GUI: btrfs-assistant (Snapper tab). Test the hook: sudo dnf install <small package>, then snapper -c root list"
