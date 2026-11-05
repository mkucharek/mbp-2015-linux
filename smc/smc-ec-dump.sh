#!/bin/bash
# Read-only dump of every SMC key (applesmc) and the EC RAM, for comparing a good and a bad
# state of the Mac (see hardware.md, "Mac powers on by itself when the charger is plugged in").
#   sudo bash smc-ec-dump.sh <label> [dir]    writes <dir>/<label>-smc.txt and <label>-ec.txt
set -euo pipefail
label=${1:?usage: $0 <label> [dir]}
dir=${2:-.}
d=/sys/devices/platform/applesmc.768
n=$(cat $d/key_count)
for ((i = 0; i < n; i++)); do
    echo $i > $d/key_at_index
    printf '%s %s %s\n' "$(cat $d/key_at_index_name)" "$(cat $d/key_at_index_type)" \
        "$(od -An -tx1 $d/key_at_index_data 2>/dev/null | tr -d '\n')"
done > "$dir/$label-smc.txt"
modprobe ec_sys
od -Ax -tx1 /sys/kernel/debug/ec/ec0/io > "$dir/$label-ec.txt"
[ -n "${SUDO_USER:-}" ] && chown "$SUDO_USER:" "$dir/$label"-*.txt
echo "wrote $dir/$label-smc.txt $dir/$label-ec.txt"
