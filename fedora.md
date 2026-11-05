# Fedora KDE on the 2015 MacBook Pro

As of 2026-11-05: **planned, not installed yet.** Fedora-specific setup only; the hardware findings, kernel parameter reasons and sleep results are in [hardware.md](hardware.md).

## Why Fedora KDE

The Mac is moving from Omarchy to a family laptop used for gaming. Gaming needs Vulkan, so amdgpu, and deep sleep on amdgpu needs the fix from [hardware.md](hardware.md#deep-sleep-on-amdgpu). That fix is in mainline from 7.4. Until a distro kernel has it, every kernel update needs a rebuilt module, so the deciding factor was how soon the distro's kernel gets it:

| Distro | Kernel (2026-11-05) | When the fix arrives on its own |
| --- | --- | --- |
| Kubuntu 26.04 LTS, Linux Mint | Ubuntu 7.0.0-42 | Only if Ubuntu picks up the backport, or with a later HWE kernel, possibly most of 2027 |
| Fedora 45 KDE | 7.2.15, updated every few days | With a 7.2.y/7.3.y stable backport (not queued yet), or when Fedora moves to 7.4, probably early 2027 |

Checked for Fedora 45:

- `CONFIG_DRM_AMDGPU_SI=y`, so amdgpu can drive this GPU.
- `CONFIG_MODULE_SIG_FORCE` is not set, and the Mac has no Secure Boot, so an unsigned patched module loads (it taints the kernel, which is harmless).
- `CONFIG_INTEL_IOMMU_DEFAULT_ON` is not set, so the installer should show a picture without `intel_iommu=off`. It still goes on the command line after install.
- Modules are compressed as `.ko.xz`, not `.ko.zst`.
- Discover installs updates on restart, not silently, and Fedora keeps 3 kernels, so an older one is always in the boot menu.

## What carries over

| Fix | On Fedora |
| --- | --- |
| Kernel parameters | `grubby --update-kernel=ALL --args="..."`; new kernels keep them |
| Patched amdgpu module | [kernel/amdgpu-module/](https://github.com/mkucharek/mbp-2015-linux/tree/main/kernel/amdgpu-module) needs changes: `.ko.xz` instead of `.ko.zst`, `dracut` instead of `limine-update`, and the source from Fedora's kernel source package. The patch touches only `si.c` and applies to 7.0 through 7.2 |
| Kernel-update guard | the boot check and notification should work; the pacman hook becomes a `kernel-install` plugin in `/etc/kernel/install.d/` |
| Wi-Fi sleep hook | as is. If it fails, look for SELinux denials: `sudo ausearch -m avc -ts recent` |
| Bluetooth fix | as is |
| Camera | facetimehd with DKMS from source |
| Hibernate | skipped: Fedora sets up only zram swap, and a swap file on btrfs with SELinux takes extra work. Deep sleep at ~0.5 W lasts about 9 days |
| `brcmfmac feature_disable=0x82000` | Omarchy-only; NetworkManager with wpa_supplicant didn't need it on Mint |
| `hid_apple fnmode=2` | add by hand if F1–F12 should be function keys |
| Fans | no daemon |

## Before wiping Omarchy

- Copy off anything not in this repo: SMC/EC dumps from a good state (see [smc/](smc/smc-ec-dump.sh)), personal files.
- Optional, needs the patched module: the VCE resume test from [hardware.md](hardware.md#deep-sleep-on-amdgpu) (`amdgpu.ip_block_mask=0xff` for one boot, then several S3 cycles).
- Wiping the whole disk removes the local macOS Recovery. Internet Recovery (Cmd+Option+R) still works for the charger fix in hardware.md.

## Install

1. Fedora 45 KDE Plasma ISO (not 43, which reaches end of life on 2026-12-02), written to USB with Fedora Media Writer or `dd`.
2. Hold Option at power-on and pick "EFI Boot". Wi-Fi works in the live session.
3. If the screen goes black, add `intel_iommu=off` to the boot entry. If the installer freezes while writing to disk, add `nvme_core.default_ps_max_latency_us=0`. Edit with `e`, and boot with **F10** (or Fn+F10): Ctrl+X doesn't work on this keyboard.
4. Default btrfs layout. Disk encryption is optional (a password at every boot).
5. The child gets a standard user account; the parent keeps the admin one.

## First boot

```bash
# s2idle until the patched module is installed: deep sleep hangs on resume with stock amdgpu
sudo grubby --update-kernel=ALL --args="intel_iommu=off nvme_core.default_ps_max_latency_us=0 amdgpu.ip_block_mask=0x7f mem_sleep_default=s2idle"
sudo dnf upgrade --refresh
sudo grub2-editenv - unset menu_auto_hide     # show the GRUB menu, to pick an older kernel if needed
sudo reboot
cat /proc/cmdline
```

s2idle draws about 22 W, so it's only for short breaks until deep sleep works.

## Open items

- [ ] Adapt the module kit and the guard for Fedora, build the patched module, switch to `mem_sleep_default=deep`, test with `sudo rtcwake -m mem -s 20`
- [ ] Install the Wi-Fi sleep hook and run `bluetooth/bt-fix.sh`
- [ ] Steam (RPM Fusion or Flathub)
- [ ] Camera (optional)
- [ ] Take good SMC/EC dumps with `smc/smc-ec-dump.sh`
- [ ] Once Fedora's kernel has the amdgpu fix (`journalctl -k -b | grep 'VRAM: '` shows `0x000000F400000000` with the stock module), remove the patched module and the guard
- [ ] Optional: the VCE resume test with `amdgpu.ip_block_mask=0xff`
- [ ] Optional: build a kernel with the MTRR patch and send a Tested-by for it upstream
