# 2015 MacBook Pro (MacBookPro11,5) on Linux

| File | What's in it |
| --- | --- |
| [hardware.md](hardware.md) | **Start here.** Distro-agnostic: kernel parameters and why, radeon vs amdgpu, sleep/hibernate results with measured power, Bluetooth, camera, fans/SMC, troubleshooting |
| [omarchy.md](omarchy.md) | Current install: Limine/UKI config files, Omarchy-owned files, lid/logind, decisions, open items |
| [linux-mint.md](linux-mint.md) | Previous install: GRUB/initramfs-tools, recovery, Ubuntu MTRR kernel build, Cinnamon extras |
| [sleep-test.sh](sleep-test.sh) | Measures battery drain of s2idle / deep / awake (any systemd distro) |
| [bluetooth/bt-fix.sh](bluetooth/bt-fix.sh) | Fixes the Bluetooth chip hanging at boot (any systemd distro) |
| [kernel/](https://github.com/mkucharek/mbp-2015-linux/tree/main/kernel) | MTRR resume patch (fixes the slow wake from deep sleep) + Ubuntu kernel build script |
| [fans/](https://github.com/mkucharek/mbp-2015-linux/tree/main/fans) | Smoothed fan daemon: a fallback only, since the SMC's own fan control was fine on Omarchy |

**In short:** always use `intel_iommu=off` and `nvme_core.default_ps_max_latency_us=0`. Then choose:

- **radeon**, for real sleep (deep, 0.2 W) and no Vulkan
- **amdgpu** + `amdgpu.ip_block_mask=0x7f` + `mem_sleep_default=s2idle`, for Vulkan but only "sleep" at about 22 W

Apply `bluetooth/bt-fix.sh` either way.

## Licence

Scripts are MIT, the notes are CC BY 4.0, and `kernel/mtrr-resume.patch` is the original author's GPL-2.0 kernel code. See [LICENSE](LICENSE). Everything here is provided as-is: kernel parameters, MSR writes and kernel patches can leave a machine unbootable, so test with a fallback boot entry.
