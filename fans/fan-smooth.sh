#!/bin/bash
# Fans: replace mbpfan with mbp-fan-smooth (smoothed temperature + limited ramp speed + failsafe).
# Run with:   sudo bash fan-smooth.sh    (also after editing mbp-fan-smooth.py, to reinstall)
# Undo:       sudo bash fan-smooth.sh undo   (back to mbpfan if installed, else SMC automatic)
# Only use this if the SMC's own fan control misbehaves: on Omarchy it was fine with no daemon.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)

if [ "${1:-}" = "undo" ]; then
    echo "=== Undo: back to mbpfan / SMC automatic"
    systemctl disable --now mbp-fan-smooth.service 2>/dev/null || true
    rm -f /etc/systemd/system/mbp-fan-smooth.service /usr/local/sbin/mbp-fan-smooth
    systemctl daemon-reload
    if systemctl cat mbpfan.service >/dev/null 2>&1; then
        systemctl enable --now mbpfan; systemctl is-active mbpfan
    fi
    echo "=== Done"
    exit 0
fi

echo "=== Install mbp-fan-smooth, replace mbpfan"
install -m 755 "$HERE/mbp-fan-smooth.py" /usr/local/sbin/mbp-fan-smooth
cat > /etc/systemd/system/mbp-fan-smooth.service <<'EOF'
[Unit]
Description=Smoothed MacBook fan control (replaces mbpfan)
After=sysinit.target
Conflicts=mbpfan.service
StartLimitIntervalSec=0

[Service]
ExecStart=/usr/local/sbin/mbp-fan-smooth
# Whatever happens to the daemon, hand the fans back to the SMC's own automatic control.
ExecStopPost=/bin/sh -c 'for f in /sys/devices/platform/applesmc.768/fan*_manual; do echo 0 > "$f"; done'
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl disable --now mbpfan 2>/dev/null || true
systemctl enable mbp-fan-smooth.service
systemctl restart mbp-fan-smooth.service
sleep 3

echo "=== Status"
systemctl is-active mbp-fan-smooth
journalctl -u mbp-fan-smooth -b --no-pager | tail -3
echo "fans: $(cat /sys/devices/platform/applesmc.768/fan1_input)/$(cat /sys/devices/platform/applesmc.768/fan2_input) rpm"
echo "=== Done"
