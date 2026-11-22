# Samsung Galaxy Book4 Edge 16" on Linux: knowledge base

Distilled, distribution-independent facts from building SB4-Edge-Linux (Ubuntu 27.04 (26.04.1 before), kernel 7.4-rc3). Written
for people and AI agents who want to reproduce, verify or redo this work in another way (another distribution,
upstream patches, a different userspace). Each section: **hardware**, **what was wrong**, **the fix used here**,
**how it was verified**, **open points / alternatives**. File paths refer to this repository. The chronological log
with dead ends is `docs/DEVELOPMENT-NOTES.md`.

Confidence tags: **[verified]** tested on the 16" hardware; **[partial]** works with caveats; **[unverified]**
implemented but not tested on hardware; **[open]** not solved.

## Machine

- Samsung Galaxy Book4 Edge 16" (NP960XMB), Snapdragon X Elite **X1E-84-100** (SoC "hamoa" / x1e80100 family),
  BIOS P00AKX.068 (2026-04). The 14" (NP940XMA) shares most of the design; the 15.6" is similar.
- Internal storage is **UFS** (`/dev/sda`), not NVMe. Windows layout: ESP 260 MB (label SYSTEM), MSR, BitLocker C:,
  Recovery.
- Boots Linux with a **devicetree** (no usable ACPI for Linux). The DTB is selected at boot by the **stubble** EFI
  stub from SMBIOS CHIDs (`overlay/hwids/*.json`, computed by `chid.py`), so one kernel image serves several models.
- **Secure Boot must be off** (the stubble-wrapped kernel is unsigned). With Secure Boot off, BitLocker measures the
  boot path: Windows asks for the recovery key once after the boot menu changes;
  `manage-bde -protectors -disable C: -RebootCount 1` then a boot via the new path reseals it.

## Kernel

- Base: mainline **v7.4-rc3** (aebb72744764) + Maxim Storetvedt's Galaxy Book4 Edge devicetree series (v8,
  patchwork 1177250; `patches/kernel/0001-0003`) + local changes (`patches/kernel/0004-sb4edge-local-changes.patch`).
  `prepare-kernel.sh` applies them; `build-kernel.sh` builds Debian packages; config = Ubuntu's config ∪ arm64
  defconfig + `sb4edge.config`.
- Local changes (individually in `patches/sb4edge-local/` for the rc2 era): usb_2 for the fingerprint reader,
  i2c buses for the PD controllers / charger, ov02c10 at 26 MHz, WSA883x speaker nodes and volume cap, keyboard EC
  node, PS8830 retimers dtsi, DMIC 2.4 MHz, VA capture fixed at 4 ch + module config blobs, SD card, VRR (AVR) for
  msm eDP, platform_profile without ACPI, pmic_glink_altmode `inject` sysfs, DP data-lanes.
- **ASoC regression in 7.4-rc2** [verified, fixed upstream in rc3]: `soc_new_pcm_runtime()` allocated the rtd with
  `devm_kzalloc_flex()`, which set the `__counted_by` counter `rtd->num_components` to the array size;
  `snd_soc_rtd_add_component()` then appended after N NULL slots, so no component ever probed and the sound card
  never registered. Fix was `rtd->num_components = 0` after allocation. Not board-specific: any ASoC card on rc2.
- Out-of-tree modules (`extra/`): `samsung-galaxybook-battery` (EC battery, mailbox), `samsung-galaxybook-kbd`
  (keyboard light, Fn key, fan hwmon, platform_profile), `gb4e-typec` (retimer/orientation glue), plus `usbc`
  (userspace PD helper).
- Idle: a third-party 6.19 tree drops CL5 + SS3 idle states to avoid idle crashes; prepared as an optional dtsi,
  **not needed so far** on 7.4.

## Embedded controller (EC)

- ENE KB9058-class EC on I2C. Two ports: **0x62** (on the bus Linux calls i2c-6 side, "simple" commands) and
  **0x64** (mailbox; Linux i2c-5 5-0064 here). ACPI ECTC `_CRS` names both.
