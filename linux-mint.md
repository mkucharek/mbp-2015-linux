# Linux Mint on the 2015 MacBook Pro

As of 2026-10-14 (install since replaced by Omarchy). Mint-specific setup only. The hardware findings are in [hardware.md](hardware.md). Everything worth keeping from the original Mint notes and scripts has been folded into this repo.

**Install:** Linux Mint 22.3 (Ubuntu 24.04 base), Cinnamon on Xorg + LightDM, kernel 7.0.0-38 (plus a self-built `7.0.0-38-mtrr`), GRUB.

**Decision:** radeon + deep (S3) sleep + the MTRR-patched kernel. That gave real sleep at 0.21 W with about 5 s wake, at the cost of Vulkan on the AMD GPU.

## Boot options

```bash
# /etc/default/grub
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=3
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash radeon.si_support=1 amdgpu.si_support=0 intel_iommu=off nvme_core.default_ps_max_latency_us=0"
sudo update-grub

# /etc/initramfs-tools/modules (appended): GPU drivers before LightDM, or Xorg starts on simpledrm and the screen goes black
i915
radeon
sudo update-initramfs -u -k all
```

- `/etc/X11/xorg.conf.d/` is empty; no custom X config.
- To switch drivers, change the `si_support` pair in `GRUB_CMDLINE_LINUX_DEFAULT` and the `radeon`/`amdgpu` line in `/etc/initramfs-tools/modules`, then run both update commands.

## Recovery

- **Recovery mode:** GRUB → Advanced options → recovery mode → resume. It boots with `nomodeset` (software rendering), so it always works, just slowly.
- **Editing a boot entry:** press `e`. **Ctrl+X doesn't work on this Mac's keyboard; boot with F10 (or Fn+F10).**
- **Text console:** Ctrl+Alt+F2 (maybe with Fn).
- **Things that didn't fix the white windows** (before `intel_iommu=off` was found): `AMD_DEBUG=notiling`, `DRI_PRIME=1 cinnamon`, an OutputClass `modesetting` driver, and reverse PRIME (Intel renders, AMD drives the panel), which gave a black screen when the AMD GPU got dropped.

## MTRR kernel (Ubuntu-specific build)

The scripts are in [kernel/](kernel/):

- `build-kernel-ubuntu.sh prepare|build`, then `sudo bash build-kernel-ubuntu.sh install|remove`
- `mtrr-resume.patch`, extracted from the LKML post

The script builds the running Ubuntu kernel's exact source and config plus the patch, named `<ver>-mtrr`, with Rust and debug info off, in `~/kernel-build`. It needs `libdw-dev` and `gawk`. Installing gawk forces a nearly full rebuild of about 2 h. Re-run it after every Ubuntu kernel update, until the patch is merged.

On another distro, apply `mtrr-resume.patch` to that distro's kernel package instead.

## Fans

mbpfan was installed early and made the fans loud. It was replaced by `mbp-fan-smooth` ([fans/](fans/): `sudo bash fan-smooth.sh` installs it, and it reverts to SMC automatic mode when stopped), which:

- smooths the temperature over 15 s
- runs the fans at minimum up to 70 °C, scaling linearly to maximum at 90 °C
- limits changes to +200/−100 rpm per second
- has a failsafe at 98 °C

On Omarchy no daemon was needed (see hardware.md).

## Desktop extras (Mint/Cinnamon only)

- **Trackpad:** `gsettings set org.cinnamon.desktop.peripherals.touchpad click-method 'fingers'` for two-finger right click; touchegg for gestures.
- **Camera viewer:** Cheese freezes through PipeWire. `~/.local/bin/cheese-v4l2` runs it with the PipeWire GStreamer plugin hidden, with matching desktop and D-Bus service overrides. guvcview works directly.
- **Toshy:** Mac-style Cmd shortcuts. Its unused cosmic/kwin/wlroots user services log harmless failures; mask them.
- **Timeshift:** rsync snapshots, daily ×5 + boot ×3, on the same SSD.
- **power-profiles-daemon:** on this Mac it only changes the CPU energy bias (EPB). It doesn't manage radeon.
- **Login keyring:** set its password to the login password in Seahorse so it unlocks at login.
- **Clipboard from scripts:** xclip/xsel weren't installed; use Python GTK.
- **Leftover open items:** `sudo ufw enable` (the firewall was off), masking Toshy's unused services, measuring power profiles.
