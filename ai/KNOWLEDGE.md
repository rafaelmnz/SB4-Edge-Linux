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
- Exposed as V4L2 stateful devices `qcom-iris-decoder` / `qcom-iris-encoder`, not VAAPI (the Adreno GPU has no video
  engine; Mesa has no VAAPI driver for it). GStreamer `v4l2h264dec`/`v4l2h265dec`/`v4l2vp9dec`/`v4l2av1dec` (rank
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
  find the CA by authority key identifier, restore the byte, accept only if the CA's signature verifies on the
  restored certificate, then verify the CA chain. Plus a double free on the verification error path in the MR.
  The device MAC check passes on the received bytes, so the damage is in the sensor's stored certificate.
- **Prints are stored on the chip and shared with Windows.** fprintd's enroll duplicate check deletes on-chip prints
  it does not know, so enrolling the same finger in Linux deletes the Windows Hello copy; Windows then drops the
  Linux one. A Linux-enrolled print is not usable by Windows (Windows Hello keeps its own database). Solution here:
  enroll in Windows Hello; `sb4edge-fingerprint-import` records the unknown chip prints (SDCP enrollment IDs) as
  fprintd prints of the Linux user (boot service + pam_exec at login; single-user systems only) [verified: unlock in
  Linux, Windows Hello still works, both ways after reboots].
- Rest the finger; pressing is a power-button press.
- Windows Hello names prints 1, 2, 3, not by finger, so imported prints get a guessed finger. Relabel with
  `sb4edge-fingerprint-import --rename FROM TO USER` or the pencil button per print in Settings -> Users ->
  Fingerprint (GNOME Settings patch; polkit action `org.sb4edge.fingerprint-rename`, admin) [verified].
- Power: USB autosuspend for the reader (udev, 2 s delay) saves about 0.5 W at idle with no extra unlock delay
  [verified: 3.3-3.6 W vs 4.0-4.4 W, battery, screen at 30 %].

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
- Ubuntu 27.04 has no arm64 desktop ISO yet: the image is Ubuntu 26.10's ISO with every squashfs layer
  dist-upgraded to 27.04 (ports.ubuntu.com) in `remaster.sh`.

## Windows partitions from Linux

- cryptsetup 2.8.4 rejected recent Windows 11 BitLocker volumes ("Unexpected metadata entry value '36'": a new
  12-byte entry in the clear-key VMK); patched to skip unknown VMK entries (`patches/cryptsetup`).
- Mount NTFS with ntfs-3g only: ntfs3 mounts a hibernated (Fast Startup) volume read-write.

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

## Sources and prior work

Maxim Storetvedt (DT series), hegjon/omarchy-galaxy-book4-edge (14": audio, usbc helper, retimer driver, fan),
Saddytech/Galaxy-Book4-Edge-linux (EC battery), ciscobugger/book4-edge-linux (15.6": camera helper, EC notes),
n1c0la84/book4-edge-linux (14": fingerprint, SDCP finding), jglathe/linux_ms_dev_kit and zensanp (X1E images, idle),
joshuagrisham/samsung-galaxybook-extras, OpenBSD samsabi, libfprint MR !547, libssc, iio-sensor-proxy, quic/fastrpc,
linux-msm audioreach-topology. Windows drivers analysed (EC2.sys, EmuEC.sys, qcusbcucsi8380.sys, qcdxkm8380.sys,
Samsung.Firmware.dll) for protocols only; no Windows code is included here.