- **Mailbox protocol** (from Windows EC2.sys `SecEne9058KbcSendExCmdFull`, IOCTL 0x30800) [verified]:
  EC RAM write `{0x40, 0, hi, lo, data}`; read = write `{0x30, 0, hi, lo}` then read 2 bytes, reply `{0x50, data}`.
  Slot byte 0xF49F (dirty mirror 0xF49E). Wait until 0xFF10 == 0, write inputs at 0xF480.., command at 0xFF10,
  wait again, outputs at 0xF480... Command length table in EC2.sys `.data` 0x14000C5A0 as `{cmd, nIn, nOut, flags}`.
  Implemented as `sgb_ec_excmd()` exported by the battery module (shared lock).
- Commands used: **0xE9** battery life extender (`{0x90,pct}` set, `{0x91,0}` get, `{0x92}` capability);
  **0xFD/0xFC** keyboard light set/get (1 byte level 0-3); **0xEE** `{0x80, mode}` performance mode
  (0x00 Optimized, 0x0A Quiet, 0x15 Performance); fan target via port 0x62 `{0x17, rpm BE32}`.
- The 0x62 command `{0x10, timeout, level}` (OpenBSD samsabi, EC2 IOCTL 0x3003C) cannot hold keyboard levels 1-2:
  the EC fades them. Use the mailbox 0xFD instead.

## Battery and charging

