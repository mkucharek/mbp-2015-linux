# 2015 MacBook Pro (MacBookPro11,5) on Linux

| File | What's in it |
| --- | --- |
| [hardware.md](hardware.md) | **Start here.** Distro-agnostic: kernel parameters and why, radeon vs amdgpu, sleep/hibernate results with measured power, Bluetooth, camera, fans/SMC, troubleshooting |
| [fedora.md](fedora.md) | Current install (from 2026-11): why Fedora KDE, what carries over, install and first-boot steps, notes, open items |
| [omarchy.md](omarchy.md) | Install until 2026-11: Limine/UKI config files, Omarchy-owned files, lid/logind, patched-module rebuilds, decisions |
| [linux-mint.md](linux-mint.md) | Previous install: GRUB/initramfs-tools, recovery, Ubuntu MTRR kernel build, Cinnamon extras |
| [sleep-test.sh](sleep-test.sh) | Measures battery drain of s2idle / deep / awake (any systemd distro) |
| [bluetooth/bt-fix.sh](bluetooth/bt-fix.sh) | Fixes the Bluetooth chip hanging at boot (any systemd distro) |
| [wifi/](https://github.com/mkucharek/mbp-2015-linux/tree/main/wifi) | Sleep hook that unloads Wi-Fi before deep sleep and hibernate (needed for hibernate); recovery script for when Wi-Fi dies anyway |
| [kernel/](https://github.com/mkucharek/mbp-2015-linux/tree/main/kernel) | amdgpu patch for deep sleep + module build/install scripts + a guard that falls back to s2idle and notifies you after a kernel update; MTRR resume patch (fixes the slow wake from deep sleep) + Ubuntu kernel build script |
| [smc/smc-ec-dump.sh](smc/smc-ec-dump.sh) | Dumps all SMC keys and the EC RAM, to compare good and bad states (charger power-on problem) |
| [fans/](https://github.com/mkucharek/mbp-2015-linux/tree/main/fans) | Smoothed fan daemon: a fallback only, since the SMC's own fan control was fine on Omarchy |

**In short:** always use `intel_iommu=off` and `nvme_core.default_ps_max_latency_us=0`. Then choose:

- **radeon**, for real sleep (deep, 0.2 W) and no Vulkan
- **amdgpu** + `amdgpu.ip_block_mask=0x7f` + `mem_sleep_default=s2idle`, for Vulkan but only "sleep" at about 22 W
- **amdgpu** + `amdgpu.ip_block_mask=0x7f` + the patched module from [kernel/amdgpu-si-reset-on-init.patch](kernel/amdgpu-si-reset-on-init.patch), for Vulkan and real sleep (deep, ~0.5 W). It needs a rebuild after each kernel update, until your kernel has the fix (mainline from 7.4).

Apply `bluetooth/bt-fix.sh` either way.

## Licence

Scripts are MIT, the notes are CC BY 4.0, and the kernel patches (`kernel/*.patch`) are GPL-2.0 kernel code. See [LICENSE](LICENSE). Everything here is provided as-is: kernel parameters, MSR writes and kernel patches can leave a machine unbootable, so test with a fallback boot entry.
