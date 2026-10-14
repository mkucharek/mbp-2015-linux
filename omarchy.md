# Omarchy on the 2015 MacBook Pro

As of 2026-10-14. Omarchy-specific setup only; the hardware findings, kernel parameter reasons and sleep results are in [hardware.md](hardware.md).

**Install:** Omarchy 4.0.4, linux-omarchy 7.2.5, Limine 12.8 booting a UKI, LUKS + btrfs (`subvol=@`), Hyprland on Wayland, Mesa 26.2.

## Current setup

| Setting | Value | Where |
| --- | --- | --- |
| GPU driver | `radeon.si_support=0 amdgpu.si_support=1` | `/etc/default/limine` |
| amdgpu video blocks off | `amdgpu.ip_block_mask=0x7f` | `/etc/default/limine` |
| amdgpu deep-sleep fix | patched `amdgpu.ko` (reset at load) | `/usr/lib/modules/7.2.5-3-omarchy/updates/`; built for that kernel only, see [Patched amdgpu module](#patched-amdgpu-module) |
| IOMMU off, NVMe APST off | `intel_iommu=off nvme_core.default_ps_max_latency_us=0` | `/etc/limine-entry-tool.d/hardware-quirks.conf` |
| Sleep mode | `mem_sleep_default=deep` | `/etc/limine-entry-tool.d/hardware-quirks.conf` |
| Lid close | suspend-then-hibernate, hibernate after 2 h | `/etc/systemd/logind.conf.d/30-lid-suspend-then-hibernate.conf`, `/etc/systemd/sleep.conf.d/suspend-then-hibernate.conf` |
| Bluetooth fix | btusb option + udev rule + `bt-check.service` | [bluetooth/bt-fix.sh](bluetooth/bt-fix.sh) |
| Wi-Fi sleep hook | unloads brcmfmac before deep sleep and hibernate | `/usr/lib/systemd/system-sleep/brcmfmac`, from [wifi/brcmfmac-sleep](wifi/brcmfmac-sleep) |
| Fans | no daemon (SMC automatic) | — |

**Decision (2026-10-14):** stay on amdgpu for Vulkan and a working Chromium. With the patched module, deep sleep works at about 0.46 W (about 9 days on a full battery) instead of s2idle at about 22 W. **A kernel update brings back the stock module, which hangs on resume from deep sleep:** switch to s2idle before updating linux-omarchy, and back to deep after rebuilding the module (see below).

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

- **Lid:** `30-lid-suspend-then-hibernate.conf` (`HandleLidSwitch=suspend-then-hibernate`), with `HibernateDelaySec=2h` in `/etc/systemd/sleep.conf.d/suspend-then-hibernate.conf`. Closing the lid goes into deep sleep (S3) and hibernates after 2 h. Idle: Omarchy defaults (no automatic suspend).
- **logind drop-ins:**
  - `10-ignore-power-button.conf` (`HandlePowerKey=ignore`)
  - `30-lid-suspend-then-hibernate.conf` (see Lid above)
  - `20-inhibit-delay.conf` (`InhibitDelayMaxSec=15`, which gives `omarchy-sleep-lock.service` time to lock before sleep)
- **Hibernate works** (`systemctl hibernate`) with the patched module and the Wi-Fi sleep hook. Omarchy's installer set it up:
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

## Patched amdgpu module

The patch and the reason for it are in [hardware.md](hardware.md#deep-sleep-on-amdgpu). Build only `amdgpu.ko` for the installed linux-omarchy and install it as an override. The build needs the same source as the installed kernel: the kernel.org release plus linux-omarchy's own patches.

1. Install the headers: `sudo pacman -S linux-omarchy-headers`.
2. Download the kernel.org tarball for the version in `pacman -Q linux-omarchy` (for example `linux-7.2.5.tar.xz`), and unpack it.
3. Download the linux-omarchy patches from [omacom-io/omarchy-pkgs](https://github.com/omacom-io/omarchy-pkgs) (`pkgbuilds/linux-omarchy/`), from the commit that matches the installed package release.
4. Apply them in their numbered order: `for p in /path/to/patches/*.patch; do patch -Np1 < "$p"; done`.
5. Apply the fix: `patch -p1 < kernel/amdgpu-si-reset-on-init.patch`.
6. Build the module: `bash kernel/amdgpu-module/build.sh /path/to/linux-7.2.5`. This takes about 7 minutes.
7. Install it: `sudo bash kernel/amdgpu-module/install.sh`. This also rebuilds the initramfs and UKI.
8. Reboot, then check the log: `journalctl -k -b | grep -E 'PCI CONFIG reset|GPU posting|VRAM:'` must show VRAM at `0x000000F400000000`.

The module is unsigned, so loading it taints the kernel. That's harmless here, because the kernel doesn't enforce module signatures.

**Kernel updates:** the module only matches the kernel it was built for.

1. Before updating, switch to s2idle: `sudo sed -i 's/mem_sleep_default=deep/mem_sleep_default=s2idle/' /etc/limine-entry-tool.d/hardware-quirks.conf && sudo limine-update`.
2. Update and reboot. The stock module is active now, and s2idle works with it.
3. Rebuild the module for the new version (steps 2–8 above).
4. Switch back to deep: the same `sed` with `s2idle` and `deep` swapped, then `sudo limine-update` and reboot.

While the stock module is active, don't close the lid for longer than `HibernateDelaySec`, or hibernate by hand: hibernate is only tested with the patched module.

Once the fix is in a linux-omarchy release, remove the override with `sudo bash kernel/amdgpu-module/install.sh remove`, and keep `mem_sleep_default=deep`.

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
- [x] Wi-Fi sleep hook installed (2026-10-14); if Wi-Fi still dies after deep sleep, run `sudo bash wifi/wifi-reload.sh`
- [ ] FaceTime HD camera: AUR `facetimehd-dkms` + `facetimehd-firmware`, blacklist `bdc_pci`
- [ ] amdgpu patch upstream: watch [drm/amd #5978](https://gitlab.freedesktop.org/drm/amd/-/issues/5978) and amd-gfx; remove the override once the fix is in linux-omarchy
- [x] Test hibernate with the amdgpu patch: works once brcmfmac is unloaded first (2026-10-14)
- [x] Deep-sleep cycle through systemd with the Wi-Fi hook: resumes, Wi-Fi back in ~4.5 s (2026-10-14)
- [x] suspend-then-hibernate on lid close: works with the fixed Wi-Fi hook (2026-10-15)
- [ ] Optional: radeon + deep + MTRR-patched kernel
- [ ] Optional: test hibernate on radeon
- [ ] Optional, risky: boot-time Intel-only GPU mode (gpu-switch)
