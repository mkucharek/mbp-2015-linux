# Omarchy on the 2015 MacBook Pro

As of 2026-10-14. Omarchy-specific setup only; the hardware findings, kernel parameter reasons and sleep results are in [hardware.md](hardware.md).

**Install:** Omarchy 4.0.4, linux-omarchy 7.2.5, Limine 12.8 booting a UKI, LUKS + btrfs (`subvol=@`), Hyprland on Wayland, Mesa 26.2.

## Current setup

| Setting | Value | Where |
| --- | --- | --- |
| GPU driver | `radeon.si_support=0 amdgpu.si_support=1` | `/etc/default/limine` |
| amdgpu video blocks off | `amdgpu.ip_block_mask=0x7f` | `/etc/default/limine` |
| IOMMU off, NVMe APST off | `intel_iommu=off nvme_core.default_ps_max_latency_us=0` | `/etc/limine-entry-tool.d/hardware-quirks.conf` |
| Sleep mode | `mem_sleep_default=s2idle` | `/etc/limine-entry-tool.d/hardware-quirks.conf` |
| Bluetooth fix | btusb option + udev rule + `bt-check.service` | [bluetooth/bt-fix.sh](bluetooth/bt-fix.sh) |
| Fans | no daemon (SMC automatic) | — |

**Decision (2026-10-14):** stay on amdgpu for Vulkan and a working Chromium, accepting that sleep is s2idle at about 22 W (about 5 h on a full battery). Shut down for long breaks. If real sleep becomes more important, switch to radeon + deep (see Fallback).

## Boot options

Kernel parameters go in `/etc/default/limine` or a drop-in under `/etc/limine-entry-tool.d/`. Run `sudo limine-update` and reboot. Don't edit the files owned by the omarchy-settings package, because updates overwrite them.

| File | Owner | Contents |
| --- | --- | --- |
| `/etc/default/limine` | you | `ESP_PATH`, base cmdline (LUKS, btrfs, `zswap.enabled=0`), GPU driver + `ip_block_mask` |
| `limine-entry-tool.d/hardware-quirks.conf` | you | Mac workarounds + `mem_sleep_default` |
| `limine-entry-tool.d/resume.conf` | Omarchy install | `resume=/dev/mapper/root resume_offset=1941580` |
| `limine-entry-tool.d/omarchy-defaults.conf` | omarchy-settings | `quiet splash …`, `initramfs_async=0` (works around a kernel 7.1 race that breaks the themed LUKS prompt), boot order, snapshot entries |
| `limine-entry-tool.d/omarchy-uki.conf` | omarchy-settings | `ENABLE_UKI=yes` (overrides `ENABLE_UKI=no` in `/etc/limine-entry-tool.conf`) |

```bash
sudo limine-update                                    # rebuilds /boot/EFI/Linux/omarchy_linux-omarchy.efi + /boot/limine.conf
sudo grep -c 'mem_sleep_default' /boot/limine.conf    # /boot is root-only
cat /proc/cmdline                                     # after reboot
```

- `limine-update` prints `Possibly missing firmware for module: 'xhci_pci_renesas'` and `'qat_6xxx'`. Both are harmless; that hardware isn't in this Mac.
- Only the main entry gets new parameters. Snapshot boot entries keep the command line they were created with.
- The early-GPU-driver requirement (see hardware.md) is already covered by Omarchy's mkinitcpio `kms` hook; no `MODULES=` change is needed.

## Sleep, lid and power

- **Lid / idle:** Omarchy defaults, with no `HandleLidSwitch` override, so closing the lid suspends into s2idle.
- **logind drop-ins:**
  - `10-ignore-power-button.conf` (`HandlePowerKey=ignore`)
  - `20-inhibit-delay.conf` (`InhibitDelayMaxSec=15`, which gives `omarchy-sleep-lock.service` time to lock before sleep)
- **Hibernate is prepared but unusable on amdgpu:**
  - `/swap/swapfile` (15.5 GB, plus zram at higher priority)
  - `resume.conf`
  - the mkinitcpio drop-in `omarchy_resume.conf`, which adds the `resume` hook after `encrypt`
- **Module options from Omarchy's installer:** `/etc/modprobe.d/brcmfmac.conf` (`feature_disable=0x82000`, from `install/hardware/apple/fix-brcmfmac-supplicant.sh`) and `hid_apple.conf` (`fnmode=2`, from `install/hardware/fix-fkeys.sh`).
- **`/etc/modprobe.d/omarchy-usb-autosuspend.conf`** (owned by omarchy-settings) (`usbcore autosuspend=-1`) is ignored, because usbcore is built in. The live value is `2`.
- **thermald** is enabled.
- **`omarchy-system-sleep-monitor`** logs a harmless `dbus-monitor ... AccessDenied ... Falling back to eavesdropping` on every boot.

## GPU / apps

- **Chromium:** on amdgpu it needs no flags. `~/.config/chromium-flags.conf` holds only Omarchy's defaults (Wayland, gnome-libsecret, touchpad overscroll). When testing flags, use a throwaway `--user-data-dir`, or the test instance can take over your real profile.
- **Hyprland:** no `AQ_DRM_DEVICES` is set. If you ever pin a GPU, use `/dev/dri/by-path/`.
- **One-off amdgpu crash:** an early boot crashed with no suspend involved (`ring gfx timeout` from Hyprland, `GPU Recovery Failed: -110`). It hasn't happened since.

## Fallback: radeon + deep sleep

```bash
sudo sed -i 's/radeon.si_support=0 amdgpu.si_support=1 amdgpu.ip_block_mask=0x7f/radeon.si_support=1 amdgpu.si_support=0/' /etc/default/limine
sudo sed -i '/mem_sleep_default=s2idle/d' /etc/limine-entry-tool.d/hardware-quirks.conf
sudo limine-update   # then reboot and test: sudo rtcwake -m mem -s 20
```

You lose Vulkan, and the Chromium artifacts seen on radeon here are unexplained. Waking takes about 20 s unless you build linux-omarchy with the MTRR patch (not done; [kernel/build-kernel-ubuntu.sh](kernel/build-kernel-ubuntu.sh) is Ubuntu-only, but [kernel/mtrr-resume.patch](kernel/mtrr-resume.patch) can go into a linux-omarchy PKGBUILD).

## Open items

- [x] Measure s2idle drain: ~22 W (2026-10-14)
- [ ] Run `bluetooth/bt-fix.sh`, then watch `journalctl -u bt-check -b` over the next few boots
- [ ] FaceTime HD camera: AUR `facetimehd-dkms` + `facetimehd-firmware`, blacklist `bdc_pci`
- [ ] Optional: radeon + deep + MTRR-patched kernel
- [ ] Optional: test hibernate on radeon
- [ ] Optional, risky: boot-time Intel-only GPU mode (gpu-switch)