- Battery: EC driver from Saddytech (modified). Bug fixed: design/full capacity words were swapped ("stuck at
  82%" was really 82% health) [verified]. `qcom_battmgr` must not load (blacklist, also in the initramfs).
- Charge limit: `charge_control_end_threshold` 1-100 via mailbox 0xE9 (100 = off, written as 0). UPower accepts
  end-only, so GNOME "Preserve battery health" drives it [verified].
- Status: EC B1ST bit 3 is the ACPI _BST "charge limiting" bit. At the limit the EC sets it without the
  charge/discharge bits; the driver used to report "Charging" (GNOME showed the charging icon with Preserve battery
  health on). Fix: discharge/charge bits first, then bit 3 = "Not charging" on AC (else "Discharging") [verified].
- Charging hardware: two **S2MM006** PD controllers (Samsung PDIC) at 0x33 on two I2C buses; **ISL9241** charger
  (0x09) and SBS gauge (0x0b) on i2c20. The PD controller waits for the host to close the **charger input switch**
  (cmd 0x12) after attach, as Windows EmuEc.sys does; without it a charger plugged after boot is ignored.
  `extra/usbc/usbc.c` (sb4edge-usbc service) does this [verified: 20 V / 3 A contract after replug].

## USB-C

- Per port: S2MM006 PD controller + **Parade PS8830 retimer** at 0x08 (port 0 on i2c3, port 1 on i2c7) + QMP combo
  PHY. Devicetree graph: pmic_glink -> retimer -> QMP PHY (`patches/sb4edge-local/x1-samsung-galaxy-book4-edge-retimers.dtsi`).
- The ADSP does **not** send altmode/orientation notifications on this machine, so userspace (`sb4edge-usbc`) reads
  the PD controller and pushes orientation/mode (gb4e_typec module, pmic_glink_altmode `inject` sysfs patch).
- **SuperSpeed** [verified, both ports, both orientations]: works on hot-plug. A device already plugged at boot
  stayed at 480M because no orientation was ever set; fix: at service start, cycle VBUS once on powered ports
  (skipped if a mounted filesystem lives behind that port, so a live USB keeps power). Note: many USB-C cables are
  USB 2.0-only; early "no SuperSpeed" results came from such cables.
- Windows programs the PS8830 from qcusbcucsi8380.sys: reset GPIO low 15 ms, high 60 ms, then regs 0x00/0x01/0x02
  (init 01/00/00, USB3 21/00/00, DP4 01|03/85/00, DP+USB 21|23/85/00) - same as Linux ps883x.
- **DisplayPort alt mode** [partial]: the S2MM006 runs Discover/Enter/Configure itself once allowed: reg 0x50 bit0
  StartAlt, bit1 ContinueAlt; pin assignment in 0x51 bits 0-2 (1 A, 2 C, 3 D, 4 E, 5 B, 6 F); progress in
  0x1A|0x57<<8. Negotiation reaches pin C + Configure ACK + HPD; msm then fails the EDID read behind a USB-C->HDMI
  adapter. [open] Switching a port from DP back to USB3 times out in `qmp_combo_reconfigure_phy` (clk imbalance in
  `qmp_combo_com_exit`), USB3 dead until reboot.
- usbcore is built in; hub autosuspend disabled (udev rule + `usbcore.autosuspend=-1`).

## USB-A, SD card, HDMI

- USB-A (a400000.usb) SuperSpeed [verified].
- SD card: sdhc_2, card detect GPIO 71 [verified, SDR104]. One bad-contact episode on insert (reseat fixed it).
- HDMI: Realtek **RTD2171** DP->HDMI bridge on DP3 (simple-bridge). Its DPCD offers only HBR2 x4 and the HDMI side is
  TMDS-only (<= 600 MHz): e.g. 5120x1440 max 75 Hz with a custom EDID override (`display/g9`).

## Display (internal OLED)

- 2880x1800 OLED, eDP, 120 Hz. EDID gets an extra 60 Hz timing (`display/make-edid.py`, loaded with
  `drm.edid_firmware` from the initramfs).
- **VRR** [verified]: msm had no VRR on X1E; the patch drives the DPU INTF **AVR** registers (downstream "Qsync"
  avr_setup/ctrl/trigger), sets `DP_MSA_TIMING_PAR_IGNORE_EN`, exposes `vrr_capable` (DPCD 0x007 bit 6 + EDID
  48-120 Hz). `msm.vrr=3` keeps AVR always on because GNOME 50 only enables VRR for fullscreen windows. Measured
  48.6 Hz idle, 120 Hz moving.
- msm PSR (`msm.psr_enabled=1`) flickers/blanks on X1E: not used.
- Brightness memory: GDM's greeter idle-dim (30%) leaked into the saved value; fixed with greeter dconf
  `idle-dim=false` + a saver service (`overlay/backlight`).

## Keyboard, Fn keys, fan, performance modes

- Touchscreen: Goodix **27C6:0123**, HID over I2C on **i2c8** at 0x5d (`hid-descr-addr` 1), from the devicetree
  series; hid-multitouch, 10 contacts, 28800 x 18000 at 84 units/mm (343 x 214 mm) [verified 2026-11-16: 10 fingers
  at once]. Touchpad: 4D49:4150, 5 contacts.

- Keyboard: i2c-hid 0CF2:9050. The Fn+F9 (keyboard light) key sends **vendor report 7, usage page 0xFF00**:
  `07 65 6e 65 00 bf` ("ene", 0xBF), press only; hid-generic maps nothing. The kbd module adds a HID driver that
  catches it and steps the light 0-1-2-3. It must set `HID_QUIRK_INPUT_PER_APP` (as hid-generic does) or all
  collections merge into one input device and normal keys break [verified].
- GNOME OSD for the keyboard light comes from UPower `BrightnessChangedWithSource("internal")`.
- Fan: EC port 0x62 `{0x17, rpm BE32}`; no tachometer readable. Curve service `sb4edge-fan` (per performance mode).
- Performance modes (Windows Samsung Settings -> SABI -> ACPI SCAI PRF3 -> EC 0xEE) mapped to Linux
  `platform_profile` (quiet/balanced/performance) so power-profiles-daemon/GNOME drive it [verified echo].
- CPU: `cpufreq/boost` defaults to 0 (cap 3.8 GHz); boost OPP 4.2 GHz exists on two clusters but **schedutil never
  selects it**; the performance governor does. Geekbench 6 with boost + performance: ~2840-3010 single /
  ~14850-15100 multi (Windows class).

## Video decoding and encoding

- **Iris** video codec (`qcom,x1e80100-iris`, falls back to sm8550; node in hamoa.dtsi, disabled because the
  firmware is signed per vendor). Enabled in the board dtsi with `qcvss8380.mbn` from Samsung's Windows graphics
  driver (qcdx8380 31.0.178.0, the same package as the GPU zap shader) [verified 2026-11-16].
- Exposed as V4L2 stateful devices `qcom-iris-decoder` / `qcom-iris-encoder` (the Adreno GPU has no video engine;
  Mesa has no VAAPI driver for it). VA-API on top: Ubuntu's qcom-va-driver (`qcom_drv_video.so`, msm alias) needs
  the five Iris patches 0006-0010 (decode-order output = DEC_DISPLAY_DELAY controls, else every picture fails with
  "S_CTRL DISPLAY_DELAY ... Invalid argument"). With them [verified 2026-11-19]: ffmpeg -hwaccel vaapi 4K H.264
  40 Mbit/s 73 fps at 27 % of one core (software 380 %), output bit-identical to software for H.264 and HEVC; the
  qcom-va-driver-tests suite passes (AV1 7 cases, error recovery, encoder, VPP scaling/tone mapping as root;
  /dev/dma_heap/system is root-only). VPP overlay needs CDSP VPP, disabled in Ubuntu's build. Citrix Workspace
  (26.08 arm64) cannot use VA-API: its bundled FFmpeg libraries have the vaapi hwaccels configured but no libva code. GStreamer `v4l2h264dec`/`v4l2h265dec`/`v4l2vp9dec`/`v4l2av1dec` (rank
  primary+1, so GNOME players use them by default) and `v4l2h264enc`/`v4l2h265enc`; ffmpeg/mpv `*_v4l2m2m`
  (h264, hevc, vp9). Measured: 1080p H.264 650 fps at 32 % of one core (software: 398 %), 4K HEVC 240 fps at 43 %.
  VP9 1080p and AV1 720p decode verified (~500 fps, ~40 %). Only 4:2:0 8-bit main profiles: a VP9 profile 1 / AV1
  high (4:4:4) stream stalls or fails to negotiate (test clips from videotestsrc need format=I420).
  Works after a cold boot with the codec in the board DT (kernel 7.4rc3-2).
- Encoders: H.264 (baseline..high) and HEVC (main, main 10), NV12 input; no VP9/AV1 encode. Decoder profiles: H.264
  baseline..high, HEVC main/main 10, VP9 profile 0, AV1 main.
- Benchmark (`tools/video-bench.sh`, AC): encode 1080p H.264 411 fps / 49 % CPU (x264 veryfast 183 fps / 580 %),
  4K HEVC 146 fps / 54 % (x265 veryfast 41 fps / 966 %); decode 4K HEVC 245 fps / 41 % (avdec 293 fps / 623 %),
  AV1 1080p 429 fps (libaom 185); transcode 4K HEVC -> 4K H.264 hw->hw 98 fps / 27 % (sw 53 fps / 624 %). On easy
  synthetic content the 12-core CPU decodes faster but uses 10-20x the CPU time.
- GPU: Adreno X1-85 with Mesa 26.2.6: OpenGL 4.6, OpenGL ES 3.2, Vulkan 1.4 (turnip, conformant) [verified].
  Mesa 26.3.0 benchmarked against it (glmark2/vkmark): not faster (equal at native resolution, lower at 800x600),
  same API versions; the ISO keeps Ubuntu's 26.2.6.
- Browsers: Firefox can use V4L2-M2M through the system libavcodec (Mozilla bug 1833354) - untested here; the
  Nightly build tested lacks its v4l2test probe helper.

## Audio

- ADSP AudioReach. Four speakers: **WSA883x** (not WSA884x as in early DTs) at SoundWire addr 1/2 on two masters
  (tweeters / woofers). Topology `X1E80100-GalaxyBook4Edge-tplg.bin`, four-speaker UCM (`overlay/audio`), PipeWire
  upmix. Volume cap raised (mainline -3 dB ~ half of Windows loudness).
- Headphone jack (wcd938x) [verified]. A UCM include missing from Ubuntu's alsa-ucm-conf made alsaucm reject the
  whole profile: ship a local copy.
- Microphones [verified]: DMIC0 + DMIC1 only. The VA capture graph only starts with **4 channels** (patched BE fixed
  at 4 ch so 2-ch works); WirePlumber maps 4 ch to FL FR AUX0 AUX1. DMIC clock **2.4 MHz** (4.8 MHz gave
  broadband noise). Gain via UCM (VA_DEC0/1 volume 116). Noise suppression: either PipeWire WebRTC echo-cancel or
  Qualcomm **Fluence** on the ADSP with Samsung's calibration (`fluence/`, needs Qualcomm's adsprpcd; see
  `fluence/NOTES.md`).

