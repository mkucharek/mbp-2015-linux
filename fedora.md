# Fedora KDE on the 2015 MacBook Pro

Installed on 2026-11-05 (Fedora 45 KDE, kernel 7.2.15). Deep sleep works with the patched amdgpu module, the Wi-Fi sleep hook and the guard. Fedora-specific setup only; the hardware findings, kernel parameter reasons and sleep results are in [hardware.md](hardware.md).

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
| Patched amdgpu module | [kernel/amdgpu-module/](https://github.com/mkucharek/mbp-2015-linux/tree/main/kernel/amdgpu-module) with `build-fedora.sh`, see [Patched amdgpu module](#patched-amdgpu-module). The patch touches only `si.c` and applies to 7.0 through 7.2 |
| Kernel-update guard | works; on Fedora it installs a `kernel-install` plugin instead of the pacman hook, and checks the module's taint flags instead of `srcversion` |
| Wi-Fi | works, but not with WPA3: switch saved WPA3 profiles to WPA2 (see [Notes](#notes-from-the-install)) |
| Wi-Fi sleep hook | works as is |
| Bluetooth fix | works as is, with SELinux enforcing (tested) |
| Camera | facetimehd with DKMS from source |
| Hibernate | skipped: Fedora sets up only zram swap, and a swap file on btrfs with SELinux takes extra work. Deep sleep at ~0.5 W lasts about 9 days |
| `brcmfmac feature_disable=0x82000` | not needed: NetworkManager with wpa_supplicant connects without it, as on Mint |
| `hid_apple fnmode=2` | set (see [Apps, codecs and parental controls](#apps-codecs-and-parental-controls)) |
| Fans | no daemon |

## Before wiping Omarchy

- Copy off anything not in this repo: SMC/EC dumps from a good state (see [smc/](smc/smc-ec-dump.sh)), personal files.
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
sudo reboot
cat /proc/cmdline
sudo bash bluetooth/bt-fix.sh
```

s2idle draws about 22 W, so it's only for short breaks until deep sleep works.

The GRUB menu stays hidden, as Fedora sets it up, so the child doesn't see it. To boot an older kernel: press Esc repeatedly right after the chime, or force a power-off during a failed boot (the menu then shows on the next start, because Fedora only marks a boot as good after about 2 minutes logged in), or `sudo grubby --set-default /boot/vmlinuz-<version>`. `sudo grub2-editenv - unset menu_auto_hide` shows it at every boot.

## Patched amdgpu module

The patch and the reason for it are in [hardware.md](hardware.md#deep-sleep-on-amdgpu). [kernel/amdgpu-module/build-fedora.sh](kernel/amdgpu-module/build-fedora.sh) downloads Fedora's kernel source package for the kernel (`dnf download --source`, about 160 MB), unpacks the kernel.org tarball, applies Fedora's `patch-<x.y>-redhat.patch` as the kernel.spec does, then the fix, and builds only `amdgpu.ko`. It compresses it as `.ko.xz` with the kernel's own settings (CRC32, 1 MiB dictionary). The source tree stays in `~/src/fedora-kernel/linux-<version>` (about 1.8 GB, plus the build); older trees can be deleted. Fedora's patch doesn't touch amdgpu, so the module source is the kernel.org one.

Fedora doesn't put amdgpu in the initramfs on this Mac (`lsinitrd | grep amdgpu` is empty), so it loads from `/usr/lib/modules/<version>/updates/`. `install.sh` rebuilds the initramfs with dracut anyway, in case that changes.

Once, as the admin user:

```bash
sudo dnf install kernel-devel-$(uname -r) gcc make flex bison elfutils-libelf-devel openssl-devel dwarves
bash kernel/amdgpu-module/build-fedora.sh       # ~7 min
sudo bash kernel/amdgpu-module/install.sh
sudo reboot
journalctl -k -b | grep -E 'PCI CONFIG reset|GPU posting|VRAM:'   # must show VRAM at 0x000000F400000000
sudo install -Dm755 wifi/brcmfmac-sleep /usr/lib/systemd/system-sleep/brcmfmac
sudo bash kernel/amdgpu-module/guard/install.sh
sudo grubby --update-kernel=ALL --remove-args=mem_sleep_default=s2idle --args=mem_sleep_default=deep
sudo reboot
cat /sys/power/mem_sleep                         # s2idle [deep]
echo +30 | sudo tee /sys/class/rtc/rtc0/wakealarm && systemctl suspend   # wakes after 30 s; Wi-Fi back in a few s
```

Tested on 7.2.15-300.fc45: the build takes about 6 minutes, the module resets the GPU at load (VRAM at `0x000000F400000000`), and an S3 cycle through `systemctl suspend` works, with Wi-Fi reconnected about 5 s after resume.

The guard tells the modules apart differently than on Arch: Fedora builds without `CONFIG_MODULE_SRCVERSION_ALL`, so neither module has a `srcversion`. The patched one shows `O` (out-of-tree) in `/sys/module/amdgpu/taint`, and the stock one doesn't.

`kernel-devel` is an install-only package like `kernel`, so once installed, `dnf upgrade` brings the matching one with each new kernel.

**Kernel updates.** The module only matches the kernel it was built for. Two ways:

- **With `sudo dnf upgrade` (best):** the guard's `kernel-install` plugin prints a warning naming the new kernel. Build for it before rebooting, and deep sleep never goes away:
  ```bash
  KVER=<new version> bash kernel/amdgpu-module/build-fedora.sh
  sudo KVER=<new version> bash kernel/amdgpu-module/install.sh
  sudo reboot
  ```
- **With Discover** (installs on restart, no warning shown): the first boot on the new kernel has the stock module. The guard switches that boot to s2idle, masks hibernate and shows a critical notification. Run `build-fedora.sh` and `install.sh` without `KVER` and reboot.

**Once Fedora's kernel has the fix** (7.4, or a 7.2.y/7.3.y stable backport): after the update the guard's notification shows up as usual. Check `journalctl -k -b | grep 'VRAM: '`: with the stock module, `0x000000F400000000` means the fix is in. Then `sudo bash kernel/amdgpu-module/install.sh remove` and `sudo bash kernel/amdgpu-module/guard/install.sh remove`, reboot, and delete `~/src/fedora-kernel`.

## Snapshots

[backup/snapper-fedora.sh](backup/snapper-fedora.sh) (`sudo bash backup/snapper-fedora.sh`) sets up snapper, roughly what Omarchy does, without the boot menu entries:

- **System (`/`, subvolume `root`):** a pre/post snapshot pair around every package transaction, from `dnf` and from Discover, through the libdnf5 actions plugin (`/etc/dnf/libdnf5-plugins/actions.d/snapper.actions`). PackageKit's backend uses libdnf5 and loads its plugins, so Discover gets snapshots too: tested on 2026-11-05, installing an app from Discover created a pair described `Discover/PackageKit`. Updates installed on restart go through the same backend, but aren't confirmed yet. Plus one snapshot a day. Keeps 10 update pairs and 7 days.
- **Home (`/home`, subvolume `home`):** hourly; keeps 24 hourly, 7 daily and 2 weekly snapshots. A deleted file stays in the snapshots until they expire, so uninstalling a large game frees its space only after 2 weeks.
- When the configs are created, SELinux logs a few `denied { reload } ... scontext=snapperd_t tcontext=init_t` messages. The configs and timers work anyway.
- `btrfs-assistant` is the GUI (Snapper tab). The admin user can list snapshots and open them without sudo; the other accounts' files keep their own permissions.
- Not covered: `/boot` (ext4, so kernels aren't rolled back with the system), and a dead or lost disk: snapshots are on the same SSD. For that, back up `/home` to another disk (Déjà Dup or Vorta are in Fedora's repos).

Grub-btrfs, which adds snapshot entries to the boot menu, isn't in Fedora's repositories and doesn't fit Fedora's BLS boot entries well, so a broken boot is handled by an older kernel first, and the live USB second.

**Restoring**

The system and `/home` are separate subvolumes, so rolling back the system never touches personal files or game saves.

- **A file in `/home`:** btrfs-assistant → Snapper → Browse/Restore. Or open `/home/.snapshots/<number>/snapshot/<user>/…` in the file manager (read-only) and copy the file out.
- **An update broke something, the Mac still boots:** btrfs-assistant → Snapper → pick the `pre` snapshot from before the update → Restore, then reboot. Or undo just that transaction's changes:
  ```bash
  snapper -c root list                      # find the pre/post pair, e.g. 42 and 43
  sudo snapper -c root undochange 42..43
  sudo reboot
  ```
- **It doesn't boot:** first pick an older kernel (Esc at boot): most broken boots are a kernel. If nothing boots, start the live USB, and in a terminal:
  ```bash
  sudo mount /dev/nvme0n1p3 /mnt                       # the btrfs top level: root, home
  ls /mnt/root/.snapshots/; cat /mnt/root/.snapshots/42/info.xml   # find the snapshot to go back to
  sudo mv /mnt/root /mnt/root.broken
  sudo btrfs subvolume snapshot /mnt/root.broken/.snapshots/42/snapshot /mnt/root
  # .snapshots is its own subvolume, so it isn't inside the snapshot: move it over
  sudo rmdir /mnt/root/.snapshots && sudo mv /mnt/root.broken/.snapshots /mnt/root/
  sudo umount /mnt && sudo reboot
  ```
  Once everything works, delete the old one: `sudo mount /dev/nvme0n1p3 /mnt && sudo btrfs subvolume delete /mnt/root.broken`.
- **After rolling back past a kernel update**, the newest kernel in the boot menu has no modules in the restored system and won't boot. Pick the previous one; the next `dnf upgrade` installs it again. The patched amdgpu module lives in the system, so it's rolled back together with the kernel modules.

## Apps, codecs and parental controls

Set up on 2026-11-06, as the admin user:

```bash
# Flathub, for most apps in Discover (only Fedora's own remote is there by default)
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# Full ffmpeg from RPM Fusion (H.264/HEVC and more), and VA-API drivers with those codecs
sudo dnf swap ffmpeg-free ffmpeg --allowerasing
sudo dnf install mesa-va-drivers-freeworld mesa-va-drivers-freeworld.i686

# Steam from RPM Fusion nonfree; gamemode for both 64- and 32-bit games
sudo dnf install steam gamemode.x86_64 gamemode.i686

# F1–F12 as function keys, Fn+F-key for brightness/volume/media
echo 'options hid_apple fnmode=2' | sudo tee /etc/modprobe.d/hid_apple.conf
echo 2 | sudo tee /sys/module/hid_apple/parameters/fnmode    # now, without a reboot
```

- **gamemode:** `dnf install steam gamemode gamemode.i686` installed only the i686 package, so name the arches. Use per game with the Steam launch option `gamemoderun %command%`; worth it only for a game that stutters.
- **Steam on Vulkan:** RADV sees the R9 M370X (`RADV VERDE`), and the Intel GPU (hasvk) shows up as a second Vulkan device. On a game's first launch, check it runs on the AMD GPU (e.g. with MangoHud).
- **No hardware video decoding.** `vainfo` fails on both GPUs: on the AMD one because `amdgpu.ip_block_mask=0x7f` turns UVD off (`radeonsi_drv_video.so init failed`), and on the Intel one because libva picks `iHD`, which is for Broadwell and newer. Haswell would need `libva-intel-driver` (i965, RPM Fusion), plus pointing apps at `/dev/dri/renderD129`. Video plays fine with CPU decoding, so it's left as is for now. Options and a test plan, including YouTube: [hardware.md](hardware.md#hardware-video-decoding-not-set-up-yet). The freeworld VA drivers start to matter if the mask goes away.

**Parental controls (malcontent)** for the child's account (PEGI 7; `<child>` below is its username):

```bash
sudo dnf install malcontent malcontent-tools malcontent-control
sudo malcontent-client set-app-filter -n \
    --disallow-user-installation --disallow-system-installation \
    <child> \
    violence-cartoon=intense violence-fantasy=moderate violence-realistic=mild \
    violence-bloodshed=none violence-sexual=none \
    drugs-alcohol=none drugs-narcotics=none drugs-tobacco=none \
    sex-nudity=none sex-themes=none \
    language-profanity=none language-humor=mild language-discrimination=none \
    money-advertising=mild money-gambling=mild money-purchasing=none \
    social-chat=mild social-audio=none social-contacts=none social-info=mild social-location=none \
    sex-homosexuality=none sex-prostitution=none sex-adultery=none sex-appearance=none \
    violence-worship=none violence-desecration=none violence-slavery=none
malcontent-client get-app-filter <child>
```

- The OARS values are what AppStream gives for age 7 (`AppStream.ContentRating.attribute_to_csm_age`), the same as picking PEGI 7 in the Parental Controls app (`malcontent-control`). The app is the easier way to change it later, e.g. to raise the age limit.
- In practice: no apps installed from the child's account, nothing above PEGI 7, no in-app purchases (`money-purchasing=none`), no voice chat apps (`social-audio=none`), moderated text chat only.
- New apps go in from the admin account; system-wide Flatpaks show up in the child's account too.
- Limits of malcontent on KDE: it only filters Flatpak installs. Apps already installed aren't hidden (only GNOME Shell does that), and Steam games aren't covered: use Steam Family for those. malcontent 0.14 also has a web filter (`set-web-filter`), not set up.

**Web filtering.** The home network uses Cloudflare for Families (1.1.1.3) through the router (10.0.4.1). Checked on 2026-11-06: adult domains resolve to `0.0.0.0`, and Google and Bing are forced to SafeSearch (`forcesafesearch.google.com`, `strict.bing.com`), the same answers 1.1.1.3 gives. Gaps found:

- **DNS over HTTPS skips it.** Queries to Cloudflare's and Google's public DoH resolvers return real addresses. Firefox can switch to DoH from its settings. Its canary check doesn't catch this network (`use-application-dns.net` resolves).
- **YouTube isn't restricted.** Cloudflare for Families leaves it alone.
- **Plain DNS to another server** (e.g. `dig @8.8.8.8`) also isn't filtered. On this laptop that needs software the child can't install, or a change to the system Wi-Fi profile, which needs the admin password. Blocking outbound 53/853 except to the router would cover every device on the network, but not DoH.

[family/web-filter.sh](family/web-filter.sh) closes the first two on this laptop: a Firefox policy (`/etc/firefox/policies/policies.json`) that turns DoH off and locks it, and `/etc/hosts` entries that send the YouTube domains to `restrict.youtube.com`. That forces Restricted Mode for every account on the laptop, the admin one too.

The same policy force-installs **uBlock Origin** in every Firefox profile, private windows included. Nobody can remove or disable it from Firefox, though the toolbar popup can still turn it off for one site. Its filter lists are set through the policy (`3rdparty` → `toOverwrite.filterLists`, reapplied at each Firefox start): uBO's defaults, plus lists recommended at https://majkiit.github.io/polish-ads-filter/:

- Oficjalne Polskie Filtry (built into uBO as `POL-0`): Polish ads
- CERT.PL's warning list (`POL-3`) and KAD - STOP Przekrętom: scam, phishing and fake-shop domains
- Cookie banners: EasyList/uBO Cookie Notices (the page's advice for uBO) and Polskie Filtry RODO-Ciasteczkowe

Left out to keep breakage low: the Polish social-widget and annoyance lists. Add their URLs to `filterLists` if wanted.

```bash
sudo bash family/web-filter.sh            # strict; "moderate" for the milder level, "remove" to undo
```

Restart Firefox, then check `about:policies` and https://www.youtube.com/check_content_restrictions.

DNS filtering works on whole domains only: chat inside games and comments on allowed sites aren't covered.

## Notes from the install

- **Wi-Fi didn't connect to a WPA2/WPA3 network.** The saved profile was WPA3-only (`key-mgmt=sae`), which the BCM43602 firmware can't do; details in [hardware.md](hardware.md#wi-fi). Fixed with `nmcli con modify <name> wifi-sec.key-mgmt wpa-psk`.
- **Bluetooth hung on the first boot after the update** (`Reset failed (-110)`), as it does at random on this chip. `bt-fix.sh` brought it back, and its boot check handles it from then on.
- **7.2.15 logs `amdgpu: [drm] *ERROR* Unsupported screen format RA24 little-endian (0x34324152)`** about 590 times right after boot; 7.2.11 logged none. The screen and desktop look normal. RA24 is the DRM format RGBA8888, which amdgpu turns down here; what asks for it wasn't looked into. Treated as log noise unless something looks wrong.

## Open items

- [x] Adapt the module kit and the guard for Fedora
- [x] Build and install the patched module, the Wi-Fi sleep hook and the guard, switch to `mem_sleep_default=deep` (see [Patched amdgpu module](#patched-amdgpu-module))
- [ ] Lid-close test through KDE (PowerDevil), and a sleep-test.sh power measurement
- [x] Run `bluetooth/bt-fix.sh`
- [x] Steam (RPM Fusion), gamemode, Flathub, full ffmpeg, malcontent, F-keys (see [Apps, codecs and parental controls](#apps-codecs-and-parental-controls))
- [ ] Steam Family for the child's account
- [ ] Back up `/home` to another disk (snapshots are on the same SSD)
- [ ] Optional: hardware video decoding, Intel i965 first, then dropping the mask (see [hardware.md](hardware.md#hardware-video-decoding-not-set-up-yet))
- [x] Snapshots: run `backup/snapper-fedora.sh`, check that a Discover install creates a pre/post pair
- [ ] Snapshots: confirm an update installed on restart creates a pair (`snapper -c root list`), try a restore once
- [ ] Camera (optional)
- [ ] Take good SMC/EC dumps with `smc/smc-ec-dump.sh`
- [ ] Once Fedora's kernel has the amdgpu fix, remove the patched module and the guard (see [Patched amdgpu module](#patched-amdgpu-module))
- [ ] Optional: build a kernel with the MTRR patch and send a Tested-by for it upstream
