#!/bin/bash
# Wi-Fi: bring the BCM43602 back when its firmware stops answering after deep sleep (S3).
# Symptom: right after resume, dmesg shows "brcmf_msgbuf_query_dcmd: Timeout on response for
# query command", then endless brcmfmac -5 / -12 errors ("Failed to reserve space in commonring")
# and no networks. Reloading the driver reloads the chip's firmware; if that is not enough,
# the PCI device is removed and rescanned as well.
# Run with:   sudo bash wifi-reload.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo"; exit 1; }

# PCI address of the BCM43602 (14e4:43ba), looked up before the driver goes away
dev=$(grep -l 0x43ba /sys/bus/pci/devices/*/device 2>/dev/null | head -1)
dev=${dev%/device}

wifi_up() {
    for _ in $(seq 1 15); do
        for n in /sys/class/net/*; do
            [ -d "$n/wireless" ] && { echo "=== Wi-Fi interface $(basename "$n") is back"; return 0; }
        done
        sleep 1
    done
    return 1
}

unload() {
    # brcmfmac_wcc/_cyw/_bca (vendor glue) hold a reference to brcmfmac; remove them first
    local mods
    mods=$(lsmod | awk '$1 ~ /^brcmfmac_/ {print $1}')
    # shellcheck disable=SC2086
    modprobe -r $mods brcmfmac
}

echo "=== Reloading brcmfmac"
unload || echo "    unload failed, continuing"
sleep 1
modprobe brcmfmac
wifi_up && exit 0

if [ -n "$dev" ]; then
    echo "=== Still no interface: removing and rescanning PCI device $(basename "$dev")"
    unload
    echo 1 > "$dev/remove"
    sleep 2
    echo 1 > /sys/bus/pci/rescan
    modprobe brcmfmac
    wifi_up && exit 0
fi

echo "=== Wi-Fi did not come back; a reboot will. Log: journalctl -k -b | grep brcmf | tail -30"
exit 1