## Camera

- OmniVision **OV02C10** on CCI0 + CAMSS (csiphy register size must be 0x2000; 0x1000 oopses in csiphy_reset),
  26 MHz clock [verified ~32 fps 1080p].
- libcamera needs an OV02C10 sensor helper (black level 4096, analogue gain linear) and a tuning file
  (`extra/libcamera`). libcamera 0.7 soft-ISP bug: black level subtracted after AWB gains -> magenta image in dim
  light; patched to subtract before gains.
- Keep distribution updates from replacing the rebuilt libcamera (hold + pin).

## Wireless

- Wi-Fi WCN7850 (17cb:1107, board-id 255): linux-firmware lacks the board entry; reuse the shared board-id 255
  data in a board-2.bin entry (`ath12k-board2-add.py`). Samsung's Windows bdwlan.elf crashes the firmware.
- Bluetooth: needs a stable public address set at boot (`overlay/sb4edge-bt-addr`, mgmt socket).

## Ambient light sensor

- **Vishay VEML3328** on the ADSP **sensor island** (SSC I2C 7, addr 0x10), powered by LDO15_B. Not visible to
  Linux I2C: read through the Qualcomm Sensor Core (QMI over QRTR) [verified: 3.24 lux = Windows].
- The ADSP sensors domain needs userspace to serve its filesystem: `/vendor/etc/sensors/sns_reg_config` (fixed
  path) and a **writable** registry. With the read-only hexagonrpcd it asserts in `sns_registry_sensor.c:279`, the
  ADSP crashes and **TrustZone resets the whole laptop**. Use Qualcomm's `adsprpcd sensorspd adsp` (full apps_std).
  Config from the Windows driver package (`sensors/qcom-root`), CRLF stripped, config mtimes set to 1719256666.
  Must start at boot, before the sensor drivers probe.
