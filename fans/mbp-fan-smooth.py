#!/usr/bin/python3 -I
"""Smoothed fan control for MacBookPro11,5 (replaces mbpfan).

mbpfan reacts to the raw CPU temperature, which jumps 70 -> 100 C within half a
second of any burst on this Haswell, so the fans went from minimum to near-max
for every short task. This daemon instead:
  * follows a smoothed temperature (exponential average, time constant TAU),
  * maps it linearly from T_LOW (fans at minimum) to T_HIGH (fans at maximum),
  * limits how fast the fans may speed up / slow down.
Sustained heavy load still reaches full speed (about 20-25 s). Failsafe: if the
raw temperature stays >= 98 C for 5 s, the fans go straight to maximum until the
raw temperature stays below 85 C for 5 s. The CPU also throttles itself at 100 C.

Install/undo: fan-smooth.sh (same folder). Test without root: python3 mbp-fan-smooth.py --dry-run
"""
import glob
import math
import signal
import sys
import time

SMC = "/sys/devices/platform/applesmc.768"

T_LOW = 70.0       # smoothed temp at/below which fans run at minimum
T_HIGH = 90.0      # smoothed temp at/above which fans run at maximum
TAU = 15.0         # smoothing time constant, seconds
UP_RPM_S = 200     # max speed-up per second (normal)
DOWN_RPM_S = 100   # max slow-down per second
HOT_RAW = 95       # raw temp counted as "really hot"
HOT_SECS = 10      # ...for this many seconds in a row -> fast ramp
HOT_UP_RPM_S = 600 # speed-up per second while really hot
CRIT_RAW = 98      # failsafe: raw temp at/above this (CPU throttles itself at 100) ...
CRIT_SECS = 5      # ...for this many seconds in a row -> fans to maximum at once
CRIT_RELEASE = 85  # failsafe ends when the raw temp stays below this for CRIT_SECS
INTERVAL = 1.0
LOG_EVERY = 60     # seconds between status lines in the journal


def read_int(path):
    with open(path) as f:
        return int(f.read().strip())


def write(path, value):
    with open(path, "w") as f:
        f.write(str(value))


def temp_inputs():
    """CPU core/package sensors plus the AMD GPU sensor."""
    paths = []
    for hw in glob.glob("/sys/class/hwmon/hwmon*"):
        try:
            with open(hw + "/name") as f:
                name = f.read().strip()
        except OSError:
            continue
        if name in ("coretemp", "radeon", "amdgpu"):
            paths += glob.glob(hw + "/temp*_input")
    if not paths:
        sys.exit("no coretemp sensors found")
    return paths


def max_temp(paths):
    vals = []
    for p in paths:
        try:
            vals.append(read_int(p) / 1000)
        except OSError:
            pass
    return max(vals) if vals else 100.0  # unreadable -> assume hot


def fans():
    out = []
    for f in sorted(glob.glob(SMC + "/fan*_min")):
        base = f[: -len("_min")]
        out.append({
            "base": base,
            "min": read_int(base + "_min"),
            "max": read_int(base + "_max"),
            "rpm": float(read_int(base + "_input")),
        })
    if not out:
        sys.exit("no applesmc fans found")
    return out


def main():
    dry = "--dry-run" in sys.argv
    sensors = temp_inputs()
    fan_list = fans()

    def release(*_):
        # Hand control back to the SMC firmware, which runs its own safe curve.
        if not dry:
            for fan in fan_list:
                try:
                    write(fan["base"] + "_manual", 0)
                except OSError:
                    pass
        sys.exit(0)

    signal.signal(signal.SIGTERM, release)
    signal.signal(signal.SIGINT, release)

    if not dry:
        for fan in fan_list:
            write(fan["base"] + "_manual", 1)

    smooth = max_temp(sensors)
    hot_count = 0
    crit_count = 0
    cool_count = 0
    failsafe = False
    alpha = 1 - math.exp(-INTERVAL / TAU)
    last_log = 0.0
    print(f"start: T_LOW={T_LOW} T_HIGH={T_HIGH} TAU={TAU}s "
          f"up={UP_RPM_S}/s down={DOWN_RPM_S}/s dry_run={dry}", flush=True)

    while True:
        raw = max_temp(sensors)
        smooth += alpha * (raw - smooth)
        hot_count = hot_count + 1 if raw >= HOT_RAW else 0
        up = HOT_UP_RPM_S if hot_count >= HOT_SECS else UP_RPM_S
        crit_count = crit_count + 1 if raw >= CRIT_RAW else 0
        cool_count = cool_count + 1 if raw < CRIT_RELEASE else 0
        if not failsafe and crit_count >= CRIT_SECS:
            failsafe = True
            print(f"FAILSAFE on: raw {raw:.0f} C for {CRIT_SECS}s, fans to max", flush=True)
        elif failsafe and cool_count >= CRIT_SECS:
            failsafe = False
            print(f"failsafe off: raw below {CRIT_RELEASE} C for {CRIT_SECS}s", flush=True)

        level = min(1.0, max(0.0, (smooth - T_LOW) / (T_HIGH - T_LOW)))
        for fan in fan_list:
            target = fan["min"] + level * (fan["max"] - fan["min"])
            if failsafe:
                fan["rpm"] = fan["max"]
            else:
                step = max(-DOWN_RPM_S * INTERVAL, min(up * INTERVAL, target - fan["rpm"]))
                fan["rpm"] = min(fan["max"], max(fan["min"], fan["rpm"] + step))
            if not dry:
                # The SMC can drop back to automatic mode (e.g. after resume).
                if read_int(fan["base"] + "_manual") != 1:
                    write(fan["base"] + "_manual", 1)
                write(fan["base"] + "_output", int(fan["rpm"]))

        now = time.monotonic()
        if dry or now - last_log >= LOG_EVERY:
            speeds = "/".join(str(int(f["rpm"])) for f in fan_list)
            print(f"raw={raw:.0f} smooth={smooth:.1f} fans={speeds}", flush=True)
            last_log = now
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
