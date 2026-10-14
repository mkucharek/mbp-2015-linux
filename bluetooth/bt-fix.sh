#!/bin/bash
# Bluetooth: stop the intermittent "hci0: BCM: Reset failed (-110)" at boot (Omarchy port of the Mint bt-fix.sh).
#  - keeps the Apple BCM20703 chip (USB 05ac:8290) out of USB autosuspend; suspending it fails
#    ("usb 1-8: Failed to suspend device, error -110") and can leave the chip hung.
#    Omarchy's /etc/modprobe.d/omarchy-usb-autosuspend.conf doesn't help: usbcore is built into the
#    kernel, so that option is ignored, and btusb enables autosuspend on the chip by itself anyway.
#  - boot check: if no controller appears, reset the chip on the USB bus and reload btusb
# Run with:   sudo bash bt-fix.sh        Undo: sudo bash bt-fix.sh undo
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo"; exit 1; }

RULE=/etc/udev/rules.d/50-apple-bt-no-autosuspend.rules

if [ "${1:-}" = "undo" ]; then
    echo "=== Undo: Bluetooth defaults"
    systemctl disable bt-check.service 2>/dev/null || true
    rm -f /etc/systemd/system/bt-check.service /usr/local/sbin/bt-check \
          /etc/modprobe.d/btusb-no-autosuspend.conf "$RULE"
    systemctl daemon-reload
    udevadm control --reload
    echo "=== Done (autosuspend settings return to default after reboot)"
    exit 0
fi

echo "=== Disable autosuspend: btusb driver + USB device"
echo "options btusb enable_autosuspend=0" > /etc/modprobe.d/btusb-no-autosuspend.conf
echo N > /sys/module/btusb/parameters/enable_autosuspend
echo 'ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="05ac", ATTR{idProduct}=="8290", TEST=="power/control", ATTR{power/control}="on"' > "$RULE"
udevadm control --reload
for d in /sys/bus/usb/devices/*; do
    if [ "$(cat "$d/idVendor" 2>/dev/null):$(cat "$d/idProduct" 2>/dev/null)" = "05ac:8290" ]; then
        echo on > "$d/power/control"
        echo "$(basename "$d") power/control: $(cat "$d/power/control")"
    fi
done

echo "=== Boot check (USB reset + btusb reload, up to 3x, if no controller shows up)"
cat > /usr/local/sbin/bt-check <<'EOF'
#!/bin/bash
# Apple BCM20703 sometimes misses its reset at boot ("Reset failed (-110)") and bluetoothd
# then has no controller. Reloading btusb alone doesn't recover a hung chip, so reset it
# on the USB bus too. Log: journalctl -u bt-check
usb_reset() {   # USBDEVFS_RESET ioctl on 05ac:8290 (usbreset isn't installed on Omarchy)
    local d
    for d in /sys/bus/usb/devices/*; do
        [ "$(cat "$d/idVendor" 2>/dev/null):$(cat "$d/idProduct" 2>/dev/null)" = "05ac:8290" ] || continue
        python3 -I -c 'import fcntl, sys; fcntl.ioctl(open(sys.argv[1], "wb"), 21780, 0)' \
            "$(printf '/dev/bus/usb/%03d/%03d' "$(cat "$d/busnum")" "$(cat "$d/devnum")")" \
            && echo "USB reset done ($(basename "$d"))" && return 0
    done
    echo "USB reset failed or chip not on the bus"
}
for attempt in 1 2 3; do
    for _ in $(seq 10); do
        timeout 3 bluetoothctl list 2>/dev/null | grep -q '^Controller' && { echo "controller OK"; exit 0; }
        sleep 1
    done
    echo "no Bluetooth controller, USB reset + btusb reload (attempt $attempt)"
    modprobe -r btusb; sleep 1
    usb_reset || true; sleep 2
    modprobe btusb; sleep 3
done
echo "Bluetooth controller still missing after 3 attempts (try suspend + wake, or a full shutdown + power-on)"
exit 1
EOF
chmod 755 /usr/local/sbin/bt-check
cat > /etc/systemd/system/bt-check.service <<'EOF'
[Unit]
Description=Reset Bluetooth if the controller failed to initialise
After=bluetooth.service
Wants=bluetooth.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/bt-check

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable bt-check.service

echo "=== Status"
echo "btusb autosuspend: $(cat /sys/module/btusb/parameters/enable_autosuspend)"
if ! timeout 3 bluetoothctl list | grep -q '^Controller'; then
    echo "Bluetooth controller missing now -> running the check"
    /usr/local/sbin/bt-check || true
fi
timeout 3 bluetoothctl list || true
echo "=== Done"