- Location: **centre of the top bezel** (a torch there reads 250-320 lux against 6-9 lux room light) [verified
  2026-11-16].
- SSC data type is **"color"** (not "ambient_light" or "rgb"). Event floats: lux, CCT, x, y, raw.
- Userspace: libssc 0.4.4 (patched data-type override) + iio-sensor-proxy 3.9 (first with SSC). GNOME auto
  brightness works. Keyboard rule (Samsung's): light off above 100 lux, on below 50 lux, 3 s debounce.
  gsd-power bug: after an iio-sensor-proxy restart it never re-claims the sensor until re-login.
  iio-sensor-proxy patched (patches/iio-sensor-proxy): client_vanished_cb no longer aborts on a missing client table
  (crashed twice on the installed laptop); the drop-in restarts it on failure (gsd still needs a re-login after that).
- Stock GNOME auto brightness: gsd sets the light at the last slider change as 2/3 of full scale and scales
  linearly with lux, unbounded (6 -> 25 lux took the screen from 16 % to 93 %). gnome-shell applies
  `target + slider - 50 %`. Patches here (`patches/gnome-settings-daemon`, `patches/gnome-control-center`) add
  `ambient-mode` to `org.gnome.settings-daemon.plugins.power`: **adjust** (default; at most +-`ambient-adjust-range`
  = 25 % around the slider, limit reached at 8x brighter/darker, log scale) and **curve** (fixed log lux ->
  brightness curve 1:8, 5:20, 20:35, 80:50, 300:65, 1000:80, 5000:100 %). Settings -> Power shows "Brightness
  Adjustment" (Around the Slider / Follow Room Light) under Automatic Screen Brightness [verified: slider 47 %,
  25 lux -> 963 vs 705 raw]. Proposed upstream to GNOME.

## Fingerprint reader

- **EgisTec ETU905A80-E**, USB **1c7a:05a1**, firmware 9050.1.2.32, in the power button, on **usb_2** (enable
  usb_2 + its HS PHY behind the eUSB repeater in the DT). libfprint driver `egismoc`, match-on-chip, 10 touches.
- Without **SDCP** the chip keeps no print: enrollment completes but the next open lists 0 prints and fprintd
  deletes the enrollment [verified]. libfprint **MR !547** (SDCP v2 for egismoc, unmerged) fixes it.
