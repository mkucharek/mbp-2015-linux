# Linux on a 2015 MacBook Pro (MacBookPro11,5): Hardware Notes

As of 2026-10-14. This file covers everything that applies on any distro. Distro-specific setup is in [omarchy.md](omarchy.md) and [linux-mint.md](linux-mint.md). The findings come from two installs on this same Mac: Linux Mint 22.3 (kernel 7.0, radeon) and Omarchy (kernel 7.2.5, amdgpu).

Linux runs well on this Mac with four kernel parameters, a Bluetooth workaround, and one hard trade-off. On the AMD GPU, stock kernels give you **Vulkan (amdgpu) or real sleep (radeon), not both**. A small amdgpu patch, submitted upstream, gives both (see [Deep sleep on amdgpu](#deep-sleep-on-amdgpu)). The internal screen is wired to the AMD GPU, and that causes most of the quirks.

## Hardware

- **Board:** MacBookPro11,5 (15" mid-2015, dual GPU), Mac-06F11F11946D27C5, Apple UEFI 1.10 (no Secure Boot, no TPM2)
- **CPU / RAM:** Haswell i7, 4 cores / 8 threads, 16 GB
- **iGPU:** Intel Iris Pro (Crystal Well) `8086:0d26`, i915, 128 MB eDRAM
- **dGPU:** AMD Radeon R9 M370X "Venus XT" `1002:6821`, Southern Islands (SI / GFX6), supported by both radeon and amdgpu
- **Panel:** 2880×1800 eDP, routed through `apple_gmux` (4.0.20), which comes up on the AMD GPU at boot
- **SSD:** ADATA XPG SX8200 Pro (SX8200PNP, fw 32A1TCTB), aftermarket NVMe on an M.2 adapter
- **Wi-Fi:** Broadcom BCM43602 `14e4:43ba`, brcmfmac, works out of the box (see Wi-Fi for the deep-sleep and hibernate issues)
- **Bluetooth:** Apple BCM20703A1, USB `05ac:8290` on port `1-8`
- **Camera:** FaceTime HD `14e4:1570`, needs the out-of-tree `facetimehd` driver
- **Other:** Thunderbolt 2 (Falcon Ridge), keyboard/trackpad USB `05ac:0274` (bcm5974)
- **Battery:** ~103 Wh (bq20z451), 15 cycles

## Kernel parameters

Add these to whatever bootloader the distro uses:

| Parameter | Needed? | Why |
| --- | --- | --- |
| `intel_iommu=off` | **always** | With the Intel IOMMU (VT-d) on, radeon renders white or blank windows and amdgpu leaves the panel black. Nothing is logged; the corruption is silent. See [Launchpad bug 1971146](https://bugs.launchpad.net/ubuntu/+source/linux/+bug/1971146). Downside: no DMA protection against malicious Thunderbolt devices. Fallback if it ever recurs: `iommu=pt`. |
| `nvme_core.default_ps_max_latency_us=0` | for this SSD | Turns off NVMe low-power states (APST). The SX8200 Pro is known to freeze, drop off the bus, or go read-only in them, especially in Macs. Next step if problems persist: `pcie_aspm=off`. |
| `radeon.si_support=1 amdgpu.si_support=0` **or** `radeon.si_support=0 amdgpu.si_support=1` | always pick one | Chooses the driver for the SI GPU (see GPU). Since kernel 7.0 the default is amdgpu, so radeon has to be forced explicitly. |
| `amdgpu.ip_block_mask=0x7f` | amdgpu only | Turns off the UVD (video decode) and VCE (video encode) blocks, which can't resume from s2idle (see Sleep). |
| `mem_sleep_default=s2idle` | stock amdgpu only | Deep (S3) sleep hangs on stock amdgpu. On radeon, or on amdgpu with the patch from [Deep sleep on amdgpu](#deep-sleep-on-amdgpu), keep the default `deep`. |

Check with `cat /proc/cmdline` after rebooting.

**Load the GPU drivers in the initramfs** (`i915` + `radeon` or `amdgpu`). Otherwise the driver can load about 5 s into boot, after the display server has already started on the temporary boot framebuffer (simpledrm), and the screen goes black. This was seen on Mint with Xorg; how to add them is distro-specific.

## GPU

### How the GPUs are wired

- The AMD GPU always drives the internal panel, and it can't power down: the log says `Runtime PM not available`.
- The Intel iGPU finds no panel (`failed to retrieve link info, disabling eDP`), stays in D3hot, and does nothing.
- Card numbers (`card0` / `card1`) swap between radeon and amdgpu boots. Pin GPUs by `/dev/dri/by-path/`, never by card number.
- The kernel's EFI stub already sends Apple's `set_os` for this model, so the Intel GPU is visible. Switching the panel to Intel isn't supported on retina MacBooks, though ([kernel bug 215003](https://bugzilla.kernel.org/show_bug.cgi?id=215003)).

### radeon vs amdgpu

|  | radeon | amdgpu |
| --- | --- | --- |
| Vulkan on the AMD GPU | none: RADV refuses radeon (Intel's Haswell Vulkan works, at about half the speed) | RADV, so Steam/Proton/DXVK, Zed, wgpu, WebGPU |
| OpenGL, OpenCL | same (Mesa radeonsi) | same |
| VA-API video decode | worked on Mint/Xorg; failed on Omarchy/Wayland (`radeonsi_drv_video.so init failed`) | off because of `ip_block_mask` |
| Idle temperature / fans | baseline | about 3 °C warmer, about 600 rpm more fan. Memory clock pinned at 1125 MHz, no clock gating on SI; `power_dpm_force_performance_level=low` doesn't fix either |
| Awake idle draw | not measured | ~30 W |
| Deep sleep (S3) | works, 0.21 W | hangs on resume; works with the patch, ~0.46 W |
| s2idle | ~21 W; broke VCE and lost the panel EDID | ~22 W, works only with the mask |
| Hibernate | not tested | works with the patch, if Wi-Fi is unloaded first (see [Hibernate](#hibernate)) |
| Chromium (Omarchy, Wayland) | rendering artifacts with `intel_iommu=off` already set; only `--disable-gpu` fixed them. Unexplained. | fine |

### `amdgpu.ip_block_mask=0x7f`

amdgpu splits this GPU into 9 blocks, numbered 0–8 (list them with `journalctl -b -k | grep 'ip block'`). `0x7f` keeps blocks 0–6 and turns off block 7, `uvd_v3_1`, and block 8, `vce_v1_0`. Effect on use:

- **Gaming:** unaffected. Graphics, copy engine, power management and display stay on.
- **Video playback:** decoded on the CPU, which is fine on this quad-core i7.
- **OBS recording / Steam Remote Play:** encoding falls back to the CPU and costs FPS.

### Battery idea (untested, risky)

Boot with the Intel GPU driving the panel and the AMD GPU powered off:

1. `gpu-switch -i` ([0xbb/gpu-switch](https://github.com/0xbb/gpu-switch)) sets the EFI variable `gpu-power-prefs`, so the firmware muxes the panel to Intel.
2. `echo OFF > /sys/kernel/debug/vgaswitcheroo/switch` from a boot service.

This would fix idle heat and draw, and maybe sleep. You'd lose about half the 3D performance and probably external displays, which are likely wired to the AMD GPU. Recovery: boot recovery mode and run `gpu-switch -d`, or as a last resort reset NVRAM (Cmd+Option+P+R at power-on).

## Sleep & suspend

**Real sleep means deep (S3).** s2idle resumes on amdgpu once UVD/VCE are masked, but it isn't really sleep on this hardware, because Haswell Macs have no S0ix low-power idle. radeon handles deep sleep out of the box. Stock amdgpu hangs on resume from deep sleep, and a small patch fixes that (see [Deep sleep on amdgpu](#deep-sleep-on-amdgpu)).

| Driver | Mode | Result | Draw | Full battery lasts | Failure in the log |
| --- | --- | --- | --- | --- | --- |
| radeon | deep (S3) | works | 0.21 W | ~20 days | none |
| radeon | s2idle | resumes, but broken | 21.3 W | ~5 h | `failed VCE resume (-22)`, `failed testing IB on ring 5/6/7`, `radeon_dp_link_train_cr: clock recovery failed`, then EDID lost (Xorg/Cinnamon dropped to 1× scale) |
| amdgpu | deep (S3) | hangs | n/a | n/a | `ring gfx test failed (-110)`, `resume of IP block <gfx_v6_0> failed -110`, `ring sdma0 timeout`; the mask doesn't help |
| amdgpu + mask + patch | deep (S3) | **works** | ~0.46 W | ~9 days | none; 1.40 W over the whole 10 min window, which includes ~22 s awake (mostly the slow resume) |
| amdgpu | s2idle | hangs | n/a | n/a | `UVD Firmware validate fail (-22)`, `resume of IP block <uvd_v3_1> failed`, then endless `Fence fallback timer expired on ring sdma0` |
| amdgpu + mask | s2idle | **works** | ~22 W | ~5 h | none; resume 0.4 s |
| amdgpu + mask | hibernate | dark screen after the LUKS prompt | n/a | n/a | nothing logged; the restored kernel hangs before journald writes. Wi-Fi was loaded, so the cause is unclear |
| amdgpu + mask + patch | hibernate | hangs with Wi-Fi loaded; **works** with the brcmfmac sleep hook | off | n/a | none; amdgpu restore takes ~1.2 s |

All measured on battery with the lid open, for 10 minutes, using [sleep-test.sh](sleep-test.sh). The script measures the awake draw just before sleeping and subtracts the seconds spent awake inside the window. The patched-amdgpu figure is that corrected value. The older radeon and s2idle rows were measured before this correction, but they're barely affected: radeon on Mint had the MTRR patch (fast resume), and s2idle draw is close to the awake draw anyway. For comparison, the awake idle draw on amdgpu is about 30 W.

### Deep sleep on amdgpu

**Symptom:** with stock amdgpu, every resume from deep sleep (S3) fails, and so does a GPU reset. The screen stays black, and the log shows `ring gfx test failed (-110)` and `resume of IP block <gfx_v6_0> failed -110`. The system itself stays up. The same failure is reported on stock Arch 7.2.9 in [drm/amd #5978](https://gitlab.freedesktop.org/drm/amd/-/issues/5978).

**Cause** (verified with register dumps on this Mac):

- With the Intel GPU enabled, Apple's firmware puts the AMD GPU's VRAM at MC address 0 (`MC_VM_FB_LOCATION=0x007f0000`). The kernel's EFI stub enables the Intel GPU on this model through Apple's `set_os` call, and there is no boot option to skip it.
- amdgpu reads this layout once at load and places everything relative to it, for example the GART page table at 0x1400000.
- S3 powers the GPU off, so on resume amdgpu runs the VBIOS init again. That moves VRAM to the VBIOS default (`MC_VM_FB_LOCATION=0xf47ff400`, VRAM at 0xF4_0000_0000).
- amdgpu never writes this register back, so the GART table is no longer in VRAM, and the first GPU command times out. radeon writes the register on every start, which is why radeon resumes fine.

**Fix:** [kernel/amdgpu-si-reset-on-init.patch](kernel/amdgpu-si-reset-on-init.patch) makes amdgpu reset and initialise the GPU itself at load, on Apple boards with VRAM at 0. amdgpu then uses the VBIOS layout from the start, and later re-inits keep it. The boot log shows `PCI CONFIG reset`, `GPU posting now...` and `VRAM: 2048M 0x000000F400000000`. This is the same approach that the kernel already uses for the 2017 and 2018 MacBook Pros with Polaris GPUs.

- Tested on 7.2.5: the panel comes up at boot, every S3 resume works (4 of 4 test cycles and a 5-minute lid-close), and Wi-Fi comes back after about 4 s. The GPU reset path is not tested.
- Submitted upstream to amd-gfx on 2026-10-14 ([drm/amd #5978](https://gitlab.freedesktop.org/drm/amd/-/issues/5978)). On 2026-10-15, [v2](https://lore.kernel.org/amd-gfx/20261015095713.20560-1-qchcio@gmail.com/T/) added the same check for the CIK and VI GPU families, as the amdgpu maintainer asked. Until it reaches a release kernel, build amdgpu with the patch yourself: [kernel/amdgpu-module/](https://github.com/mkucharek/mbp-2015-linux/tree/main/kernel/amdgpu-module) builds and installs only the module (steps for Omarchy are in [omarchy.md](omarchy.md)).
- A patched module only works with the kernel version it was built for. After a kernel update, the distro's stock module is back until you rebuild, so switch to s2idle before updating. On Arch-based distros, [kernel/amdgpu-module/guard/](https://github.com/mkucharek/mbp-2015-linux/tree/main/kernel/amdgpu-module/guard) does that automatically for the first boot on the new kernel and shows a notification.

**Slow wake from S3 (MTRR bug).** The patch and an Ubuntu build script are in [kernel/](https://github.com/mkucharek/mbp-2015-linux/tree/main/kernel). Apple firmware changes the CPU cache settings (MTRRs) during S3 on half the cores, and those cores run extremely slowly until the kernel restores them. "Enabling non-boot CPUs" takes 0.7–5 s per CPU, about 15–23 s in total. CPU 4, the boot core's hyperthread sibling, comes back fast. The fix is an unmerged patch written for exactly this Mac: [x86/mtrr: Expedite cache init if MTRRs change on resume](https://lkml.iu.edu/hypermail/linux/kernel/2602.0/05829.html) (Chris Paulson-Ellis, Feb 2026). On Mint it cut kernel resume from 15 s to about 5 s, and dmesg then shows `mtrr: your CPUs had unexpected MTRR settings on resume`. Check whether it has been merged before building it.

**Lid open:** sleeping with the lid open wakes the Mac after about 2 s, because the lid sensor (`LID0` in `/proc/acpi/wakeup`) is a wake source. That's harmless in normal use.

**Runtime vs persistent:** `echo s2idle | sudo tee /sys/power/mem_sleep` only lasts until reboot. After adding `mem_sleep_default` to the kernel command line, the running boot keeps the old mode until you reboot.

**Measuring power:** use the charge drawn (µAh) × the average voltage. Charge × voltage at each end overstates it: the voltage sags about 0.7 V right after unplugging, which once produced a fake 54 W "awake" reading. For a live reading, multiply `current_now` by `voltage_now` in `/sys/class/power_supply/BAT0`.

## Hibernate

Hibernate works on amdgpu with the patch from [Deep sleep on amdgpu](#deep-sleep-on-amdgpu), as long as the Wi-Fi driver is unloaded before hibernating. Untested on radeon. Tested on 7.2.5 with LUKS + a btrfs swap file:

- **amdgpu:** restores in about 1.2 s with the patch. When hibernating, amdgpu resets the GPU (`PCI CONFIG reset`), and the patched module keeps VRAM at the same place through the reset and the restore. A forced reset while running (`cat /sys/kernel/debug/dri/<n>/amdgpu_gpu_recover`) also works, but the GPU loses VRAM, and Hyprland crashes and restarts in safe mode.
- **Wi-Fi (brcmfmac):** with the driver loaded, the restored system hung on all 4 tries, on a black or frozen lock screen, with no keyboard response and nothing in the log. With the driver unloaded before hibernating, the restore works, Thunderbolt included. The fix is the same sleep hook that handles Wi-Fi after deep sleep (see [Wi-Fi](#wi-fi)). Wi-Fi reconnects about 5 s after the restore.
- **CPUs** come back right away; the slow MTRR wake from S3 doesn't happen here.

**Testing tips:**

- `echo test_resume > /sys/power/disk` hangs on amdgpu even when real hibernate works, so it's not a useful test. The likely reason: amdgpu's freeze callback runs twice on an already suspended GPU in that mode.
- `echo devices > /sys/power/pm_test`, then `echo disk > /sys/power/state`, runs every driver's hibernate freeze, waits 5 s and resumes. No image is written and nothing powers off.
- A hang on restore leaves nothing in the journal. To find the driver, unload suspects (`modprobe -r`) before hibernating and add them back one at a time. After a hang, the next boot is a normal cold boot, because the kernel clears the image signature as soon as it starts reading the image.

**suspend-then-hibernate** works: deep sleep first, then after `HibernateDelaySec` the Mac wakes itself with an RTC alarm and hibernates. Tested with a 2-minute delay on lid close; Wi-Fi was back about 5 s after the restore.

The Wi-Fi hook runs three times in one cycle: `pre suspend-then-hibernate` before the deep sleep, `post suspend-then-hibernate` after the timed wake, and `pre hibernate` about 0.2 s later. A hook that only runs `modprobe brcmfmac` in `post` breaks here: the unload in `pre hibernate` fails with `Module brcmfmac is in use` while the firmware is still loading, the system hibernates with the chip half set up, and after the restore the log shows `brcmf_fwvid_request_module: mod=wcc: failed -16` and `Firmware has halted or crashed`. Wi-Fi stays dead until a reboot. That's why [wifi/brcmfmac-sleep](wifi/brcmfmac-sleep) waits for the interface after loading and retries the unload.

```ini
# /etc/systemd/sleep.conf.d/suspend-then-hibernate.conf
[Sleep]
HibernateDelaySec=2h

# /etc/systemd/logind.conf.d/30-lid-suspend-then-hibernate.conf
[Login]
HandleLidSwitch=suspend-then-hibernate
```

Apply the logind change with `sudo systemctl kill -s HUP systemd-logind`, which reloads logind without ending the session. To test, set `HibernateDelaySec=2min` first and close the lid for about 3 minutes.

## Bluetooth

The Apple BCM20703 chip misses its reset on about 2 of 5 boots, warm reboots included. It was seen on both distros. The log shows `hci0: command 0x0c03 tx timeout` and `BCM: Reset failed (-110)`, and there's no controller; `usb 1-8: Failed to suspend device, error -110` shows that USB autosuspend of the chip fails. Reloading `btusb` doesn't help, because the chip itself is hung. A suspend/resume, or a full shutdown and power-on, brings it back.

The fix is [bluetooth/bt-fix.sh](bluetooth/bt-fix.sh). It needs systemd and Python 3 (`sudo bash bt-fix.sh`, undo with `undo`), and installs:

- `/etc/modprobe.d/btusb-no-autosuspend.conf`: `options btusb enable_autosuspend=0`. This alone isn't enough: the USB core still suspends the device after 2 s idle.
- `/etc/udev/rules.d/50-apple-bt-no-autosuspend.rules`: sets `power/control=on` for `05ac:8290`.
- `bt-check.service`: if there's no controller at boot, it resets the chip on the USB bus with a `USBDEVFS_RESET` ioctl and reloads `btusb`, up to 3 times. Check with `journalctl -u bt-check -b`.

`usbcore.autosuspend=-1` set through `/etc/modprobe.d` does nothing when usbcore is built into the kernel, which it usually is. It would have to go on the kernel command line, and `btusb` turns autosuspend back on for its device anyway.

After recovery the radio may be soft-blocked: `rfkill unblock bluetooth`. The first scan can be slow. One untested theory is that 2.4 GHz Wi-Fi on channel 1 shares the antenna.

## Wi-Fi

Wi-Fi works out of the box with brcmfmac and firmware 7.35.177.61. It warns `no clm_blob available`, which may limit the available channels. Omarchy's Apple installer step adds `options brcmfmac feature_disable=0x82000` (`/etc/modprobe.d/brcmfmac.conf`), because Broadcom's in-firmware supplicant fails the WPA handshake on Apple hardware; Mint ran fine without it.

**After deep sleep (S3) the chip sometimes doesn't come back.** S3 cuts the chip's power, which s2idle doesn't. Usually Wi-Fi reconnects about 2–3 s after resume. Sometimes, though, the firmware stops answering: right after resume dmesg shows `brcmf_msgbuf_query_dcmd: Timeout on response for query command`, then endless `-5` and later `-12` errors (`Failed to reserve space in commonring`, `scan error`), and there are no networks until a reboot. On Omarchy it happened on 1 of 2 S3 cycles, and the second cycle was fine.

**Recovery:** [wifi/wifi-reload.sh](wifi/wifi-reload.sh) (`sudo bash wifi-reload.sh`). It reloads the driver, which reloads the chip's firmware, and if no interface appears it also removes and rescans the PCI device. A plain `modprobe -r brcmfmac` fails, because the vendor module `brcmfmac_wcc` holds a reference to it, so remove `brcmfmac_wcc` first.

**Hibernate hangs on restore when brcmfmac is loaded** (see [Hibernate](#hibernate)).

**Fix for both:** [wifi/brcmfmac-sleep](wifi/brcmfmac-sleep), a systemd sleep hook that unloads the driver before deep sleep or hibernate and loads it again after resume, so the chip starts with fresh firmware instead of resuming. s2idle keeps the chip powered, so the hook skips it. Install with `sudo install -Dm755 wifi/brcmfmac-sleep /usr/lib/systemd/system-sleep/brcmfmac`.

`rtcwake` writes straight to `/sys/power/state` and skips systemd's sleep hooks. To test the hook, set an RTC alarm and suspend through systemd: `echo +30 | sudo tee /sys/class/rtc/rtc0/wakealarm && systemctl suspend`.

## Camera (FaceTime HD)

Use the [patjak/facetimehd](https://github.com/patjak/facetimehd) driver through DKMS, plus the firmware from [patjak/facetimehd-firmware](https://github.com/patjak/facetimehd-firmware), which extracts it from Apple's Boot Camp package. On Arch use the AUR packages `facetimehd-dkms` and `facetimehd-firmware`; elsewhere, build it with DKMS from source (commit `c9b063a3c0`, version 0.7.0.1, worked with kernel 7.0). Blacklist `bdc_pci` (`/etc/modprobe.d/facetimehd.conf`). When it's healthy, dmesg shows `facetimehd ... loaded set file facetimehd/1871_01XX.dat`, and `/dev/video0` gives 1280×720 at 30 fps. Apps that read the camera through PipeWire (Cheese, possibly browsers and OBS) can fail with `can't negotiate buffers`. Apps that use v4l2 directly (guvcview, `gst-launch-1.0 v4l2src`) work.

## Fans and thermals

- **Fans:** the Mac's own fan controller (SMC automatic mode, `fan*_manual=0`) behaves well on a clean install, at about 3400/3200 rpm at 67 °C on Omarchy. On Mint, mbpfan made the fans jump to full speed on every turbo burst (Haswell goes from 74 to 100 °C in about 1 s), and SMC automatic mode seemed broken afterwards. The likely cause is installing mbpfan too early. **Don't install a fan daemon unless the fans actually misbehave.** If one is needed, the smoothed daemon in [fans/](https://github.com/mkucharek/mbp-2015-linux/tree/main/fans) works better than mbpfan.
- **CPU stuck at 800 MHz:** the SMC can hold the CPU's PROCHOT throttle line and never release it. The charger (85 W) wasn't the cause. Check with `grep MHz /proc/cpuinfo` under load, then `sudo modprobe msr; sudo rdmsr -p0 0x690`: bit 0 set means it's limiting now. The temporary fix is `sudo wrmsr -a 0x1FC 0x4005e`, which makes the CPU ignore the external PROCHOT signal. The CPU's own 100 °C throttle and THERMTRIP shutdown still protect it. Undo with `0x4005f`, and do undo it on battery for long heavy jobs.
- **SMC reset**, which is firmware-level and survives reinstalls: shut down with the charger in, hold left Shift+Ctrl+Option+Power for 10 s, release, then power on. Done on 2026-10-14. It cleared the 800 MHz problem. It neither causes nor fixes the power-on-with-charger problem below.
- **Mac powers on by itself when the charger is plugged in** (from shutdown or hibernation). It boots at the moment the MagSafe LED turns from green to orange, when the SMC starts charging. With a nearly full battery, the SMC may not start charging, so nothing happens. Test with the battery around 80–85%. It happens even after a firmware-only power-off (boot picker, hold Power), so Linux doesn't cause it. The SMC `AUPO` key reads `00`, the EC wake bits are clear, and nothing in NVRAM controls it. What turns it on is not known yet. Neither an SMC reset nor a forced power-off at the boot picker does; a forced power-off while Linux hangs (as in the early hibernate tests) is untested. A normal Linux power-off doesn't clear it, but one shutdown from macOS does: power on with Cmd+R and choose Apple menu → Shut Down. After that, Linux power-offs stayed off when the charger was plugged in (tested 2026-10-15).
- **NVRAM `auto-boot`** (Apple EFI variable): leave it at `true`. Setting it to `false` can stop normal booting on these Macs.

## Other

- **Keyboard:** `options hid_apple fnmode=2` makes F1–F12 act as function keys; hold Fn for media keys.
- **NVMe:** every suspend logs `Refused to change power state from D1 to D3hot`. No effect has been seen.
- **Trackpad:** `bcm5974: Touch jump detected and discarded` is harmless log noise.
- **Software rendering:** don't test with `LIBGL_ALWAYS_SOFTWARE=1` at 2880×1800. It hung the whole machine.

## Testing & troubleshooting

Test every sleep change with a timed self-wake before trusting the lid:

```bash
sudo rtcwake -m mem -s 20                                                      # whatever mem_sleep selects
echo s2idle | sudo tee /sys/power/mem_sleep && sudo rtcwake -m freeze -s 20   # force s2idle, this boot only
sudo bash sleep-test.sh s2idle 10                                              # power draw, on battery
sudo bash sleep-test.sh awake 10                                               # baseline
```

After a hang and a hard reset:

```bash
journalctl --list-boots | tail -5
journalctl -b -1 -k | grep -Ei 'PM: suspend|Waking|radeon|amdgpu.*(ERROR|fail|timeout)|gmux'
journalctl -b -1 -k | grep 'ip block'          # amdgpu block numbers + which are disabled
journalctl -b 0 -k | grep 'PM: Image'          # 'Image not found' after a hibernate = image was consumed
cat /proc/cmdline
lspci -k -s 01:00.0 | grep 'in use'            # radeon or amdgpu
```

Error codes: `-110` is a timeout (the hardware didn't respond), and `-22` is an invalid argument (here, a firmware check failing).
