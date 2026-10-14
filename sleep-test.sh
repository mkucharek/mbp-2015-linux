#!/bin/bash
# Measure battery drain of a sleep mode on the MacBookPro11,5 (Omarchy port of the Mint sleep-test.sh).
# Sleeps for N minutes, wakes by itself (RTC alarm), then reports average watts and kernel resume time.
# Run ON BATTERY (unplugged), lid open, nothing heavy running.
#   sudo bash sleep-test.sh s2idle 10
#   sudo bash sleep-test.sh awake 10     # baseline: stay awake and idle for comparison
#   sudo bash sleep-test.sh deep 10      # radeon, or amdgpu with the si_fb_restore fix (stock amdgpu hangs)
# Lid (LID0) and internal keyboard/trackpad/Bluetooth wakeups are disabled during the test,
# because with the lid open the Mac wakes after ~2 s. Add "usbwake" to keep the USB ones.
# The original mem_sleep mode and wakeup settings are restored afterwards.
# If it doesn't wake by itself: press the power button briefly.
set -euo pipefail
export LC_ALL=C
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo"; exit 1; }
MODE=${1:-}; MIN=${2:-10}; OPT=${3:-}
[[ "$MODE" == deep || "$MODE" == s2idle || "$MODE" == awake ]] || { echo "Usage: sudo bash $0 s2idle|awake|deep [minutes] [usbwake]"; exit 1; }
BAT=/sys/class/power_supply/BAT0
[ "$(cat /sys/class/power_supply/ADP1/online 2>/dev/null || echo 0)" = 0 ] || { echo "Unplug the charger first"; exit 1; }
if [ "$MODE" = deep ] && [ "$(cat /sys/module/amdgpu/initstate 2>/dev/null)" = live ] &&
   [ "$(cat /sys/module/amdgpu/parameters/si_fb_restore 2>/dev/null || echo 0)" = 0 ]; then
    echo "amdgpu without the si_fb_restore fix is loaded: deep sleep will hang on resume. Aborting."; exit 1
fi

# Energy used = charge used (uAh) x mean voltage. Not charge x voltage at each end: the voltage sags
# ~0.7 V right after unplugging, which would count as several Wh of phantom drain.
charge_uah() { cat $BAT/charge_now; }
volt_uv() { cat $BAT/voltage_now; }