- This sensor's SDCP model certificate arrives with **one byte zeroed** in the issuer ("Microsoft Cor\x00oration"),
  so OpenSSL cannot build the chain and the CA signature fails on the received bytes. Fix (`extra/libfprint` patch):
  only on "unable to get local issuer certificate", and only when that byte sequence occurs once, restore the byte
  and run the same X509_verify_cert (X509_STRICT, no time check, same truststore) on the restored certificate
  [verified 2026-11-18: "model certificate verified once its zeroed issuer byte was restored", prints listed].
  (Until 2026-11-18 the fallback checked the signature by key identifier and then verified only the CA's chain.)
  Plus a double free on the verification error path in the MR.
  The device MAC check passes on the received bytes, so the damage is in the sensor's stored certificate.
- **Prints are stored on the chip and shared with Windows.** fprintd's enroll duplicate check deletes on-chip prints
  it does not know, so enrolling the same finger in Linux deletes the Windows Hello copy; Windows then drops the
  Linux one. A Linux-enrolled print is not usable by Windows (Windows Hello keeps its own database). Solution here:
  enroll in Windows Hello; `sb4edge-fingerprint-import` records an unknown chip print (SDCP enrollment ID) as an
  fprintd print of a Linux user [verified: unlock in Linux, Windows Hello still works, both ways after reboots].
  Chip prints carry no owner (list_prints: username/description empty, finger UNKNOWN), so since 2026-11-18 a print
  is bound only after the user touches the sensor (identify_sync over the new prints; egismoc supports IDENTIFY).
  Boot service and pam_exec only report new prints, unless AUTO_IMPORT=yes in /etc/default/sb4edge-fingerprint
  (the old touch-free import: every new print -> the only regular user; a shared Windows Hello would give another
  person's finger this account, sudo included - independent review, 2026-11-18).
- Rest the finger; pressing is a power-button press.
- Windows Hello names prints 1, 2, 3, not by finger, so imported prints get a guessed finger. Relabel with
  `sb4edge-fingerprint-import --rename FROM TO USER` or the pencil button per print in Settings -> Users ->
  Fingerprint (GNOME Settings patch; polkit action `org.sb4edge.fingerprint-rename`, admin) [verified].
- Power: USB autosuspend for the reader (udev, 2 s delay) saves about 0.5 W at idle with no extra unlock delay
  [verified: 3.3-3.6 W vs 4.0-4.4 W, battery, screen at 30 %].
- **Login from the GDM user list with one touch** [verified 2026-11-21]: GDM runs PAM only after a user is chosen.
  `sb4edge-fp-identify` (root, D-Bus `org.sb4edge.FingerprintIdentify`, callable by group gdm) verifies the finger
  against each user with prints while the greeter's list is shown (only while that session is active); a match
  releases the reader, writes a one-time token (`/run/sb4edge/fp-token/USER`, root 0600, valid 20 s, whole seconds
  since boot) and emits Identified; a greeter-only `loginDialog.js` overlay selects that user and
  `pam_exec sb4edge-fp-token` (in gdm-password and gdm-fingerprint, before the normal checks) accepts the token once.
  With several users, a finger that does not match the user being tried moves on to the next: touch again.
- **Ubuntu PAM quirk:** `common-auth` starts with `pam_fprintd` (timeout 10, one try), and GDM's gdm-password includes
  it while GDM also runs its background gdm-fingerprint service: both claim the reader when a prompt starts
  (fprintd "Device was already claimed"). The password one usually wins and stops listening once text is typed, so
  the lock screen ignored the finger with text in the field. gdm-password now skips exactly that module
  (`auth [success=1 default=ignore] pam_permit.so` before `@include common-auth`, only while it is the first auth
  line); the background service then always has the reader [verified]. sudo/polkit keep fingerprint.
  `overlay/gnome/sb4edge-gnome-persist` maintains these PAM lines across upgrades.

## Boot

- Live ISO: Ubuntu's ISO remastered (`remaster.sh`): own GRUB (`refind/build-grub.sh`, silent) as the ESP boot
  program; casper; ISO9660 partition offset 16 so the ISO partition is mountable (persistence).
- Installed: **rEFInd** on the internal ESP, kept first in BootOrder by a service; GRUB hidden; Windows tile points at
  `\EFI\Microsoft\Boot\bootmgfw.efi`. rEFInd starts on the last OS booted (no `default_selection`; `use_nvram false`
  keeps that in `EFI/refind/vars` on the ESP); `default_selection Ubuntu` had made it always pick Ubuntu. Never leave a `vmlinuz-*` copy in /boot during kernel installs (update-grub
  picks it up as the default).
- Installer: "Install alongside Windows" works once C: is shrunk in Windows (the installer cannot resize BitLocker).
  A leftover `/cdrom` directory in the squashfs crashed the installer (configure_apt) - remove it after remastering.
- Kernel parameters `clk_ignore_unused pd_ignore_unused` are required: without them xhci-hcd.4.auto fails to probe
  (-110) and idle power does not improve (5.12 vs 4.99 W) [verified]. `mem_sleep_default=s2idle` (deep is not
  offered). `sb4edge-hdmi-sleep-guard` keeps the laptop from suspending with an HDMI adapter attached, since
  unplugging it during/after sleep crashed the machine.
- The PMIC RTC (rtc-pm8xxx) is read-only on this laptop and keeps no time across boots (it reads 2024-07-05):
  install fake-hwclock (or anything that restores a saved time early), otherwise NTS time sync fails its certificate
  checks until the clock is stepped, and early logs carry wrong dates.
- Ubuntu 27.04 has no arm64 desktop ISO yet: the image is Ubuntu 26.10's ISO with every squashfs layer
  dist-upgraded to 27.04 (ports.ubuntu.com) in `remaster.sh`.

## Windows partitions from Linux

- cryptsetup 2.8.4 rejected recent Windows 11 BitLocker volumes ("Unexpected metadata entry value '36'": a new
  12-byte entry in the clear-key VMK); patched to skip unknown VMK entries (`patches/cryptsetup`).
- Mount NTFS with ntfs-3g only: ntfs3 mounts a hibernated (Fast Startup) volume read-write.
- **Read-only Windows drive with per-folder unlock** (`windows/sb4edge-windows-mount`, Files menu
  `windows/sb4edge-unlock-folder.py`) [verified 2026-11-21]: ntfs-3g read-write at a root-only path, the /run/media
  view a read-only bind, unlocked folders writable mounts on top (x-gvfs-hide), remembered in
  /var/lib/sb4edge/windows-unlocked. Pitfalls met: GIO judges `filesystem::readonly` by device number, so a plain
  bind mount of the same filesystem looks read-only to GNOME Files (refuses New Folder, then Nautilus crashes in its
  error path) - use bindfs (own device); bindfs with a space in its source records its source as "bindfs" and loses
  x-gvfs-hide (Files shows an "Unmount" it cannot do) - read through a spaceless alias bind; `findmnt -l` escapes
  spaces as `\x20` - parse /proc/self/mountinfo; `os.path.ismount` misses same-filesystem binds; a lock/unlock
  changes only the mount, so touch the folder (same inode, through the read-write mount) for Files to re-read it; an
  unlocked folder's own entry is in its locked parent (rename/delete need the helper).

## NPU (Hexagon compute DSP)

- The 45 TOPS NPU is the Hexagon **CDSP** (`remoteproc` with `qcom,x1e80100-cdsp-pas`, firmware `qccdsp8380.mbn`),
  reached through FastRPC (`/dev/fastrpc-cdsp`). There is no DRM accel device (`/dev/accel*`) on X1E; that is
  expected, not a missing driver. Running work on it needs Qualcomm's userspace (libcdsprpc, `fastrpc_shell_3`,
  QNN HTP libraries) or an onnxruntime build with the QNN provider; none of these are in Ubuntu.
- Load: the DSP firmware keeps SysMon statistics in SMEM (host 5, item 634): records with a header
  `feature << 28 | length << 16`. Feature 1 = Q6 load (thousands of cycles/s + a 64-bit arch-timer timestamp),
  feature 2 = event stats (first word: Q6 clock vote in kHz), feature 3 = power stats. Load / clock vote = compute
  DSP load. Reading it never wakes the DSP. `extra/sb4-cdsp-stats` exposes it as
  `/sys/module/sb4_cdsp_stats/parameters/load_permille` (layout from Qualcomm's downstream
  `sysmon_subsystem_stats.c`). The timestamp stays 0 until the DSP first runs something after boot: report that as
  idle (0), like the downstream driver, not as missing data [verified: one FastRPC capability query fills it].
  This is Q6 core load, not HTP tensor-engine utilisation, which the firmware does not report.
- Resources (`patches/resources/snapdragon-monitoring.patch`) shows the load, firmware state and the hottest `nsp*`
  thermal zone. Its graphs autoscale; a steady temperature then fills the graph and reads as full load, so the
  Hexagon temperature graph is pinned to 0-100 °C.

## GNOME desktop (Ubuntu Dock, overview)

- **Ubuntu Dock over maximized windows at fractional scaling** [verified 2026-11-21]: with the top bar (hidetopbar)
  and the dock hidden, a maximized window covers the monitor and mutter unredirects it; the dock only inhibited
  unredirection for fullscreen windows, so it flickered and lost hover over maximized Firefox (it behaved while a
  notification was up - the message tray disables unredirection). Fix: inhibit whenever the dock is on screen.
  Also: at 166 % the pointer at the bottom sits in the last physical pixel row, outside the dock's whole-pixel area
  (edge watch), and a resting touchpad finger jumps the pointer 15-50 px when it lifts (tolerance zone above the
  dock). All in `overlay/gnome/sb4edge-dock-fix`, re-applied by an apt hook.
- **Fullscreen windows on the fractionally scaled panel jump when the top bar appears** [verified 2026-11-21]: direct
  scanout lets the display hardware do the 1.667x scaling, a few pixels off GNOME's own; the picture shifts when GNOME
  composites again (top bar/dock shown). Fix: no unredirection for fullscreen windows on fractionally scaled monitors
  (dock-fix patch 5); integer-scaled monitors keep direct scanout.
- **Page flips failing after login with two monitors** [verified 2026-11-21]: the login screen's default layout
  leaves hardware planes on other CRTCs than the user's session expects; mutter then moves a plane between CRTCs in
  one commit, the DRM core refuses ("switching CRTC directly", EINVAL), and frames drop until a full modeset. Giving
  the login screen the user's monitors.xml (/etc/xdg/monitors.xml) avoids it; `sb4edge-gnome-persist` keeps it in sync.
- **Overview Esc:** `snapd-search-provider@canonical.com` (declares GNOME 48-49) breaks Esc on GNOME 51; disabled.
  `sb4edge-overview-close` adds Esc / empty-click close and workspace-preview click to switch [verified].
- Extensions declare GNOME versions; `sb4edge-gnome-persist` adds the running major to the project's own extensions
  after upgrades so they are not silently disabled.

## Open problems (good places to contribute)

1. USB-C DP -> USB3 reconfigure timeout (qmp-combo clk imbalance); DP alt mode EDID read behind adapters.
2. Upstream: libfprint MR !547 + the certificate fix; the msm VRR (AVR) patch; the WSA883x volume cap; DT bits.
3. Secure Boot (signing the stubble-wrapped kernel, or a shim/MOK flow).
4. Fan tachometer; whether EC mode 0xEE changes the fan by itself.
5. A safe way to give fingerprints to multiple Linux users (map Windows Hello prints to accounts, e.g. by reading
   the Windows WinBio database).
6. Browser hardware video decoding (Firefox V4L2-M2M, Chromium).
7. GNOME: upstream the automatic brightness modes; gsd re-claiming the light sensor after iio-sensor-proxy restarts.
8. 14" and 15.6" models: most of this applies; DT differences (USB-A port uses eusb6 on the 16").
9. NPU userspace: an open way to run models on the Hexagon NPU (FastRPC + QNN HTP, or an onnxruntime QNN build).

## Sources and prior work

Maxim Storetvedt (DT series), hegjon/omarchy-galaxy-book4-edge (14": audio, usbc helper, retimer driver, fan),
Saddytech/Galaxy-Book4-Edge-linux (EC battery), ciscobugger/book4-edge-linux (15.6": camera helper, EC notes),
n1c0la84/book4-edge-linux (14": fingerprint, SDCP finding), jglathe/linux_ms_dev_kit and zensanp (X1E images, idle),
joshuagrisham/samsung-galaxybook-extras, OpenBSD samsabi, libfprint MR !547, libssc, iio-sensor-proxy, quic/fastrpc,
linux-msm audioreach-topology. Windows drivers analysed (EC2.sys, EmuEC.sys, qcusbcucsi8380.sys, qcdxkm8380.sys,
Samsung.Firmware.dll) for protocols only; no Windows code is included here.