MEM_SLEEP_ORIG=$(sed -E 's/.*\[([a-z0-9]+)\].*/\1/' /sys/power/mem_sleep)
declare -A WAKE_ORIG=()
for d in /sys/bus/usb/devices/*; do
    case "$(cat "$d/idVendor" 2>/dev/null):$(cat "$d/idProduct" 2>/dev/null)" in
        05ac:0274|05ac:8290) [ -f "$d/power/wakeup" ] && WAKE_ORIG[$d/power/wakeup]=$(cat "$d/power/wakeup") ;;
    esac
done
# /proc/acpi/wakeup: writing a device name TOGGLES it, so only toggle LID0 if it's enabled now
LID_TOGGLED=0
restore() {
    echo "$MEM_SLEEP_ORIG" > /sys/power/mem_sleep
    for f in "${!WAKE_ORIG[@]}"; do echo "${WAKE_ORIG[$f]}" > "$f"; done
    if [ "$LID_TOGGLED" = 1 ] && ! grep -qE '^LID0.*\*enabled' /proc/acpi/wakeup; then
        echo LID0 > /proc/acpi/wakeup
    fi
}
trap restore EXIT

if [ "$MODE" != awake ]; then
    if grep -qE '^LID0.*\*enabled' /proc/acpi/wakeup; then
        echo LID0 > /proc/acpi/wakeup; LID_TOGGLED=1
        echo "Lid wakeup disabled for this test"
    fi
    if [ "$OPT" != usbwake ]; then
        for f in "${!WAKE_ORIG[@]}"; do echo disabled > "$f"; done
        echo "USB wakeup disabled for this test: keyboard/trackpad + Bluetooth"
    fi
    echo "$MODE" > /sys/power/mem_sleep
    echo "mem_sleep: $(cat /sys/power/mem_sleep)"
fi

# Wake-source counters (ACPI GPEs + wakeup sources), compared after waking
snap() {
    grep -H . /sys/firmware/acpi/interrupts/gpe[0-9A-F]* 2>/dev/null | awk -F'[: ]+' '{print $1, $2}' | sed 's|.*/||'
    for w in /sys/class/wakeup/*; do echo "$(cat "$w/name" 2>/dev/null)@$(basename "$w") $(cat "$w/event_count" 2>/dev/null)"; done
}
snap > /tmp/sleep-test.before
# Awake power right before sleeping (current x voltage, averaged over 5 s). Used to subtract the
# time the Mac is awake inside the measured window: suspending, the slow resume (~13 s here, see
# the MTRR bug in hardware.md) and the 5 s voltage settle afterwards.
watts_now() { awk -v i="$(cat $BAT/current_now)" -v v="$(volt_uv)" 'BEGIN { print i * v / 1e12 }'; }
p_awake=0
for _ in 1 2 3 4 5; do p_awake=$(awk -v a="$p_awake" -v b="$(watts_now)" 'BEGIN { print a + b / 5 }'); sleep 1; done
echo "=== $MODE for $MIN min (battery $(($(charge_uah)/1000)) mAh, awake draw $(printf %.1f "$p_awake") W)"
q0=$(charge_uah); v0=$(volt_uv); t0=$(date +%s.%N)
if [ "$MODE" = awake ]; then
    sleep $((MIN*60))
else
    rtcwake -m mem -s $((MIN*60)) >/dev/null
fi
q1=$(charge_uah); t1=$(date +%s.%N)   # charge is a coulomb counter: read it at once
sleep 5                               # but let the battery voltage settle
v1=$(volt_uv)
snap > /tmp/sleep-test.after

full_wh=$(awk -v c="$(cat $BAT/charge_full)" -v v="$(cat $BAT/voltage_min_design)" 'BEGIN { print c * v / 1e12 }')
awk -v q0="$q0" -v q1="$q1" -v v0="$v0" -v v1="$v1" -v t0="$t0" -v t1="$t1" -v full="$full_wh" \
    -v mode="$MODE" -v n="$((MIN*60))" -v pa="$p_awake" 'BEGIN {
    sec = t1 - t0; mwh = (q0 - q1) * (v0 + v1) / 2 / 1e9; raw = mwh / 1000 / (sec / 3600)
    printf "=== Result: %s\n  %.0f s, used %d mAh = %d mWh = %.2f W average over the whole window\n", mode, sec, (q0 - q1) / 1000, mwh, raw
    w = raw
    # The RTC alarm fires n s after t0, so the Mac sleeps ~n s; the rest of the window is awake.
    awake = sec - n
    if (mode != "awake" && awake > 0 && awake < 120) {
        smwh = mwh - pa * awake / 3.6
        w = smwh / 1000 / (n / 3600)
        printf "  minus ~%.0f s awake at %.1f W = %d mWh asleep = %.2f W while asleep\n", awake, pa, smwh, w
        if (smwh < 0.1 * mwh) print "  (most of the charge went to the awake part; run longer for a reliable figure)"
    }
    if (w > 0) printf "  full battery (~%.0f Wh) would last ~%.0f h in this mode\n", full, full / w
}'

if [ "$MODE" != awake ] && [ "${t1%.*}" -lt $(( ${t0%.*} + MIN*60*8/10 )) ]; then
    echo "  WOKE EARLY (after $(( ${t1%.*} - ${t0%.*} )) s). Wake counters that changed:"
    join <(sort /tmp/sleep-test.before) <(sort /tmp/sleep-test.after) | awk '$2!=$3 {printf "    %-28s %s -> %s\n", $1, $2, $3}'
fi

[ "$MODE" = awake ] && exit 0
# Kernel resume time: from leaving sleep to "PM: suspend exit"
journalctl -k -b --no-pager -o short-monotonic | awk '
    { match($0, /[0-9]+\.[0-9]+/); ts=substr($0, RSTART, RLENGTH) }
    /PM: suspend entry/ { s=""; e=""; gap=0; ll=0; prev=ts }   # only the latest suspend counts
    # s2idle: the kernel clock runs while asleep, so waking = the line after the largest gap
    prev!="" && ts-prev>gap { gap=ts-prev; if (!ll) s=ts }
    { prev=ts }
    /Low-level resume complete/ { s=ts; ll=1 }               # deep (S3): exact wake point
    /PM: suspend exit/ { e=ts }
    END { if (s && e) printf "  kernel resume: %.1f s\n", e-s; else print "  kernel resume: not found in log" }'
