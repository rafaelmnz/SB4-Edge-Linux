<!-- Development log of this project, written while building it with Claude Code (an AI coding agent) and kept as working notes. Published as-is for review; personal details (names, IP addresses, host names, serial numbers) replaced with placeholders. Paths like ~/... refer to the build machine. -->

# sb4edge-linux hand-off

Custom Ubuntu 26.04.1 arm64 ISO for the owner's Samsung Galaxy Book4 Edge 16" (X1E-84-100).

- Kernel: mainline v7.4-rc2 + `patches/book4-v8` (Maxim Storetvedt v8 series, patchwork series 1177250). Built in Docker image `sb4build`, tree on volume `sb4-src`, by `build-kernel.sh` (config = Ubuntu 7.0 config ∪ arm64 defconfig, plus `sb4edge.config`).
- ISO: `remaster.sh` (privileged container, scratch volume `sb4-iso`). The kernel is wrapped with stubble via ukify using `overlay/hwids/*.json` (CHIDs computed by `chid.py`). Firmware copied from Windows is in `fw/`. The live initrd pins the ISO's casper UUID.
- Test: QEMU image `sb4qemu`, `-cpu cortex-a76 -nic none`; test GRUB menu in `test/grub.cfg`. A generic VM boots to GDM; a VM with the Samsung SMBIOS selects the Book4 Edge 16 DTB.
- Output: `~/Claude AI/apps/sb4edge-linux/ubuntu-26.04.1-sb4edge-desktop-arm64.iso`.
- Status 2026-11-13: not yet tested on real hardware. The owner will boot the USB live session; a hardware report may land in `hw-report/`.
- Safety: the laptop has BitLocker (TPM) and Secure Boot on. Never touch its partitions unless the owner asks. Agreed Linux partition size: 200 GB.
- Hardware test plan (2026-11-13, Mac Studio session): The owner boots the live USB, installs openssh-server + Tailscale, adds the Mac's key (`~/.ssh/id_ed25519.pub`, "<key name>") to `~ubuntu/.ssh/authorized_keys`. Then from the Mac: `scp hw-check.sh ubuntu@<ip>:` → `ssh ubuntu@<ip> sudo ./hw-check.sh /tmp/hw-report` → `scp -r ubuntu@<ip>:/tmp/hw-report/* hw-report/`. The script is read-only.
- First USB boot done 2026-11-13: see `hw-report/FINDINGS.md`. Wi-Fi/battery/BT fixes are in `remaster.sh` + `overlay/`, ISO not rebuilt yet. Keyboard still open. Live session reachable as `ssh ubuntu@<tailscale-ip>` (Mac key installed; scp/sftp unavailable, pipe through ssh).
- 2026-11-14: ISO rebuilt with keyboard/BT/Wi-Fi/battery fixes (sha f7ef972b…), flashed to the Realtek USB SSD. Fingerprint: Egis (ESS) sensor, likely on usb_mp port 1 (DT comment "MP0 goes to the USB-A port and FPC"; eusb5_repeater was defined but unused). `patches/sb4edge-local/0001-usb-mp-port1-fingerprint.patch` enables usb_mp_hsphy1 behind eusb5 (applied in the sb4-src tree); kernel debs bumped to 7.4rc2-3. libfprint 1.95.1 in the ISO supports 1c7a:0570-05ae,0603; actual PID unknown until the port enumerates.
- 2026-11-14: remaster.sh now upgrades the ISO from the archive (base: 298 pkgs; desktop layer minimal.standard upgraded as overlay upperdir over the new base, fix-broken first, aborts on any removal; status merged into all other layers; sizes measured du -sB1 before/after). Kernel 7.4rc2-3 (fingerprint port). QEMU: boots to GDM. Flashed to the Realtek stick, sha 829c92df…. sb4qemu image had to be rebuilt from docker/qemu.

## Build 2026-11-14 (third USB boot), ISO sha256 c005ba98…7901, kernel 7.4rc2-4

- Wi-Fi: `ath12k-board2-add.py` adds a board-2.bin entry for 17cb:1107 / board-id 255 reusing linux-firmware's
  shared board-id 255 (NCM825) data; installed at /usr/lib/firmware/updates/ath12k/WCN7850/hw2.0/board-2.bin.
  Samsung's Windows bdwlan.elf crashed the firmware (-110), so board.bin is no longer installed.
- Bluetooth: Python mgmt-socket helper (overlay/sb4edge-bt-addr) sets a stable public address. Verified live.
- Battery: Saddytech EC driver (extra/samsung-galaxybook-battery, GPL, unmodified) built and signed against the
  tree, in /usr/lib/modules/$KVER/updates; DT node embedded-controller@64 on &i2c0; qcom_battmgr blacklisted.
  The DTB from out/ (dtb-only rebuild) overrides the deb's in remaster.sh.
- Fingerprint: usb_2 + usb_2_hsphy enabled behind eusb5 (16" only: eusb6 is the USB-A port). Patch
  patches/sb4edge-local/0001-usb2-fingerprint.patch. Unverified on hardware.
- USB-C PD (S2MM006 at 0x33): i2c9 (a84000) and i2c15 (a9c000) enabled (0002 patch); omarchy's usbc helper
  installed as sb4edge-usbc.service but NOT enabled. Next boot: read-only check that 0x33 answers on both
  buses (i2cdetect -r -y on the buses whose realpath has a84000.i2c / a9c000.i2c), then `systemctl enable --now sb4edge-usbc`.
- QEMU test: `bash test/qemu-test.sh`.

## 2026-11-14 afternoon (fourth USB boot + remote dev loop), kernel 7.4rc2-5 built, ISO NOT rebuilt

Hardware on the 7.4rc2-4 stick: Wi-Fi, BT OK; fingerprint enumerates (EgisTec 1c7a:05a1, usb 5-1, fprintd sees it;
enrolment untested). "Battery stuck at 82%" was a decode bug: design/full capacity words swapped in Saddytech's
driver (fixed in extra/samsung-galaxybook-battery, SOURCE notes it); the battery is full, health 82%. No charge
limit is active on Linux. USB-C helper: its startup "VBUS off on powered ports" cut the boot stick (port 0); fixed
in extra/usbc/usbc.c (powered ports left alone); the service is enabled in remaster.sh now.

Kernel 7.4rc2-5 (sb4-src tree, patches/sb4edge-local/0001-0005 applied; 0006 applied after the -5 build):
- 0003 ov02c10 26 MHz; 0004 WSA883x speakers (DT had WSA884x 0204, chips are WSA883x 0217:0202 at addr 1/2 on
  sdw-master-1/4: omarchy layout Tweeter* on swr0, Woofer* on swr3); 0005 &i2c20 (ISL9241 0x09, SBS 0x0b) +
  camera dtsi (x1-samsung-galaxy-book4-edge-camera.dtsi: cci0 + camss with csiphy reg size 0x2000; 0x1000 oopsed
  in csiphy_reset); 0006 WSA883x volume cap PA 17 (0 dB) / digital 84 for samsung,galaxy-book4-edge (mainline caps
  at 6 = -3 dB, ~half Windows loudness per omarchy). Needs a kernel rebuild (7.4rc2-6) to take effect.
- Test UKI build/test/vmlinuz-test (stubble, -5 kernel + -5 DTB). First boot of it (09:18 EST) never came back on
  Tailscale (>10 min): suspect a hang (camss/camera nodes are now in the base DT). Logs, if any, in the stick's
  writable partition: sb4dev/logs/.
Audio (overlay/audio, from omarchy): topology X1E80100-GalaxyBook4Edge-tplg.bin, four-speaker UCM linked for both
  long names (…-2.1-NP960XMB_KB1US / NP944XMA_MC1US), WSA883x runtime-PM udev rule, PipeWire upmix. In remaster.sh.
  Card failure seen on -4: wcd938x set_jack with mbhc=NULL, wcd938x_soc_codec_probe never ran, qcom-apm CMD timeout;
  probably the missing topology + wrong WSA884x nodes. Untested with the fixes.
Keyboard backlight: extra/samsung-galaxybook-kbd (LED class "samsung-galaxybook::kbd_backlight", EC 0x62 on i2c5,
  SET {0x10,timeout,level 0..3}, GET {0x11}+8 bytes, level byte 3). Test overlay dtbo/kbd.dts. Needs a DT patch
  (kbd-backlight@62 under &i2c5) + remaster install. Unverified: whether the raw command lit the keys.
Charging: S2MM006 PD controllers verified (20 V/3 A contract). ISL9241 + SBS answer once &i2c20 is enabled. Not
  known whether the EC programs the ISL9241 (charges from low) or Linux must (ciscobugger's book4-pd-charge, 15.6").
  GNOME "Preserve battery health" needs charge_control_end_threshold: no EC register for it is known; the ISL9241
  route (ChargeCurrent 0 above the threshold) needs testing first.

Remote dev loop (works without the owner at the laptop):
- Stick grub.cfg (iso9660, LBA 3048, 1217 bytes, edited in place) entry 0 chains to ($writable)/sb4dev/grub.cfg,
  fallback entry 1 = normal 7.4 boot. The "persistent" entry (initramfs panic: whole-disk iso9660 mount claims sdb,
  so /cow can't mount) is gone.
- writable/sb4dev/: grub.cfg (dev menu; one-shot test entry via next_entry in grubenv, cleared by GRUB before
  booting), hook.cpio (casper-bottom 99sb4dev: installs sb4dev.service), setup.sh (dpkg -i debs/: openssh-server,
  curl, tailscale; restores Tailscale state = node <name> <tailscale-ip>; Mac key), local.sh (saves dmesg/journal/
  asound/media/power to sb4dev/logs/), vmlinuz-test. Sources in dev/.
- Mount the writable partition from the live session: losetup -o start*512 --sizelimit size*512 /dev/sdX (direct
  mount fails, same exclusive claim).

remaster.sh changes (not built yet): curl + openssh-server + tailscale (pkgs.tailscale.com resolute repo) in the
base layer, ssh/tailscaled enabled (live user has no password, so sshd is closed until one is set); SB4_DEV=1 adds the
dev grub entry; -partition_offset 16 so partition 1 is a mountable iso9660 (fixes persistence; stock uses 0);
audio block; USB-C helper enabled. Still to add: kbd driver + DT, battery threshold, camera userspace (libcamera
ov02c10 helper/tuning), kernel 7.4rc2-6.

Install/dual-boot test: QEMU (Homebrew, HVF) on the Mac, test/vm/: make-windows-disk.sh (ESP+MSR+NTFS C:+recovery
+34.7 GiB free), autoinstall.yaml (storage direct/use_gap = "install alongside"), run.sh install|boot.

### Install / dual-boot test results (QEMU HVF, 2026-11-14 ~10:10 EST)
- Bug found and fixed in remaster.sh: the chroot bind-mount point /cdrom was left in minimal.squashfs (stock has
  none) -> installer crashed at configure_apt ("File exists: .../mount/cdrom"). Any install from the current ISO
  (sha c005ba98…) would fail the same way on the laptop. Now `rmdir "$B/cdrom"` after teardown.
- With that fixed (test ISO = current ISO with only minimal.squashfs rebuilt), autoinstall storage direct/use_gap
  = "install alongside Windows": ESP reused (Windows files untouched), MSR/C:/Recovery untouched, Ubuntu ext4 in
  the 34.7 GiB gap (vda5). Installed system boots shim -> GRUB 2.14 -> 7.4.0-rc2-sb4edge (default entry) via
  dracut initrd to the login prompt. os-prober finds "Windows Boot Manager" once the ESP has
  EFI/Microsoft/Boot/{bootmgfw.efi,BCD} (the fake ESP first lacked BCD; make-windows-disk.sh now adds it) and
  update-grub adds the entry. The installer also writes shim to EFI/Boot/bootaa64.efi (stock Ubuntu behaviour).
- Kernel: install-sources.yaml kernel.default (linux-generic-hwe-24.04) is now pointed at
  linux-image-7.4.0-rc2-sb4edge in remaster.sh. Our kernel stayed installed either way (curtin's ensure_one_kernel
  doesn't recognise its name). linux-generic-hwe-26.04 7.0.0-43 also ends up installed (from the desktop layer's
  archive upgrade); GRUB defaults to 7.4 by version sort, but a future stock kernel > 7.4 would become default.
- Not testable in QEMU: BitLocker. The installer cannot resize a BitLocker volume: shrink C: from Windows Disk
  Management first (leaves unallocated space; the use_gap / "Install alongside" path then uses it), and have the
  BitLocker recovery key at hand (changing the boot path can trigger recovery). Secure Boot: shim+grub are signed
  by Canonical, but the stubble-wrapped 7.4 kernel is unsigned -> Secure Boot must be off (as on the live stick).
Camera userspace: libcamera 0.7.0-1ubuntu2+sb4edge1 debs built (out/libcamera; extra/libcamera/build.sh), the IPA
  contains the ov02c10 helper; remaster.sh installs them into the desktop layer (held) + tuning, configuration.yaml
  (software_isp cpu), WirePlumber rule hiding raw CAMSS nodes.

## Build 2026-11-14 10:39 EST: kernel 7.4rc2-6, ISO sha256 581c2f31…1d00 (in apps/, NOT flashed)
- Kernel: patches 0001-0007 (0006 WSA883x volume cap, 0007 kbd-backlight@62). Camera include commented out in the
  board dtsi (the -5 boot with it hung); camera dtsi + dtbo/camera.dts remain for testing.
- ISO adds: curl/openssh-server/tailscale (host keys removed from the image, ssh-keygen -A before sshd), audio
  overlay, kbd + battery modules, libcamera with ov02c10 helper (desktop layer, held), partition_offset 16,
  /cdrom removed, installer kernel default = ours. USB-C helper installed but not enabled.
- QEMU (final ISO): live boot from USB mounts sda1 (ISO9660 partition) as /cdrom; autoinstall use_gap next to the
  fake Windows: ESP reused, Windows untouched, GRUB gets "Windows Boot Manager (on /dev/vda1)" at install time;
  installed system boots 7.4rc2-6 (#6), ssh + tailscaled active with per-machine host keys, curl present.
- Note: the default "Ubuntu Desktop (minimized)" source has no libcamera (it is in the full desktop layer).
  Not yet tested on the laptop at all.

## Build 2026-11-14 11:20 EST: kernel 7.4rc2-7, ISO sha256 9c70fd53…90b9 (in apps/, NOT flashed)
- 0008 USB-C SuperSpeed: patches/sb4edge-local/x1-samsung-galaxy-book4-edge-retimers.dtsi, included at the end of
  the 16" dts (0008-usbc-retimers.patch). PS8830 retimers at 0x08 on i2c3 (port 0) / i2c7 (port 1) with their 6
  fixed regulators + pinctrl, graph pmic_glink -> retimer -> QMP PHY, SBU muxes disabled. Ported from omarchy's
  14" patch (retimer hunks only); the 15.6" ACPI UCS0 confirms the same buses/address (ACPI I2C4/I2C8). Compiled
  graph checked. extra/gb4e-typec (omarchy gb4e_typec, matches samsung,galaxy-book4-edge so it loads on the 16"),
  loaded via /etc/modules-load.d/sb4edge.conf. SuperSpeed needs sb4edge-usbc running (it sets orientation at
  attach); ports already powered at boot (a live stick) are left at USB 2.0 so the root device never drops.
- Hubs: usbcore is built in, so autosuspend is disabled by udev rule 63-sb4edge-usb-hub-pm.rules (hubs
  power/control=on), the ISO cmdline (usbcore.autosuspend=-1) and /etc/default/grub.d/60-sb4edge.cfg.
- Keyboard backlight driver rewritten: 1 s keepalive (the EC turns the light off otherwise; OpenBSD samsabi),
  probe fails cleanly if the EC doesn't answer, levels=1 for 3 levels (default on/off).
- Fan: the same EC port takes {0x17, rpm BE32} (EC2.sys, omarchy). samsung_galaxybook_kbd now exposes hwmon
  "samsung_galaxybook_ec" fan1_target (resent on resume); /usr/libexec/sb4edge-fan + sb4edge-fan.service apply
  omarchy's curve (0/3000/4500/6000/8000 rpm at 60/70/80/88 °C, override in /etc/default/sb4edge-fan).
- 3.5 mm jack: real bug found. HiFi.conf included /codecs/wcd938x/HeadphoneABEnableSeq.conf, which Ubuntu's
  alsa-ucm-conf 1.2.15.3 doesn't ship -> alsaucm rejects the whole profile (speakers too). Now a local copy in
  /usr/share/alsa/ucm2/Samsung/GalaxyBook4Edge/. Every other include checked against the package. Jack DT node =
  CRD's; "Headphone Jack"/"Mic Jack" kcontrols match the UCM.
- SD card: dtbo/sdcard.dts (cd-gpio 71, l9b/l6b) for runtime test.
- Idle crash (Launchpad #149, jglathe via zensanp 6.19): that tree drops CL5 + SS3 idle states. Prepared, NOT
  applied: patches/sb4edge-local/optional/x1-samsung-galaxy-book4-edge-idle.dtsi (costs idle power).
- Charger only seen after reboot (#154): sb4edge-usbc closes the charger input switch at attach (cmd 0x12) -> should
  fix hotplug charging once usbc is enabled.
- usbc + fan are installed but disabled; SB4_ENABLE=1 for remaster.sh enables both. On a running system:
  sudo systemctl enable --now sb4edge-usbc sb4edge-fan
- Fixed: remaster.sh overwrote the deb's DTB with a stale out/ copy (would have hidden 0008); removed, and remaster
  now fails if the DTB lacks ps8830 / kbd / battery nodes. Old copy in build/old/.
- Test on hardware, in order: boot, `lsusb -t` (5000M on USB-C after replug with usbc running), fan
  (`echo 3000 > /sys/class/hwmon/hwmonN/fan1_target`, listen), keyboard light, speakers, jack (plug-in switches
  output), SD overlay, camera (nocam kernel first).

## Windows driver search (online, 2026-11-14)
- Microsoft Update Catalog: no Samsung Arm (X1E) drivers. Every Samsung "Firmware" entry is AMD64 (Intel Galaxy Books);
  no hits for ACPI\SAM060B/SAM0602/4/5, SSEC0001/2, SUBSYS_C199144D. Samsung ships EC2.sys (ec2.inf, arm64, newest
  16.4.9.862, HWIDs ACPI\SAM060B, ACPI\SSEC0002, ...SUBSYS_C199144D / C1A1144D) only via Samsung Update. build/catsearch.py
  searches the catalog.
- Laptop BIOS: P00AKX.068.260409.WY.1908 (2026-04-09).
- Battery protection lead (ciscobugger reports/ec/06-command-table.md): charge limit = STPC, offset 0x24 of ACPI region
  BMOP (space 0x9E, EC2.sys region handler). DSDT declares STPC but no method uses it, so Samsung Settings/EmuEc.sys
  writes it through the region. Missing: the I2C mailbox opcode EC2.sys uses for space 0x9E (0x88/0x89 = space 0xA1).
  Needs EC2.sys (from the laptop's Windows: pnputil /export-driver) -> IDA -> region handler for 0x9E.

## Battery charge limit, from the Windows drivers (2026-11-14)

Windows "Battery protection" (Battery Life Extender), traced from the exported drivers:
- Samsung.Firmware.dll SetBatteryLifeExtender → EmuEC IOCTL 0x58430198 (set, u32 percent), 0x58430194 (get), 0x58430190 (capability); 0 = off.
- EmuEC.sys 7.22.18.735 (an EC emulator) → EC command 0xE9 with {0x90, pct} (set), {0x91, 0} (get, out[0] = pct), {0x92} (capability) → EC2 IOCTL 0x30800.
- EC2.sys 15.27.1.994 SecEne9058KbcSendExCmdFull, over I2C 0x62:
  - EC RAM write: {0x40, 0, hi, lo, data}. Read: write {0x30, 0, hi, lo}, read 2 bytes; reply is {0x50, data}.
  - Slot byte 0xF49F (dirty mirror 0xF49E).
  - Wait for 0xFF10 = 0. Input goes to 0xF480.., the command to 0xFF10. Wait again, then the output is at 0xF480...
  - Command length table at .data 0x14000C5A0: 0xE9 = 2 in, 3 out.
- Same command and sub-commands as the x86 samsung-galaxybook driver.

Implemented in extra/samsung-galaxybook-battery: charge_control_end_threshold, writable 1-100 (100 = off, written as 0).
- Probe logs the current EC value; it is never changed at boot, so the default is whatever the EC holds. It may still be set from Windows: check `dmesg | grep "charge limit"`.
- UPower 1.91 accepts end-only batteries (start OR end), so GNOME Settings > Power > "Preserve battery health" drives it.
- Hardware test: `cat /sys/class/power_supply/samsung-galaxybook-bat/charge_control_end_threshold`; `echo 80 | sudo tee …`; read it back; `echo 100 | sudo tee …` turns it off.
- Not hardware-tested yet: the laptop is in Windows.

ISO rebuilt with this driver 2026-11-14 13:09 EST: sha256 c69dc67556a4ce1cd58ebcb3ddacb311dafd564c5f788c7039d869156c426921 (apps/; previous 9c70fd53 ISO moved to apps/.../old/). Same kernel 7.4rc2-7. Not flashed.

## Third-party image "ubuntu2404_book4dge.img" (MEGA, 2026-11-14), extracts in research/img2404/
- jglathe's X1E devkit Ubuntu 24.04.4 plus zensanp kernel 6.19.14-ge2c46c019aa0-dirty (built on "sambook").
  - Modules are not installed, and the initrd (619-nofw.img) has no firmware.
  - Own book4edge14/16.dtb, devicetree loaded by GRUB.
  - cmdline: cma=128M pd_ignore_unused clk_ignore_unused arm64.nopauth efi=noruntime.
- No Samsung userspace: only the same keyboard udev rule; no UCM, no kbd or fan tools. board-2.bin is stock (no 17cb:1107 entry).
- 16" DT vs ours (book4edge16.dts vs ours16.dts):
  - Speakers are WSA884x @0,0 (ours: WSA883x @0,2, matching the IDs that enumerated on the hardware).
  - No retimers, no EC nodes.
  - Idle: clusters use CL4 only and the system domain has no idle state, i.e. our optional idle.dtsi.
    This is independent support for applying it if idle crashes show up on 7.4.
- Nothing else to take.
- Stick flashed 2026-11-14 13:2x with ISO c69dc675.
  - The writable partition was overwritten; sb4dev was backed up first to build/stick-backup-20261114/.
  - The readback was interrupted: the stick dropped off USB, so it is unverified.

## First hardware run of ISO c69dc675 (2026-11-14 ~13:40 EST, live from the 128 GB SSD, Tailscale <tailscale-ip>)
- Battery driver: charge-limit query works on hardware ("charge limit 100% (off)"), so the mailbox command 0xE9 path is confirmed.
- Keyboard backlight: the LED works (writing brightness 1 lights it); it boots at 0. Fn+F9 FIXED, confirmed on hardware:
  - Fn+F9 is NOT Ctrl+Win+F24 (that guess was wrong; an F24 input filter saw nothing). A hidraw capture shows each press is
    vendor report 7 (usage page 0xFF00) = `07 65 6e 65 00 bf` ("ene", 0, 0xBF), press only, no release. hid-generic maps
    nothing for page 0xFF00, so evdev never sees it. (Another press seen: `02 0a 00 72` = Shift+Win+F23, the Copilot-style chord.)
  - samsung_galaxybook_kbd now also registers a HID driver for i2c-hid 0CF2:9050 (hid_parse + hid_hw_start default, so the
    keyboard is unchanged) whose raw_event catches report 7 / 0xBF and steps the LED 0-1-2-3-0, with
    brightness_hw_changed for the GNOME OSD. Other vendor codes go to hid_dbg.
  - levels now defaults to on (max_brightness 3); levels 1-2 are refreshed every refresh_low_ms (250 ms), level 3 every
    refresh_ms (1000 ms). User confirmed all levels cycle and hold ("working perfectly").
  - Capture tools: scratchpad hidlog.py (all hidraw) and keylog.py (evdev) -> /tmp/hidlog.txt, /tmp/keylog.txt on the laptop.
- Camera: the camera dtsi include is still commented out (the -5 hang), so there are no camss/cci nodes. Not tested yet.
- Audio: no card.
  - ADSP running; qcom-apm "CMD timeout for [1001021]" (APM_CMD_GET_SPF_STATE).
  - Then wcd938x set_jack -22. kprobe shows wcd_mbhc_start(mbhc=NULL).
  - wcd938x_soc_codec_probe is never called. It is deterministic: rebinding and reloading the module give the same result.
  - Test module build/wcdtest (set_jack returns -ENOTSUPP when mbhc is NULL) gets past the jack.
    The card then fails to add all 12 routes (no component widgets exist) and silently doesn't register.
    So ASoC never probes the link components at all on 7.4-rc2. omarchy's 7.3 works on the 14", and the -4 build had the same failure.
  - ROOT CAUSE FOUND (7.4-rc2 regression, not board-specific): soc_new_pcm_runtime() allocates the rtd with
    devm_kzalloc_flex(), which sets the __counted_by counter rtd->num_components to the array size (kprobe: 20/10/10/6).
    snd_soc_rtd_add_component() then appends at num_components, so slots 0..N-1 stay NULL, for_each_rtd_components()
    stops at slot 0, snd_soc_component_probe() is never called (kprobe: zero hits), no component widgets -> every route
    fails, set_jack sees mbhc NULL, card never registers. Fix: patches/sb4edge-local/0009-asoc-rtd-num-components.patch
    (rtd->num_components = 0 after the allocation). Applied to the sb4-src tree; kernel rebuilt as 7.4rc2-8.
  - The APM "CMD timeout [1001021]" and the sdw runtime-PM message were red herrings (or secondary).
  - Live test failed for unrelated reasons: hot-unloading the audio stack left q6prm deferred, and restarting the ADSP
    (remoteproc0 stop/start) oopsed in glink smem register; ADSP offline until reboot. Don't do that again: test by reboot.
- Keyboard light OSD: GNOME 50 shows it via UPower BrightnessChangedWithSource("internal") on the legacy
  /org/freedesktop/UPower/KbdBacklight path -> gsd-power -> gsd-media-keys ShowOSD. Verified with a uhid fake keyboard
  (scratchpad fakefn.py sends report 7 / 0xBF). It only failed live because UPower and gsd-power cached the old LED
  (max 1) from before the module reload; after restarting both, the OSD showed 0.33/0.67/1/0. Fresh boot is fine.
- Mistake: I ran dmesg -C on the laptop while setting up the key capture, so the boot log is gone (relevant lines are quoted above).

## Build in progress 2026-11-14 ~19:15 EST: kernel 7.4rc2-8 (+0009 ASoC fix) + camera test boot entry
- build-kernel.sh KDEB_PKGVERSION 7.4rc2-8; chain: build-kernel.sh -> scripts-build-dtbo.sh -> remaster.sh.
- remaster.sh now also builds /casper/vmlinuz-sb4edge-camera: same kernel, stubble-wrapped with the base DTB +
  dtbo/camera.dtbo merged by fdtoverlay (fails the build if ov02c10 is missing). overlay/grub.cfg gets a 4th entry
  "camera test" (verbose); the default entries stay camera-free, so a camera hang costs one reboot.
- Previous ISO b602465e… (kbd Fn+F9 fix, -7 kernel) is the one in apps/ until this finishes.

## Hardware run of ISO dc226ab4 (kernel 7.4rc2-8), 2026-11-14 evening, Tailscale <tailscale-ip>
- AUDIO WORKS (patch 0009 confirmed): card X1E80100-GalaxyBook4Edge, headset jack input registered.
- Keyboard light + Fn+F9 work. Regression found and fixed: the module's HID driver did not set HID_QUIRK_INPUT_PER_APP
  (hid-generic sets it before hid_parse), so all collections were merged into one input device; typing and the Fn
  brightness/volume keys broke. With the quirk the keyboard splits into "Keyboard" + "Wireless Radio Control" again;
  user confirmed the keyboard is fully working (loaded live). ISO rebuilt with it.
- Camera test entry is the 3rd GRUB entry. Not tested yet.

## Camera test boot (3rd entry, ISO 00f6964e), 2026-11-14 ~23:15 EST, Tailscale <tailscale-ip>
- Camera nodes boot fine (no hang): camss + cci + ov02c10 probe, PipeWire "Built-in Front Camera", ~32 fps at 1080p.
- Magenta image FIXED (libcamera bug): 0.7's CPU debayer applies AWB gains / combined CCM to raw values including
  the pedestal and subtracts the black level afterwards in the gamma table, so the pedestal is scaled by the R/B gains
  (stats/AWB subtract it first). extra/libcamera/0002-software-isp-subtract-black-level-before-gains.patch subtracts it
  in the lookup tables before gains/CCM (gamma table starts at 0). Measured R/G/B 89/58/95 -> 63/67/58, natural frame.
  Rebuilt out/libcamera (same version string +sb4edge1); installed live. blackLevel 4096 in the tuning is correct.
- Recording freeze: NOT the camera/encoder (pipewiresrc -> vp8enc realtime = 32.5 fps, queue empty). The internal mic
  delivers 0 buffers: q6apm "DSP returned error[1001002]" / "Failed to start APM port 110" on VA_CODEC_DMA_TX_0
  (MultiMedia4 Capture). Snapshot's recording waits for audio. Stopgap: overlay/camera/90-sb4edge-snapshot.gschema.override
  (enable-audio-recording=false). MIC IS THE NEXT AUDIO BUG.
- WebM quality: Snapshot's VP8 "Profile Realtime" preset leaves vp8enc at 256 kbit/s. remaster.sh diverts
  GstVP8Enc.prs and adds target-bitrate=8000000/threads=4/vbr (measured 8.05 Mbit/s, 32.6 fps).
- apt upgrade error: kdump-tools postinst hook can't build an initrd on the live root (harmless; purged live). Real ISO
  bug: dpkgstatus.py merge marked dracut "installed" in the live layer (which removes it) -> missing .list warnings.
  merge now takes the lower layer's before-status and skips packages the layer removed.
- Keyboard light idle-dim flicker (GNOME dims to level 1): EC holds level 1 (GET polls stay 1, byte 2 just echoes);
  suspect the 250 ms re-send restarts the LED fade. /tmp/kbdtest.py on the laptop (phases A-E) awaiting user's report.
- Idle-dim flicker RESOLVED (pending final confirm): user tests: level 1 re-sent every 250 ms flickers from the start
  (timeout byte 0x00 or 0xFF alike); re-sent every 1 s steady; sent once steady (75 s). Level 3 sent once flickers/goes
  off, so a keepalive is still needed. First try (all levels at 1 s): user saw levels 1-2 still flicker, 0 and 3 steady.
  Second try (keepalive only at level 3, others sent once with byte 0): levels 1-2 fade within 1 s.
  => byte 2 of SET is the EC light-off TIMEOUT: 0 = fade at once (hence OpenBSD's 1 s keepalive), 0xff = stay lit
  (test Z). Module now: timeout param default 0xff, sent once per change, no keepalive (timeout=0 restores it).

## Keyboard backlight: solved with the EC mailbox (2026-11-15)
- The 0x62 command { 0x10, timeout, level } (OpenBSD samsabi 1.1, EC2 IOCTL_SET_KBDBLT 0x3003C) cannot hold levels 1-2:
  any single SET makes the EC pulse/fade the light by itself; a 1 s keepalive only holds level 3 (OpenBSD forces 3 for this reason).
- Windows (Samsung.Firmware.dll SetKbdBacklit/GetKbdBacklit) uses EC2 IOCTL 0x30800 = SecEne9058KbcSendExCmdFull:
  mailbox command 0xFD (1 byte in: level) / 0xFC (1 byte out), on the EC's 0x64 port (ECTC _CRS: 0x62 on I2C6, 0x64 on I2C1;
  Linux i2c-5 5-0064, the battery driver's device). EC2's command table at .data 0x14000C5A0: {cmd, nIn, nOut, flags}.
- User test via /tmp/ecmbox.py (scratchpad copy): levels 1/2/3 steady with one command, no refresh; 0 fades out (EC animation).
- Implementation: battery driver exports sgb_ec_excmd() (shared lock + slot protocol); kbd module sends 0xFD/0xFC through it,
  no keepalive, no timeout/refresh params; depends on samsung_galaxybook_battery. scripts-build-dtbo.sh builds battery first and
  passes KBUILD_EXTRA_SYMBOLS for kbd. Installed live in /lib/modules/7.4.0-rc2-sb4edge/updates (depmod done).

## Internal microphones: fixed (2026-11-15)
- Cause of "DSP returned error[1001002]" / "Failed to start APM port 110" (VA_CODEC_DMA_TX_0): the topology's VA capture graph
  only starts with 4 channels (hw:0,3 offers 2 or 4); PipeWire opened it as stereo. arecord -c4 works.
- Mics: DMIC0 + DMIC1 (data line 0, decimators 0/1 -> slots 0/1). DMIC2-7 give digital silence (no mics). Both mics hear a
  440 Hz speaker tone at the same level.
- DMIC clock: the DT had 4.8 MHz; DMIC0 then captures broadband noise at about -16 dBFS. At 2.4 MHz (poked live through /dev/mem,
  VA CDC_VA_TOP_CSR_DMIC0_CTL clk_sel = div4) both idle at -68 dBFS. Matches ciscobugger's 15.6" DTS comment.
- Fixes: patches/sb4edge-local/0010-dmic-2p4mhz.patch (qcom,dmic-sample-rate = <2400000>, kernel deb 7.4rc2-9);
  overlay/audio/51-sb4edge-mic.conf (WirePlumber: mic node 4 channels, positions FL FR AUX0 AUX1, so mono/stereo apps get the
  two real mics). Snapshot's enable-audio-recording=false override removed (overlay/camera/90-sb4edge-snapshot.gschema.override deleted).
- "failed to load gen70500_sqe.fw" at boot: the initramfs probe missed it and the GPU only loaded sqe + GMU v4.3.17 after
  the switch to the real root. Since 2026-11-18 overlay/sb4edge-gpu-dracut.conf puts both into the initramfs.

## Performance modes: Quiet / Optimized / Performance (2026-11-15)

Windows: Samsung Settings (SamsungSystemSupportEngine.exe ModulePerformanceModeV2) sends SABI
{'CX', SASB 0x91, GUID 8246028d-…, FNCN 0x51, SUBN 3, mode}. DSDT `\_SB.SCAI` PRF3 handles it: modes
0x02 AUTO (Optimized), 0x0A SILENT (Quiet), 0x15 MAXPERF (Performance); each rewrites the TZ31/32/33/35
_PSV/_MTL trip points (Windows thermal framework only) and sends EC mailbox command
`0xEE {0x80, m}` with m = 0x00 / 0x0A / 0x15 (CMDD -> ECTC.ECMD = the EXCM mailbox; EC echoes the 2 bytes).
Quiet: passive trip 57 -> 54 °C, min throttle 64%. Performance: throttle floor 64 -> 79% (clusters).

Linux:
- patches/sb4edge-local/0011: platform_profile loads on a DT boot (creates /sys/firmware/acpi). Applied in
  the sb4-src tree; until the kernel deb is rebuilt, out/platform_profile.ko ships in updates/ (remaster.sh).
- samsung_galaxybook_kbd registers platform_profile "samsung-galaxybook" (quiet/balanced/performance) and
  sends 0xEE through sgb_ec_excmd (probe: balanced; resent on resume). power-profiles-daemon 0.30 picks it up
  -> GNOME Power Mode: Power Saver = Quiet, Balanced = Optimized, Performance = Performance.
- sb4edge-fan (now enabled by default) reads the profile: per-mode fan curves, and Quiet caps all
  cpufreq policies at 2.5152 GHz. Verified live: profile switch -> EC echo, cap applied/restored, curve swapped.
- Over SSH, powerprofilesctl needs sudo (polkit); the GNOME session is authorized.
- Not verified: an audible effect of 0xEE itself on the EC (no fan tach readable); the fan is still driven by
  sb4edge-fan's 0x17 writes.
- CPU boost: /sys/devices/system/cpu/cpufreq/boost is 0 by default, capping all cores at 3.8 GHz (clusters
  1/2 have a 4.2048 GHz SCMI boost OPP). sb4edge-fan turns boost on at start and writes a large scaling_max
  (kernel clamps) outside Quiet. Geekbench Linux before the fix: 2769 / 14372 (Windows ~2900 / 15000).
- GPU (Geekbench Vulkan 5120): Face Detection (workload 303) fails validation on Mesa 26.0.8 turnip -> 0,
  dragging the score; GPU reaches 1.5 GHz, devfreq governor makes no difference. Windows results are OpenCL.

## Kernel 7.4rc2-10 + ISO f60311ad (2026-11-15)
- 0012: camera dtsi included in the board DT (identical to the dtbo verified on hardware). Camera now in the deb DTB:
  live default entry and installed systems. remaster.sh requires ovti,ov02c10 in the DTB; camera-test entry and the
  vmlinuz-sb4edge-camera build are gone. grub.cfg has ONE entry (plus next volume / firmware settings).
- 0011 (platform_profile without ACPI) is in the deb now; the out/platform_profile.ko override was removed.
- CPU boost: schedutil never selects the 4.2 GHz boost OPP (0 s under a pinned busy loop, even after boost=1 and a CPU
  replug); the "performance" governor does (Geekbench: ~250 s at 4.2 GHz on policy4/8). sb4edge-fan sets the
  performance governor in Performance mode, schedutil otherwise. Geekbench CPU with boost=1 + schedutil: 2791 / 14031.

## Camera quality + mic level (2026-11-15, ISO after f60311ad)
- Snapshot 50 records MP4/H.264 when openh264enc exists (else WebM/VP8 at ~600 kbit/s despite the VP8 preset):
  remaster installs gstreamer1.0-plugins-bad + libopenh264-8. Measured: 1080p H.264 ~1.95 Mbit/s, MP3 audio.
- Mic: speech was -54 dBFS RMS over a -64 floor. UCM HiFi.conf now inlines the va-macro DMIC0/1 enable sequences with
  VA_DEC0/1 Volume 116 (+32 dB; a later EnableSequence does not override an included one). Speech peaks ~-24 dBFS.
- Hiss at that gain (DMIC self-noise, floor ~-51 dBFS): overlay/audio/60-sb4edge-mic-ns.conf = PipeWire
  echo-cancel (WebRTC NS + HPF + AEC, monitor.mode, mono) "Microphone (noise suppression)", default input. Hiss
  (3-20 kHz) ~15 dB lower; user: "still there, but much better". No NS level knob in PipeWire 1.6's webrtc plugin.
- DMIC clock 3.2 MHz (clk_sel 1) tested live: hiss not lower than 2.4 MHz. Stays 2.4 MHz.

## Geekbench 6.7.1 CPU, Performance mode (performance governor, boost 4.2 GHz), 2026-11-15
- 19475510 (02:08): 2841 / 15115. 19475577 (02:36): 3013 / 14853.
- Before: 2769 / 14372 (no boost), 2791 / 14031 (boost + schedutil). Single-core +9%, multi +3-5%: Windows-class numbers.

## Kernel 7.4rc2-11/-12: mic 2 ch + module cfg blobs, SD card (2026-11-15)
- 0013-va-4ch-module-cfg-blob.patch (-11): VA_CODEC_DMA_TX_0 BE fixed at 4 ch, so 2-ch (and 4-ch) capture works;
  audioreach sends topology module cfg blobs (for Fluence, see fluence/NOTES.md). Verified live (2-ch arecord).
- 0014-sdcard-16.patch (-12): sdhc_2 + card detect gpio71 in the 16" DTS. Verified with dtbo/sdcard.dtbo through
  sb4_dtbo: "mmc0: new UHS-I speed SDR104 SDHC card", 32 GB card read. remaster.sh checks the DTB for it.
- ISO 7acba1a8 (-11) was published but superseded before flashing; -12 build follows.
- Mac: Tailscale accept-routes made <lan-ip> go through utun6 (<home server> subnet route); LAN SSH then fails
  intermittently. Laptop LAN IP changes per boot (.70, .52).

## 2026-11-15: -12 on hardware
- SD card (0014, no overlay): card hot-inserted at 242 s initialised at SDR104, then every read timed out ("Timeout waiting
  for hardware interrupt", re-init -110). After the owner reseated the card: SDR104 again, 256 MiB direct read at 58 MB/s,
  filesystems visible. So a bad contact on insert, not the DT. Watch for it recurring.
- Fluence with Samsung calibration (m070010d9-cal.bin, 2 ch) works on -12: no SET_CFG errors, DSP fetched
  fluence_nn_module_fvxiii.so.1, idle floor -34/-40 -> -50/-52 dBFS. Harness now kept in fluence/harness
  (try.sh, restore.sh, lvl.py, ab.sh = guided A/B with playback). Laptop reachable on Tailscale <tailscale-ip> this boot.

## 2026-11-15: Fluence default mic + rEFInd boot menu
- Fluence: "Microphone (Fluence)" default (fluence/NOTES.md, last two sections). ISO built 05:31 (published, not
  flashed: superseded by the rEFInd build).
- rEFInd (refind/): The owner wants rEFInd everywhere (live + installed), modern theme, Ubuntu + Windows tiles.
  Theme generated from SVG (refind/theme/make-theme.py + build-theme.sh in sb4build, preview.py -> preview.png).
  Live: remaster builds a new 16 MiB efi.img: EFI/boot/bootaa64.efi = rEFInd 0.14.2 (Ubuntu refind deb in refind/),
  grubaa64.efi from Ubuntu's image (launched directly, no shim; Secure Boot is off), refind.conf = refind-live.conf.
  GRUB is kept in the chain for cutmem; live grub.cfg menu hidden (timeout 1, Esc shows it).
  Installed: /usr/lib/sb4edge/refind + sb4edge-refind.service (every boot, skipped when /rofs exists) copies rEFInd to
  /boot/efi/EFI/refind, creates/keeps the "rEFInd" NVRAM entry first, sets grub2/update_nvram=false;
  /etc/default/grub.d/zz-sb4edge-refind.cfg hides GRUB and disables os-prober.
  Windows tile: volume "EFI system partition" (sda2, label SYSTEM) \EFI\Microsoft\Boot\bootmgfw.efi.
- Internal disk is sda (UFS): sda2 ESP 260M (156M free), sda4 BitLocker C: 937G. Secure Boot off.
  The owner chose internal install: he shrinks C: in Windows Disk Management; never touch partitions from Linux.
  BitLocker with Secure Boot off measures the boot path (PCR4): booting Windows via rEFInd will ask for the recovery
  key once; reseal from Windows with `manage-bde -protectors -disable C: -RebootCount 1` and reboot via rEFInd.
- rEFInd -> Ubuntu's signed ISO GRUB printed "error: file '/boot/' not found." (from its built-in early config,
  before grub.cfg; non-fatal, also through shim) and rEFInd showed its text "Booting OS" banner. Fixed for a clean
  screen: refind/build-grub.sh builds our own GRUB (grub-mkimage, silent early config grub-live-early.cfg) used as
  EFI/boot/grubaa64.efi on the live ESP; rEFInd entries have "ostype ..." + "graphics on"; live grub.cfg quotes
  "$lockdown" (unset in our GRUB). Verified in QEMU (test/rf/shots.sh, timed screenshots; serial.log has the console).

## 2026-11-15 night: installed system fixes, charging, VRR (kernel 7.4rc2-13)

- GRUB on the installed system: ubuntu-x1e-settings.cfg (grub.d) re-enabled os-prober, which forced a 10 s menu
  when it found Windows. Our override is now refind/zz-sb4edge-refind.cfg (sorts last). GRUB_RECORDFAIL_TIMEOUT=0.
- Battery: qcom_battmgr was still loaded from the initramfs (installed system uses dracut, which ignored the
  modprobe.d blacklist): overlay/sb4edge-battery-dracut.conf -> /etc/dracut.conf.d. (Writing files through
  `printf pw | sudo -S tee` feeds the password to tee's stdin too: copy files over and `sudo install` them.)
- Charging after a replug: needs sb4edge-usbc (S2MM006 waits for the host to close the input switch, as
  EmuEc.sys does on Windows). Now enabled by default in remaster.sh; verified: "charger attached, input switch on",
  20 V/3 A. tqftpserv was a wrong guess (the ADSP has no PMIC_RTR_ADSP_APPS channel; charging is EC/PDIC based).
- Display: display/make-edid.py adds a 60 Hz DTD (vtotal doubled) to the panel EDID -> drm.edid_firmware (file in
  the initramfs via overlay/sb4edge-edid-dracut.conf). msm PSR (msm.psr_enabled=1) blanks/flickers on X1E
  ("driver disabled vblank in self-refresh", frame done timeouts): not used.
- VRR: patches/sb4edge-local/0015-msm-vrr-avr.patch drives the DPU INTF AVR registers (downstream Qsync's
  avr_setup/ctrl/trigger) on eDP, sets DP_MSA_TIMING_PAR_IGNORE_EN, attaches vrr_capable (DPCD 0x007 bit 6 +
  EDID 48-120 Hz) and clamps the scanout position in the extended porch. msm.vrr=3 (overlay/sb4edge-grub.cfg):
  AVR always on, because GNOME 50 only sets VRR_ENABLED for fullscreen windows. Measured with
  display/test/vblank-rate.py: idle desktop 48.6 Hz, moving 120 Hz; the owner: "everything feels smooth".
  The 60/120 Hz AC/battery switcher (display/sb4edge-refresh) is no longer installed.
  Laptop: patched msm.ko is in /lib/modules/$KVER/updates until the 7.4rc2-13 kernel deb is installed (then
  remove updates/msm.ko.zst, depmod, dracut -f).

## 2026-11-15 afternoon: rEFInd USB entry, Windows (BitLocker/NTFS) access

- rEFInd (installed): `scanfor manual,external,internal`; internal ESP excluded (`dont_scan_volumes LRS_ESP,SYSTEM,
  "EFI system partition"`; this token has no "+" mode, unlike `dont_scan_files`). Sticks/SD cards get the USB tile
  (os_unknown etc.) with the `vol_external` badge. Our live stick's ESP is now labelled SB4EDGE and has
  `EFI/boot/sb4live.efi` (copy of the live GRUB), so rEFInd boots it directly instead of the stick's own rEFInd.
  QEMU test: test/rf-usb (GPT images needed: superfloppy images all share a zero PARTUUID and rEFInd's default
  dont_scan_dirs `<self GUID>:EFI\boot` then hides every stick).
- BitLocker: cryptsetup 2.8.4 rejected C: ("Unexpected metadata entry value '36'": new 12-byte entry in the
  clear-key VMK). patches/cryptsetup + build-cryptsetup.sh -> out/cryptsetup (2.8.4-1ubuntu4+sb4edge1, held).
  C: currently has a clear-key VMK (BitLocker suspended / device encryption not bound), so
  windows/sb4edge-windows-unlock(.service) opens it at boot as /dev/mapper/bitlk-sda4. udisks uses ntfs-3g only
  (windows/mount_options.conf) because ntfs3 would mount a hibernated (Fast Startup) volume read-write.
- Installed on sda7 from the live session: new rEFInd conf/theme in /usr/lib/sb4edge/refind (copied to the ESP by
  sb4edge-refind.service at boot), patched cryptsetup (held), windows unlock service, udisks config.
- Resources (GNOME system monitor) showed an unnamed GPU page with no data: the msm card is a platform device.
  patches/resources/msm-gpu.patch (new src/utils/gpu/msm.rs; msm fdinfo in process_data) + build-resources.sh ->
  out/resources (1.10.2-0ubuntu3.1+sb4edge1, held via remaster). Verified on the 16" from a temp extract
  (dbus-run-session, since the user's instance owns the app id): "Qualcomm Adreno X1-85", usage ~22% at 300 MHz,
  48 °C, 1.5 of 15.5 GB shared memory.
- HDMI: Realtek RTD2171 DP->HDMI bridge (simple-bridge, bound) on DP3; HDMI-A-1, DP-1, DP-2 connectors exist.
  Not yet tested with a display. USB: all three controllers have SuperSpeed root hubs (10 Gb/s); a device present
  at boot stays at USB 2.0 by design (sb4edge-usbc), replug for SuperSpeed.
- HDMI + Samsung Odyssey G95NC (57", EDID in display/g9): the RTD2171 converter's DPCD lists only 5.4 Gbit/s
  (MAX_LINK_RATE 0, SUPPORTED_LINK_RATES = 0x6978), link HBR2 x4, so HBR3 via DT link-frequencies is pointless.
  Max over HDMI: 5120x1440@60 / 3840x1080@120 from the EDID. Added 5120x1440@75 (monitor's own 60 Hz timing,
  faster pixel clock): display/g9/make-g9-edid.py + sb4edge-hdmi-edid (udev 66-...rules, debugfs
  edid_override, "reset" must be written without newline). Mutter only re-reads modes on a real replug.
  90 Hz was garbled on the 57": the converter's HDMI side is TMDS only (<= 600 MHz; the monitor's TMDS limit too).
  Now 75 Hz (586.47 MHz). Not yet confirmed on the monitor.
- USB-C SuperSpeed on the 16" does NOT work (never verified before): with orientation + USB mode set by
  sb4edge-usbc/gb4e_typec, the RTL9210 SSD still enumerates on the HS bus. DP alt mode: adapter only shows its
  billboard device; nothing negotiates DP with the S2MM006 (also missing on omarchy's 14").

## 2026-11-15: USB-C DisplayPort alt mode, kernel 7.4rc2-14, stick boots GRUB
- EmuEC.sys RE (research/emuec/): the S2MM006 runs DP discovery/enter/configure itself once the host allows it:
  0x50 bit0 StartAlt, bit1 ContinueAlt (after Discover Mode DP), pin to 0x51 bits0-2 (1 A, 2 C, 3 D, 4 E, 5 B, 6 F);
  progress in 0x1A|0x57<<8 (write 0 to clear), replies at 0x0A40/0A60/0AC0/0AE0/0AA0. Implemented in extra/usbc/usbc.c
  (prefers pin C, 4 lanes; `sb4edge-usbc --dump` prints the registers). Verified on the 16": DisplayPort partner found,
  pin C, Configure ACK, HPD 1.
- patches/sb4edge-local/0016: pmic_glink_altmode `inject` sysfs file (mux/retimer/HPD bridge from userspace; the ADSP
  never sends altmode notifications here). 0017: mdss_dp0/1_out data-lanes <0 1 2 3>. Both in kernel 7.4rc2-14.
- Lesson: never leave a vmlinuz-* copy in /boot during a kernel install: update-grub made it the default entry, and
  moving it away left GRUB booting a missing file (internal Ubuntu did not boot; fixed with update-grub in a chroot
  from the live stick). Backup is at /var/backups/sb4edge/.
- Live stick EFI: GRUB (refind/grubaa64-live.efi) is EFI/boot/bootaa64.efi and sb4live.efi; rEFInd only on the internal
  disk (remaster.sh changed; the attached stick was converted in place and its ESP relabelled SB4EDGE).

### 2026-11-15: USB-C DisplayPort paused
Paused at the owner's request (no USB-C→DP cable to test full modes). State: the S2MM006 helper negotiates DP alt mode
(pin C, Configure ACK, HPD via the patched `inject` sysfs), DP-2 reports connected, but msm's EDID read fails behind
the USB-C→HDMI adapter (raw 8-byte I2C read OK, sink count 1; drm_edid_read_ddc NULL; prepare -107, so 640x480).
Debug msm (build/altmode/msm-dbg2.ko, logs full 128-byte block reads) was built but never ran; the laptop now runs the
stock -14 msm again (debug copy in /var/backups/sb4edge/). 0018 is in the sb4-src tree but unverified.
Windows qcdxkm8380.sys: logging stripped; AUX diag escape at sub_140115C40 calls the AUX transfer sub_1400F2FE8.

### 2026-11-15: USB-C SuperSpeed investigation (Windows RE)
- Windows programs the PS8830 from qcusbcucsi8380.sys (Qualcomm UCSI driver), not EmuEC.sys. EmuEC's Retimer/Dpmux/Redrive
  "Phy" registry values are factory tuning that it only stores in UEFI variables. Decompile: research/ucsi-decomp/.
- PS8830 in qcusbcucsi (retimer type 2, sub_140021448/sub_140027B78): on first use URS GPIO index 5 (the reset) goes low, 15 ms,
  high, 60 ms; then three single-byte writes to regs 0x00/0x01/0x02 from tables at 0x14002F050..F368:
  init 01/00/00, USB3 21/00/00 (reversed 23), DP4 01|03/85/00, DP+USB 21|23/85/00, USB4/TBT 0x05/0x07 with r02 01/11/80/90.
  This is the same thing the Linux ps883x driver writes. On the laptop both retimers read r0=0x21 with the drive at 480M.
  GPIO indices 1-4 are SBU-mux pins (sub_140021088); nothing else touches the SS lanes.
- UCS0_NX16.bin (qcusbcucsi ext) is a PEP power-resource file; regulators/clocks/RF_CLK3/4 match our DT.
- Bug found: switching port 0's combo PHY from DP back to USB3 fails ("fd5000.phy: phy initialization timed-out" plus
  clk_core_disable/unprepare WARNs from qmp_combo_com_exit in qmp_combo_reconfigure_phy), which leaves USB3 dead until
  reboot. Earlier boots had no timeout and still no SuperSpeed, so this is a second bug, not the root cause.
- Next: clean boot (no DP adapter), drive plugged after boot, then read xhci portsc + qmp-combo dynamic debug (needs root).

### 2026-11-15 (evening): USB-C SuperSpeed solved, brightness kept across boots

- **The earlier cables were USB 2.0-only.** With a Thunderbolt 5 cable, Windows shows SuperSpeed + UAS on both
  ports (V2 flags 0xB), and so does Linux on a hot-plug: 5000M, uas, both orientations, both ports. The RTL9201
  enclosure is 5 Gbit/s only. All earlier RxDetect results on port 0 came from those cables.
- **The real Linux bug:** a device already plugged in at boot. sb4edge-usbc left ports powered at start alone, so
  the retimer never got an orientation and the device stayed at 480M. Fix in extra/usbc/usbc.c: at start, a powered
  port (not in DP mode, 0x56 == 0) gets VBUS off once and attaches again through step(), which sets the
  orientation. It is skipped when a filesystem is mounted from a disk behind that port's controller (port 0:
  a600000.usb, port 1: a800000.usb; checked through /proc/self/mountinfo), so the live stick keeps power.
  Tested by restarting the service with the drive on port 1: unmounted, it went to 5000M within 1 s; mounted, it
  was left alone. Installed on the laptop; out/sb4edge-usbc rebuilt (sb4build, gcc -O2 -Wall, no warnings).
- **S2MM006 0x12 while we power a port:** bits 3:2 hold the CC pin (0x08 reverse, 0x05 normal). Bits 1:0 only
  while a partner waits. Not used yet; the VBUS cycle does not need it.
- **Panel brightness** (overlay/backlight, in remaster.sh): at shutdown GDM's greeter mutter sets the brightness it
  cached at boot, then systemd-backlight saves it, so every boot started at 628/2047. sb4edge-backlight.service
  records the value while an unlocked, non-idle user session is active (in /var/lib/sb4edge/backlight); a
  systemd-backlight@ drop-in (ExecStopPost) writes it over systemd's save. Installed; confirmed by a reboot only
  once one has happened.
- **Still open:** the qmp-combo DP→USB reconfigure timeout (clk imbalance in qmp_combo_com_exit); kernel -15 not
  installed; ISO not rebuilt.

### 2026-11-15 (night): keyboard backlight memory, rEFInd Windows, USB-A, ambient light sensor

- **Brightness memory, real cause:** the greeter's idle dim (idle-brightness 30% = 628/2047) carried into the
  session. overlay/backlight/95-sb4edge-greeter (`idle-dim=false` for GDM, /usr/share/gdm/dconf) fixes it. The
  saver now also records the keyboard backlight (leds:*::kbd_backlight, 0 allowed). Verified after a reboot:
  panel 1822, keyboard 2.
- **rEFInd:** Windows failed from rEFInd because the installed config's `volume` line did not match. Removed from
  refind-installed.conf (live config uses `volume SYSTEM`). Windows booted with the 860 EVO attached.
- **USB-A** (a400000.usb, bus 7): SuperSpeed works (the 2 TB disk enumerated at 5000M).
- **Ambient light sensor: working.** VEML3328 on the ADSP sensor island (SSC I2C 7, addr 0x10), powered by
  LDO15_B 1.8 V (on already). Chain:
  - The ADSP sensors domain reads `/vendor/etc/sensors/sns_reg_config` (fixed path) and needs a WRITABLE registry:
    with hexagonrpcd 0.4.0 (read-only) it gets `Tried to open .../registry/DIR for writing`, asserts in
    sns_registry_sensor.c:279, the ADSP crashes and TrustZone resets the whole laptop (it boot-looped at the login
    screen until hexagonrpcd was masked from the live USB). hexagonrpcd stays masked.
  - sb4edge-sensors.service runs Qualcomm's adsprpcd (the Fluence build) as `adsprpcd sensorspd adsp`, which has
    full apps_std (writes, mkdir, rename). /vendor -> /var/lib/sb4edge/vendor (tmpfiles.d). sb4edge-sensors-setup
    refreshes etc/sensors/{sns_reg_config,config,socinfo} from /usr/share/qcom/x1e80100/Samsung/galaxy-book4-edge-16
    (Unix line endings: a trailing CR became part of a path; config mtimes set to @1719256666, the value the
    registry records, so it is not rebuilt) and seeds persist/sensors/registry/registry from the Windows copy once.
  - It must run from boot: started later, the sensor drivers had already probed without a registry.
  - The light sensor's SSC data type is **"color"** (not "ambient_light"/"rgb"): attributes name veml3328, vendor
    vishay_capella, 1 Hz continuous. Event floats: [0] lux, [1] CCT, [2] x, [3] y, [4..] raw. 3.2407 lux in the
    dim room = Windows' 3.24. Cover 0.8 lux, flashlight 1000+.
  - libssc v0.4.4 + patches/libssc (LIBSSC_LIGHT_DATA_TYPE override, value debug) and iio-sensor-proxy 3.9 (first
    release with SSC; Ubuntu ships 3.8) built by build-ssc.sh into out/ssc, installed in /usr/lib/sb4edge/ssc;
    iio-sensor-proxy drop-in (ExecStart, LIBSSC_LIGHT_DATA_TYPE=color, AF_QIPCRTR, waits for the sensor) and udev
    rule 81-sb4edge-ssc-light.rules (fastrpc-adsp -> ssc-light). Needs libprotobuf-c1.
  - GNOME 50 auto-brightness (gsd-power, ambient-enabled) works: covered 1470, flashlight 2047. gsd-power bug: if
    iio-sensor-proxy restarts, gsd keeps light_claimed set and never claims again until re-login.
  - Keyboard: sb4edge-kbd-ambient (user service, UPower KbdBacklight): off after 3 s above 100 lux, restored after
    3 s below 50 lux (Samsung's Windows thresholds). Verified. While it holds the keyboard off it leaves
    $XDG_RUNTIME_DIR/sb4edge-kbd-auto-off so sb4edge-backlight does not remember "off".
  - All in remaster.sh (overlay/sensors). Windows-derived files: sensors/qcom-root (registry, JSON configs) -
    publishing decision pending.
- Kernel: moving to v7.4-rc3 (rc2 tree state backed up in patches/rc2-tree-backup).
- **Kernel 7.4rc3-1** (v7.4-rc3 aebb72744764 + book4 commits + local patches; 0009 dropped, upstream has it).
  Installed on the laptop next to rc2 (held; modules in updates/; rc2 kept as fallback, its msm/altmode overrides
  stay rc2-only). Not booted yet.
- **ISO 9d544ca4** (rc3 kernel, light sensor, kbd rule, backlight memory, usbc VBUS cycle, rEFInd fix) in apps/;
  previous 9864eecc in apps/.../old. Flashed to the 128 GB SSD, readback sha256 verified, ejected.
- Publishing prep: .gitignore + scripts/check-secrets.sh; no repo yet.

## 2026-11-15 late: fingerprint, ISO 507060c8, release

- Fingerprint (EgisTec 1c7a:05a1, fw 9050.1.2.32): stock libfprint enrolls but the chip keeps nothing (list = 0
  after reopen; fprintd then deletes the print). Needs SDCP: libfprint MR !547 (head 2d7c5277). Our package
  extra/libfprint/build.sh (Ubuntu debian/, MR tree, TOD/doc packages dropped) + 0001 patch:
  - double free of the X509 verify param on the error path (crash),
  - the chip's model cert has issuer "Microsoft Cor\x00oration" (one byte zeroed); find the CA by AKI=SKI,
    restore 'p', require X509_verify with the CA key, then verify the CA chain.
  Installed on the laptop (held + /etc/apt/preferences.d/sb4edge-libfprint), enrolled right index via GNOME,
  survives reopen, lock-screen unlock = verify-match. pam-auth-update --enable fprintd (backup
  /var/backups/common-auth.pre-fprintd). libfprint-2-tod1 now orphaned (autoremovable).
- Software Updater error: /etc/apt/sources.list.d/crosspaste.sources pointed at http://localhost/crosspaste-fork;
  renamed to .disabled.
- remaster.sh: Tailscale removed; libfprint installed/held/pinned; fprintd PAM enabled.
- ISO sha256 507060c869d9…6508 in apps (previous 9d544ca4 in old/), flashed to the SSD, readback verified.
- GitHub: commit 1d20a1c; release v2026.11.15 with the ISO split in 3 parts (out/release).
- TODO: sudo-by-finger test confirmation; reboot + Windows boot persistence of the print.

## 2026-11-16: power tests, battery status, fingerprint relabel, brightness modes, Ubuntu 27.04

- Boot parameters: without `clk_ignore_unused pd_ignore_unused` xhci-hcd.4.auto fails to probe (-110) and idle
  power is not lower (5.12 W vs 4.99 W): both stay. `usbcore.autosuspend=-1` also kept.
- Idle power on battery, screen at 30 %: fingerprint reader USB autosuspend (udev, 2 s) 3.31-3.56 W vs 3.95-4.43 W,
  unlock unchanged -> made permanent (`overlay/63-sb4edge-usb-hub-pm.rules`). Wi-Fi PCI runtime PM: no change.
  60 Hz vs 120 Hz: negligible. power-saver profile: inconclusive.
- Suspend: s2idle only (`mem_sleep_default=s2idle`); `sb4edge-hdmi-sleep-guard` blocks sleep while an HDMI adapter
  is attached (unplugging it after sleep crashed the laptop) (`overlay/sleep`).
- Battery: with "Preserve battery health" GNOME showed the charging icon at the limit. EC B1ST bit 3 (ACPI _BST
  "charge limiting") was read as charging; now "Not charging" on AC unless a direction bit is set.
- Compared with ishashanknigam/Samsung-Galaxy-Book-4-Fingerprint-Ubuntu: kept this project's SDCP libfprint.
- Fingerprint relabel: Windows Hello prints carry no finger; `sb4edge-fingerprint-import --rename FROM TO USER`
  and a GNOME Settings patch (pencil button per print, pkexec, polkit `org.sb4edge.fingerprint-rename`).
  The separate "Fingerprint Labels" app was dropped.
- Light sensor location: centre of the top bezel (torch 250-320 lux vs 6-9 lux room).
- Automatic brightness modes (gsd + Settings patches, `ambient-mode` adjust|curve, `ambient-adjust-range`):
  slider 47 %, 25 lux: adjust 963, curve 705 (raw, max 2047). GNOME rebuilds on the installed system: an apt
  DPkg::Post-Invoke hook starts `sb4edge-gnome-rebuild@<pkg>` when Ubuntu updates gnome-control-center or
  gnome-settings-daemon (deb-src + quilt, version +sb4edgeN, patch-hash stamp).
- Ubuntu 27.04 "tenacious": no arm64 daily-live ISO exists (amd64 only), so the ISO is 26.10's with each squashfs
  layer dist-upgraded from ports.ubuntu.com. Build container = ubuntu:26.10 switched to tenacious (stonking-updates
  and -security kept: newer zlib/bzip2 builds there). Userland rebuilt for 27.04 (cryptsetup, Resources 51.0 with
  the msm GPU patch ported, libcamera, libfprint, libssc/iio-sensor-proxy, fastrpc, GNOME). The kernel tree's
  sign-file needs libcrypto.so.3 (gone in 27.04): kernel and modules use the 26.04 container (`docker/kernel`).
- rEFInd always selected Ubuntu (`default_selection Ubuntu`). Removed so it starts on the last OS booted; stored
  in EFI/refind/vars (use_nvram false). sb4edge-refind-install copies the new refind.conf at the next boot.
- Hardware video: Iris enabled (dtbo/iris.dts tested live with sb4_dtbo, then &iris in the board dtsi, kernel
  7.4rc3-2). qcvss8380.mbn from the qcdx8380 31.0.178.0 package. HW encode then decode of 1080p H.264 (650 fps,
  32 % CPU vs 398 % software, frames correct) and 4K HEVC (240 fps, 43 %). GStreamer ranks v4l2 decoders above
  avdec_*; ffmpeg has h264/hevc/vp9_v4l2m2m.
  After reboot on 7.4rc3-2: decoder/encoder probe at boot; VP9 1080p and AV1 720p decode verified once the test
  clips were 4:2:0 (4:4:4 = VP9 profile 1 / AV1 high: VP9 stalls in preroll, AV1 not-negotiated).
- Video benchmark (tools/video-bench.sh, AC power): see README "Hardware acceleration". Hardware encoders need NV12
  input (I420 from rawvideoparse fails to negotiate). GPU: OpenGL 4.6 / ES 3.2 / Vulkan 1.4 (Mesa 26.2.6 turnip).
- Touchscreen (Goodix 27C6:0123, i2c8 0x5d, hid-multitouch): 10 slots; live test registered 10 fingers at once.
  Touchpad 4D49:4150: 5 slots.
- After installing kernel 7.4rc3-2: battery, keyboard backlight (Fn+F9), performance modes gone. bindeb-pkg ships its
  own modules.dep, which overwrote the system's and left out updates/ (EC battery/kbd, gb4e_typec). Fixed with
  /etc/kernel/postinst.d/00-sb4edge-depmod (overlay/00-sb4edge-depmod); power-profiles-daemon and gsd-power must be
  restarted (or reboot) when platform_profile / the kbd LED appear late (ppd falls back to "placeholder", gsd-power
  logs "max > min" on every Fn+F9).
- Fingerprint: once (14:15, fprintd start) "fpi_sdcp_device_connect_complete: assertion 'priv->host_private_key'
  failed"; fprintd then held the claim and ignored SIGTERM (killed after 90 s); every later Claim was refused
  ("Device was already claimed"). Restarting fprintd fixed it. Not seen on earlier boots; cause unknown.
- Mesa 26.3.0 (built side by side in /opt, buildtype plain -O2, no LTO) vs Ubuntu's 26.2.6, glmark2/vkmark, two
  alternating rounds on AC: native 2880x1800 equal within noise (GL 974/961 vs 1037/835, Vulkan 4401/4271 vs
  4475/4313); 800x600 lower on 26.3 (GL 2227/1788 vs 1343/1406, Vulkan 22057/22859 vs 19275/22105). Same API
  versions (GL 4.6, ES 3.2, Vulkan 1.4; no Vulkan 1.5 yet). Kept Ubuntu's 26.2.6.
- Crash sweep on the installed laptop (2026-11-18, separate session that patched files in place); fixed here at the source:
  iio-sensor-proxy aborted twice with "client_vanished_cb: assertion failed: (ht)" when a client left while a client
  table was gone, leaving automatic brightness off until reboot: patches/iio-sensor-proxy skips missing tables (the
  laptop had a one-instruction binary patch), and the drop-in adds Restart=on-failure. sb4edge-fingerprint-import
  crashed at exit in libusb_unref_device (SIGBUS) during Python teardown, after its work was done: it now leaves with
  os._exit. make-g9-edid.py raised on EDIDs without the expected timings: it now exits with a message (the real G95NC
  EDID still produces g9-hdmi-75hz.edid byte for byte).
- NPU in Resources (2026-11-18): the Hexagon page showed no usage, and its only graph (temperature, autoscaled) looked
  like ~100 % load. Added extra/sb4-cdsp-stats: a read-only module that reads the CDSP SysMon record from SMEM
  (host 5, item 634) and gives load per mille of the clock vote. Idle reads 0; a FastRPC capability query briefly
  showed 16.8 %. First version returned ENODATA after boot: the load record (header 0x10100001) stays all zeros,
  timestamp included, until the DSP first runs something; a zero timestamp now reads as idle (0), as in Qualcomm's
  downstream driver. Resources: hexagon.rs reads the counter ("Compute DSP load" graph + sidebar meter), and the
  temperature graph is pinned to 0-100 °C after every point (add_unclamped_point() turns autoscaling back on, so
  setting it once at setup did nothing). Verified in an Xvfb render: sidebar "0 % · 39 °C", 40 °C at 40 % of the
  graph. No userspace can run work on the NPU yet (no libcdsprpc / QNN HTP; onnxruntime has no QNN provider).
- Log cleanup on the installed laptop (2026-11-17/18), errors repeated at every boot or login:
  - Ubuntu Dock: after an HDMI hotplug rebuilt the docks, handlers of the destroyed docks kept firing on every window
    move and workspace switch (~1300 "DashToDock ... has been already disposed" stack traces per 30 min, from
    theming.js). AppIndicators threw "SettingsManager.getDefault() is null" whenever the shell disabled extensions for
    the lock screen. overlay/gnome/sb4edge-dock-fix patches both, re-applied by an apt hook after every update of
    gnome-shell-ubuntu-extensions.
  - The PMIC RTC is read-only here: every boot started at 2024-07-05, systemd then raised the clock to its build date,
    and chrony's NTS handshakes failed ("certificate not yet valid") until the bootstrap server stepped the clock
    ~45 s in (46 days). fake-hwclock saves the time at shutdown and hourly and restores it in early boot.
  - alsa-base's "install snd" line failed at every boot inside the initramfs (busybox modprobe rejects
    --ignore-install/--use-blacklist; snd-ioctl32 does not exist on arm64 either): removed in remaster.sh.
  - 66-sb4edge-hdmi-edid.rules is copied into the initramfs, where its RUN script does not exist ("Failed to find and
    pin callout binary"): TEST== guard.
  - authd and USBGuard are not installed, but Ubuntu's defaults made every login/unlock log "PAM service gdm-authd
    was not found" and gsd-usb-protection "Failed to fetch USBGuard parameters": overlay/gnome/99_sb4edge.gschema.override.
  - libmalcontent-common ships D-Bus files for daemons that are not installed (their users do not exist; "Invalid
    user name" at every boot): removed and dpkg-excluded. brltty's udev rule (invalid line 611) is masked.
  - Not fixable here: the ChatGPT app polls a Codex "primary runtime" manifest that does not exist for linux-aarch64
    (404 about twice a minute); localsearch logs "Could not ask extractor to update" when the on-demand extractor is not running.
- Video playback/seeking (2026-11-18): GStreamer's playbin (Showtime, the Files previewer) decodes H.264 with
  v4l2h264dec on Iris. Seeking logged "UBSAN: array-index-out-of-bounds in .../iris/iris_buffer.c:869 index 32 is out
  of range for type 'iris_ts_metadata [32]'": iris_set_ts_metadata() wraps metadata_idx only on its next call, so
  iris_get_ts_metadata() can read tss[32]. patches/kernel/0005 wraps it right after the increment (mainline and
  linux-next still have the bug). The installed laptop got the same fix as an out-of-tree qcom-iris.ko in
  /lib/modules/$KVER/updates/ (delete it once a kernel built with 0005 is installed, or it shadows that kernel's module).
- sb4edge-fingerprint-import: the reader can vanish mid-read (suspend/shutdown, "g-usb-device-error-quark: device was
  disconnected"); the GLib error is now reported instead of leaving a crash report.
- Independent review (2026-11-18, of the 11c84de bundle and 32fd834), checked and fixed:
  - Wi-Fi: linux-firmware-qualcomm-wireless 20261110 has the 17cb:1107 board-id 255 entry itself, with the same
    data as our donor copy; ath12k-board2-add.py exited 1 ("entry already present") and stopped remaster.sh. Now it
    writes nothing and no override is installed; the update script removes the override on installed systems when
    Ubuntu's entry matches (no ath12k firmware in the initramfs, so no rebuild; effective at the next boot).
  - Fingerprint import gave every unknown chip print to the only Linux user: prints carry no owner (username,
    description empty; finger UNKNOWN), so another person's Windows Hello finger would unlock the account. A print
    is now bound only after a touch identifies it among the new prints (identify_sync; egismoc has IDENTIFY);
    boot/login only report. AUTO_IMPORT=yes in /etc/default/sb4edge-fingerprint keeps the touch-free import.
  - libfprint certificate fallback: now restores the byte only when the sequence occurs once, then runs the normal
    X509_verify_cert on the restored certificate (was: signature by key identifier, then only the CA's chain).
    Verified on the sensor: "model certificate verified once its zeroed issuer byte was restored".
  - sb4edge-fan read a missing CPU temperature as 0 °C (fan off). Now: top step until readings return (fixture test:
    85 °C 6000 rpm, no reading 8000, back at 40 °C 0, garbage 8000).
  - sb4edge-usbc: the "disk mounted behind the port" guard missed dm/md (LUKS, LVM) and swap; it follows slaves/ and
    loop backing files and reads /proc/swaps (fake-sysfs test: direct, LUKS, LVM-on-LUKS, none, unreadable).
  - test/qemu-test.sh always returned 0: now 0 only with graphical.target/GDM and no panic/emergency, 1 otherwise,
    2 when QEMU did not run to the timeout.
  - dpkgstatus.py ignored packages whose stanza disappeared below (none in the 27.04 build, but possible): recorded
    as null and dropped from upper layers that still carry the inherited stanza.
  - build-ssc.sh could skip a patch silently: builds from git archive of each tag, every patch must apply.
  - build.sh kept a partial base ISO: downloads to .part, checks Ubuntu's SHA-256, also checks the cached copy.
  - check-secrets.sh: fixed patterns case-sensitive (user words still any case), expected lines in
    scripts/check-secrets.allow; returns 0 on a clean tree.
- VA-API on Iris (2026-11-19): qcom-va-driver 1.1.0 failed every decode ("S_CTRL DISPLAY_DELAY (Iris decode-order
  patch required): Invalid argument"). Its kernel patches (radxa-pkg/qcom-va-driver patches/, GPL-2.0) are now
  patches/kernel/0006-0010; all stay inside drivers/media/platform/qcom/iris (module-only change). 0006 (decode order)
  was rebased: 7.4-rc3 has SLICE_MODE/SLICE_MAX_BYTES/SLICE_MAX_MB after TIME_DELTA_BASED_RC, so the new cap enum
  entries and the two switch cases go after them; no functional change. Built against the kernel tree (gcc 15.2,
  signed) with 0005 first; installed on the laptop as /lib/modules/$KVER/updates/qcom-iris.ko and reloaded.
  Before: 90/90 frames failed. After: 4K H.264/HEVC test clips 90/90 frames, no errors, framemd5 identical to
  libavcodec; 4K 40 Mbit/s H.264 73 fps, 1.2 CPU-s per 10 s (software 9.2). qcom-va-driver-tests: all pass except
  vpp-overlay (CDSP VPP disabled at build time); vpp-scaling/tonemap and prime-import need /dev/dma_heap/system
  (root-only). Citrix Workspace 26.08 arm64 cannot use it: its bundled libavcodec.so.62/libavutil.so.60 were
  configured with the *_vaapi hwaccels but contain no libva code (no vaInitialize), so HWAccelerationEnabled does
  nothing and HDX H.264 stays in software.
- Wi-Fi stats freezes (2026-11-20): Resources froze (its UI thread blocked in ath12k_mac_get_fw_stats /
  nl80211_dump_interface), and every `iw station dump` took 6-11 s: "time out while waiting for fw stats done" 2500x
  in a day. fw_stats.num_vdev_recvd was only reset after a successful request, so after one miss every VDEV_STAT
  request waited its 3 s timeout (two per station dump). patches/kernel/0011 resets the state per request and uses
  ">="; on the laptop (out-of-tree ath12k.ko in updates/, exported symbol CRCs unchanged) station dumps now take 0.00 s.
- Ubuntu Dock hid by itself on the 166 % panel with Firefox maximized or fullscreen (the Dell at 100 % was fine):
  the pointer at the very bottom sits in the last physical pixel row (logical y ~1079.4), outside the dock's
  whole-pixel area, and each redraw of the window below re-picks the pointer onto it, so the dock lost hover and hid.
  (The same edge is why "require pressure to show" never triggered there.) sb4edge-dock-fix now treats a pointer
  within 3 px of the dock's edge, inside its width, as hovering. Found with temporary show/hide/hover logging.
- Extensions from the reference laptop are now part of the image (overlay/gnome/extensions/*.zip, enabled by
  90-sb4edge-extensions.gschema.override): hidetopbar-multimonitor (with a fix: secondary panels now report their
  height to Desktop Icons NG, whose icons sat under those panels; overlapping icons there let a drag move the Windows
  drive into Home), top-bar-organizer-plus, simple-weather, no-screenshot-box-xr, tesseract-ocr-xr, rustdesk-window.
- Ubuntu Dock over maximized windows, root cause (2026-11-21): with hidetopbar and the dock both hidden, a maximized
  window covers the whole monitor and mutter unredirects it (direct scanout). The dock's inhibitsUnredirection only
  returned true for fullscreen windows, so over a maximized Firefox the screen switched between scanout and
  compositing as the dock appeared and hid: it flickered and lost hover. The tell: it behaved while a notification
  was up (the message tray disables unredirection). Found by inspecting the live shell (unsafe mode via Looking
  Glass, Eval) and confirmed by calling global.compositor.disable_unredirect() live. sb4edge-dock-fix patch 4
  (sb4edge-dock-unredirect): the dock inhibits unredirection whenever it is SHOWING/SHOWN/HIDING. Also from 60 Hz
  pointer traces: resting on the touchpad, the pointer jumps 15-50 px up when a finger lifts or settles, which left
  the dock's box and hid it; the dock now stays up 40 px beside / 70 px above its box, a pointer back on the icons
  during the hide delay cancels the hide, and a 150 ms watch reveals the hidden dock at the edge even if its strip
  never gets hover (the last physical pixel row at 166 %). hide-delay 1.0 s had made the still-visible dock "catch"
  the pointer early; 0.3 s on the reference laptop (user setting, not a distro default).
- Overview (2026-11-20/21): Esc did not close the overview: snapd-search-provider@canonical.com (declares shell 48-49)
  broke SearchController's Esc on GNOME 51; disabled in 90-sb4edge-extensions.gschema.override. New extension
  sb4edge-overview-close: Esc (clearing a search first) and a click on empty space close the overview and app grid;
  a click on a neighbouring workspace preview activates that workspace (the first version closed the overview).
  hidetopbar: the overview search padding divided panelBox.height (already logical px) by the monitor scale, gluing
  the entry to the panel at 166 %; now panelBox.height + 6 px (18 px above / 19 px below). The panel's 0.4 s slide in
  the overview looked like the entry moving up: 0.15 s (schema default).
- Fingerprint from the GDM user list (2026-11-20/21): GDM needs a user before PAM, so a touch on the user list did
  nothing. sb4edge-fp-identify (root, D-Bus activated, callable by group gdm) verifies the finger against each user
  with enrolled prints while the greeter's list is shown and only while the greeter session is active; on a match it
  releases the reader, writes a one-time token (/run/sb4edge/fp-token/USER, root 0600, 20 s) and emits Identified. A
  greeter-only loginDialog.js overlay (G_RESOURCE_OVERLAYS in a drop-in for org.gnome.Shell@gdm.service; GLib falls
  back to the stock file if the overlay is missing; rebuilt from libshell by sb4edge-gdm-fp-overlay after updates)
  calls Start/Stop and selects the matched user; pam_exec sb4edge-fp-token accepts the token once. Three rounds of
  fixes from real logins: (1) Ubuntu's GDM authenticates through gdm-password (common-auth has pam_fprintd), so a
  token check only in gdm-fingerprint was never used and a second touch was needed: the line now also sits in
  gdm-password before common-auth. (2) The token time was written rounded and compared with truncated
  /proc/uptime, so about half the touches looked 1 s in the future: whole seconds on both sides, 1 s tolerance.
  (3) Lock screen ignored the finger once text was typed: busctl monitor showed gdm-password's pam_fprintd and
  gdm-fingerprint both claiming the reader at prompt start ("Device was already claimed"); the former usually won,
  waited 10 s, and gave up once a password was being typed. gdm-password now skips that one module
  (`auth [success=1 default=ignore] pam_permit.so` right before @include common-auth, only while common-auth starts
  with pam_fprintd), so GDM's background gdm-fingerprint service always has the reader. sudo/polkit unchanged.
  pamtester: fresh token -> authenticated; used token -> fingerprint then password; wrong password fails in 2 s.
- sb4edge-gnome-persist (2026-11-21): apt hook + boot service before GDM. Re-runs sb4edge-dock-fix and
  sb4edge-gdm-fp-overlay, restores the PAM lines (both files are conffiles a release upgrade may replace), and adds
  the running GNOME Shell major version to the shell-version of *@sb4edge and hidetopbar extensions (system and
  ~/.local), so a GNOME upgrade does not silently disable them. Simulated GNOME 52 and a replaced PAM file: restored
  once, only those extensions touched.
- Windows drive read-only with Unlock/Lock folder (2026-11-20/21): ntfs-3g mounts the volume read-write at a
  root-only path; the /run/media view is a read-only bind; unlocked folders (list in /var/lib/sb4edge/windows-unlocked,
  re-applied at boot) are writable mounts on top, hidden from Files (x-gvfs-hide); GNOME Files' right-click menu
  (nautilus-python) offers Unlock / Lock (pkexec). Generic since 2026-11-21: the NTFS volume holding
  Windows/System32 is found at boot (UUID / USER_NAME / ENABLED=no in /etc/default/sb4edge-windows-mount).
  Bugs found on the laptop: (1) the menu used os.path.ismount, which misses same-filesystem bind mounts: it now
  reads the saved list plus rw mounts in mountinfo. (2) Files said "destination is read-only" in unlocked folders and
  then crashed (also without the extension: a Nautilus bug in its error path): GIO decides filesystem::readonly by
  device number and a bind mount keeps the read-only drive's device, so unlocked folders are bindfs mounts (own
  device). (3) Lock/unlock changes only the mount, so Files got no change event: the helper touches the folder through
  the read-write mount and restores its mtime (inotify ATTRIB). (4) With a space in its source path bindfs records
  its source as "bindfs", libmount's utab merge fails and x-gvfs-hide is lost (Files offered "Unmount", which fails
  for the user): bindfs reads through a spaceless alias bind under /run/sb4edge/unlocked; findmnt -l escapes spaces
  as \x20, so lock/rename/delete now parse /proc/self/mountinfo. (5) An unlocked folder's own entry lives in its
  locked parent and it is a mount point: rename-folder / delete-folder helper commands (zenity dialogs in the menu).
- Fullscreen Citrix (Epic) and RustDesk jumped a few pixels up and left whenever the top bar appeared on the 166 %
  panel (2026-11-21). A window logger showed no move or resize at all; disabling unredirection live
  (global.compositor.disable_unredirect()) made it stop. A fullscreen window is scanned out directly with the display
  hardware doing the 1.667x scaling, which lands a few pixels off GNOME's own scaling; when the top bar (or dock)
  appears, GNOME composites again and the picture shifts. sb4edge-dock-fix patch 5 (sb4edge-dock-unredirect-
  fractional): the dock inhibits unredirection for fullscreen windows on fractionally scaled monitors; integer-scaled
  monitors (the external one at 100 %) keep direct scanout. (It showed up with Firefox open on the other monitor; not
  investigated further, the fix covers both cases.)
- Sluggish desktop for minutes after every login, with two monitors (2026-11-21): mutter logged "Page flip failed:
  drmModeAtomicCommit: Invalid argument" hundreds of times per minute from the moment the session took over from the
  login screen until the next full modeset (screen lock/blank). drm.debug=0x14 (only briefly: at 120 Hz it slows the
  whole system) showed "[PLANE:51:plane-0] switching CRTC directly" then "atomic core check failed": the user
  session's mutter tried to move a hardware plane from one CRTC to the other in a single commit, which the DRM core
  refuses; the login screen (default layout) had left the planes assigned differently. Re-applying the display
  configuration once cleared it (0 failures afterwards). Fix: the login screen gets the user's monitors.xml
  (/etc/xdg/monitors.xml, kept in sync by sb4edge-gnome-persist at every boot and after updates); after that login
  0 failures. Toggling VRR at runtime did not reproduce it, so the panel's VRR patch is not the cause.
- geoclue (location) timed out after 90 s at boot (night light and the weather extension then failed to get a
  location); started by hand it is ready in 2 s. Debug drop-in added to catch the boot-time cause.
- Boot: "Error running install command '/sbin/modprobe --ignore-install snd-pcm ...'" 10x per boot (2026-11-22):
  alsa-base's install lines for snd-pcm/snd-mixer/snd-seq/snd-rawmidi fail in the initramfs (busybox-style modprobe
  rejects --ignore-install, the same failure as the "install snd" line removed on 2026-11-18). They only preload the
  OSS emulation modules, which Ubuntu blacklists; removed (remaster sb4edge_cleanup, update script), initramfs rebuilt.
- Desktop Icons (DING): an icon's right-click menu was cut off after a few items (seen for the drives in the right
  column at 150 %; the mapped xdg_popup was 162x184 for a ~5-item menu). The menu was parented to the desktop window
  and pointed at the icon's allocation. Moving it to the right half (LEFT position) alone did not help; parenting it to
  the icon itself, like DING's rename popup, did (popup 174x198, all items). Placed on the left, a top-row icon's menu
  reached under the top bar (DING is a desktop window; its popups stay below GNOME's chrome), so the menu opens below
  the icon (GTK flips it up near the bottom) and points at the icon's inner third so it fits next to a screen edge with
  its rounded corners. sb4edge-dock-fix patch 6. (A thin dark bar next to the menu was the edge of a window behind.)
- Menus: "a thin black vertical bar" at the left of a right-click menu (2026-11-22). Zoomed screenshots: Yaru draws
  every popup menu with a 1 px rgba(0,0,0,0.23) outline and a hard 0 1px 2px shadow; on a light window behind the menu
  that reads as a dark line. Tried with the user over five rounds (screenshots compared pixel by pixel): a wide soft shadow
  (0 6px 18px) or a deep below-only one shows as a grey band on a white window behind the menu; no shadow is too flat;
  a 1 px box-shadow spread as hairline made GTK cut off the menu's last item at 150 %; border-color had no visible
  effect. Final for GTK4 (popover.menu) and GTK3 (menu, .context-menu, popover.menu): `outline: 1px solid
  rgba(0,0,0,.09); outline-offset: -1px` plus `box-shadow: 0 2px 3px -1px rgba(0,0,0,.10)` (dark variant via
  prefers-color-scheme), and a 99.5 % opaque menu background. The last "bar" only appeared while a menu was open
  and showed the wallpaper colour through the window behind: with a fully opaque background GTK reports the popup's
  opaque region slightly larger than what it paints at 150 %, so mutter culled (did not draw) the window behind that
  strip. That was also the original "thin black bar". Alpha 0.995 avoids the opaque region; it looks identical.
in each user's gtk.css and /etc/skel,
  kept by sb4edge-gnome-persist (a "sb4edge-smooth-menus: off" line opts out). GNOME Shell's own menus already use a
  light #ededed outline and a soft shadow.
- Battery (2026-11-22): Resources showed "Design Capacity N/A" (it reads energy_full_design; the driver only had
  charge_*), and the percentage dropped to 4 %/7 % or jumped to 100 % for a poll (UPower history 61, 56, 55, 56,
  100, 56 within a minute; no "EC read failed" logged, so the bad values came from successful reads). Cause: the
  4-byte EC fields are read byte by byte through the shared mailbox and can be torn. samsung_galaxybook_battery:
  sgb_ec_read_block_stable (two identical reads, up to 4 tries), a jump of more than 5 % held until the next poll
  confirms it, energy_now/full/full_design (charge x voltage_min_design) and power_now. Reload needs
  `modprobe -r samsung_galaxybook_kbd samsung_galaxybook_battery` (kbd uses sgb_ec_excmd). After it: 60.5 Wh design /
  49.7 Wh full / 82 % health in UPower, rate 12.7 W, 120 samples over 4 min without a jump.
- hidetopbar (2026-11-22, battery): secondary top bars follow the pointer through the cursor tracker's
  position-invalidated signal instead of a 75 ms poll (13 wakeups/s per extra monitor), with a one-shot 500 ms
  re-check while a menu of a revealed bar is open; monitors-changed rebuilds only the secondary panels whose monitor
  changed geometry or scale (each full rebuild left work behind). See the extension's CHANGELOG.md.
- GNOME extensions merged (2026-11-21): no-screenshot-box-xr, tesseract-ocr-xr, sb4edge-overview-close and
  rustdesk-window are now one extension, sb4edge-tweaks-xr@sb4edge (features/<name>.js, one feature-<name> switch
  each in its preferences, toggled at runtime; the screenshot CSS is loaded only while that feature is on). Same
  setting key names, so a dconf dump of the old paths loads into /org/gnome/shell/extensions/sb4edge-tweaks-xr/.
  Nested headless shell: all features start, each switch removes and restores its changes (OCR button, panel style,
  D-Bus object), disable/enable clean, no JS errors. The accessibility icon (shown by GNOME whenever Large Text is
  on, even with "Always Show" off) was first hidden by Hide Accessibility Menu (hideaccessibilitymenu@boni.scot, EGO
  v7, reviewed), then replaced by the `accessibility` feature (see the conflict review below).
- Extension conflict review (2026-11-21): shell log of the reference laptop + what every enabled extension patches.
  (1) hidetopbar-multimonitor's extra top bars are full Panel.Panel instances, destroyed and rebuilt at every monitor
  change and lock; GNOME's top bar items never disconnect from session-wide objects (session mode, Bluetooth / NM
  clients), so destroyed items kept reacting: "already disposed" errors in calendar.js, bluetooth.js,
  thunderbolt.js, popupMenu.js, backgroundApps.js at unlock. Reproduced headless with two virtual monitors (3
  rebuilds + one session update: 50 errors). Fixed in sb4edge-tweaks-xr feature `panels`: while an extra panel is
  built (Panel._init, and QuickSettings._setupIndicators, which continues after an await), connect/connect_after/
  connectObject calls made by GNOME Shell code (first non-plumbing stack frame in resource:///org/gnome/shell/) to
  objects outliving the panel are recorded and removed after its destroy; connectObject ones via
  disconnectObject(owner), Gio.Settings / DBusProxy skipped (items run_dispose them). Result: 0 errors, 0 JS errors
  with every laptop extension loaded. (2) Hide Accessibility Menu hid only the primary panel's a11y icon (each extra
  top bar has its own), and the primary's _updatePanel (bound before extensions load) re-showed it on a session
  update: feature `accessibility` covers every panel (Panel hooks + a session-mode handler) and replaced it.
  (3) The screenshot feature reloaded its stylesheet on St.ThemeContext 'changed', which loading a stylesheet emits
  itself: infinite recursion with hidetopbar loaded; now notify::theme. No other overlaps: Top Bar Organizer patches
  Panel._addToPanelBox (we patch _init/_updatePanel, through one shared hook that restores only its own wrappers);
  dock and hidetopbar unredirect calls are balanced.
  (4) On the laptop after a re-login, 12 "this._settings is null" errors in dateMenu.js: the extra panels' date menus
  connect to Main.messageTray, an actor, and `panels` first kept only non-actor objects. Session-wide actors are now
  kept too: global.stage, window_group, top_window_group and every actor exported by main.js and layoutManager
  (rebuilt per extra panel, as some are created lazily); the panel's own actors and its menus are destroyed with it.
  Those actors are watched for 'destroy' (module-level WeakSets), so a cleanup still pending at shell shutdown skips
  them. 0 errors after the fix.
- Battery: idle wakeups of the GNOME extensions (2026-11-22). A probe extension loaded first wraps
  GLib.timeout_add/timeout_add_seconds/idle_add and counts callbacks by origin over 30 s with the pointer still
  (nested 2-monitor shell, every laptop extension, dock autohide on). Before: about 20 wakeups/s:
  hidetopbar-multimonitor polled the pointer every 75 ms per extra top bar (531 per 40 s) and the dock edge watch of
  sb4edge-dock-fix every 150 ms (266 per 40 s). After: 4 callbacks in 30 s (two one-shot intellihide checks), 14-17
  stage paints.
  - hidetopbar fork (secondaryVisibilityManager.js): the 75 ms poll is replaced by the same reveal logic on the cursor
    tracker's 'position-invalidated' (once per pointer move, never while still; track_position does not exist on
    GNOME 51), plus a one-shot 500 ms re-check only while a menu of the revealed bar is open (PopupMenuManager has no
    menu-changed signal). multiMonitorManager.js: _rebuildSecondaryPanels keeps an extra top bar whose monitor
    geometry and scale are unchanged instead of destroying and rebuilding all of them on every monitors-changed.
  - sb4edge-dock-fix 3b (mark sb4edge-dock-edge-event, applied on top of the edge patch): the edge watch runs only
    while it has something to do (pointer on the hidden dock's edge, on the icons while it hides, or on the shown dock
    without hover), woken by pointer motion, the dock's 'hiding' signal and box hover changes. Tested headless with a
    virtual pointer, also with the dock box non-reactive (no hover, as over a window): shows after the edge dwell,
    hides on leave, timer back to 0.
- Battery survey of the whole system (2026-11-22, laptop in use, per-process context switches and CPU over 30 s,
  forks with perf sched:sched_process_fork, D-Bus with busctl monitor, disk writes from /proc/*/io; a sudo per
  process in a measuring loop floods the journal and the system bus itself, so measure with one sudo).
  - Wi-Fi: patches/kernel/0012. Every NetworkManager station dump (every 3-6 s) still blocked 3 s with 0011
    applied. kprobe on ath12k_mac_get_fw_stats (struct ath12k is past 16 KiB: num_started_vdevs at +0x4000+2856,
    found in the disassembly of the reply handler) showed num_started_vdevs=2 with one STA vdev; the firmware
    replies with one vdev, so WMI_REQUEST_VDEV_STAT never completed. ath12k_mac_vdev_start_restart() counts a
    restart as another start; restarts come from a channel switch of an up vdev (DFS AP: CTRL-EVENT-STARTED-
    CHANNEL-SWITCH at 23:32:26, 0 timeouts before it, first one 6 s after). 0012 counts only real starts.
    Out-of-tree ath12k.ko rebuilt on the laptop (sparse clone of v7.4-rc3 + 0011 + 0012, headers tree; the 130
    symbol CRCs ath12k_wifi7 imports match), in updates/ for the next boot, copied to out/ath12k.ko.
  - sb4edge-fan (every 2 s) and sb4edge-backlight (every 3 s) started 2.5 processes/s each (cat, sleep, ls, and 5
    loginctl calls per backlight pass, each a system-bus connection: the NameOwnerChanged churn). Now bash builtins
    (read from sysfs, results in variables, pause = read -t on an idle pipe); the backlight watcher compares levels
    in memory and asks loginctl (one call for Class/LockedHint/IdleHint) only when a level changed, retrying a
    level seen outside an active session after 30 s. 1.0 and 0.4 wakeups/s, no children. Verified: a panel
    change is recorded and the restore too.
  - sb4edge-usbc: 173 -> ~100 wakeups/s. The 150 ms poll stays (a waiting sink shows 0x10 for ~0.33 s of every
    3.7 s), the reads per poll drop: alt state (0x1A/0x57) only with a partner or DP on (cleared just before
    StartAlt instead), once a second for a partner with no DP 10 s after the attach; the Source_Capabilities
    block only once a sink or a waiting partner is seen, and not for a charger already switched in and settled.
    The CC orientation read (0x12) stays on every poll of an empty port (it can be the only orientation reading).
    Needs plug tests: device (USB 3 speed), charger (20 V request), DP adapter.
  - geoclue's temporary debug drop-in (G_MESSAGES_DEBUG=Geoclue, laptop only) wrote ~60 KB/s to the journal and
    rsyslog (long Wi-Fi scan dumps); geoclue started in 87 ms this boot, so it was removed (backup kept).
  - Not ours, left as is: Claude Desktop renders in software (it disabled hardware acceleration itself:
    isHardwareAccelerationAutoDisabled) and its GPU process used ~25 % of a core while animating; RustDesk
    --server runs loginctl ~2.5 times/s and wakes ~300 times/s; Citrix ServiceRecord and AuthManagerDaemon ~120
    wakeups/s each; ChatGPT's codex exec-server ~330/s; DING ~16/s (Wayland events). rustdesk-display-client
    asks the extension for the RustDesk window every 3 s (could become a D-Bus signal).
  - Boot logo shown twice (from the user's video): plymouth started on simpledrm, msm replaced it a second later
    (blank), and plymouth showed the logo again. UseSimpledrm=0 in plymouthd.conf (overlay/sb4edge-plymouthd.conf,
    remaster.sh, update-script item 24), initramfs rebuilt. DeviceTimeout=8 still falls back if msm never comes.
  - A kernel crash left no log: kdump-tools ran, but makedumpfile --dump-dmesg fails on 52-bit VA. persist patches
    kdump-config to try vmcore-dmesg first (backup kdump-config.orig; re-applied after kdump-tools updates).
  - Battery module fix not active after a reboot: the initramfs still held the old samsung_galaxybook_battery.ko.
    The update script's battery step now runs update-initramfs.
  - geoclue sometimes hangs at boot for 90 s (night light/weather wait). A TEMP drop-in on the laptop only (not
    shipped) runs it through a wrapper that logs thread wait channels and fds if it is still starting after 20 s,
    with TimeoutStartSec=30 and a restart. G_MESSAGES_DEBUG was not re-enabled (journal volume).
  - Crash reports checked, not ours: gnome-software (polkit race at login), a headless gnome-shell for RustDesk,
    fprintd (truncated core). The Ventoy stick logged one USB reset on insertion, harmless.
  - The splash shows once (user-confirmed) but later: black from rEFInd until msm is up (~3.4 s kernel time) plus
    GRUB reading the 113 MB initramfs. 45 MB of it was other laptops' ADSP/CDSP firmware (ubuntu-x1e-settings
    copies all of qcom/x1e80100; ath12k QCN9274/IPQ5424/QCC2072 too). sb4edge-slim.conf removes them: 76 MB
    (backup initrd .pre-slim). GRUB timeouts were already 0. No FPDT on this laptop to time the loader.
  - User asked to boot only this laptop's drivers: dracut hostonly strict (sb4edge-hostonly.conf), 2572 -> 184
    modules, 76 -> 52 MB. Checked: every module loaded now that was in the generic image is in it, except exfat,
    uas, binfmt_misc and snd_seq_device (loaded later from /). Generic image kept as initrd.img-<ver>.full with a
    GRUB rescue entry (42_sb4edge_rescue). The kernel's built-in drivers stay (a rebuild); unused modules on disk
    never load. TEMP initcall_debug boot (zzz-sb4edge-boot-timing.cfg) to time the display bring-up.
  - First host-only boot: msm at 7.9 s instead of 3.1 s. qrtr_smd was loaded at 2.49 s, after the CDSP was up
    (1.98 s); its IPCRTR channel open on the CDSP edge timed out (5.16 s, "failed to create endpoint", -12) and the
    module loading behind it waited. The next boot (same image) loaded it at 1.92 s, right as the CDSP came up, and
    was normal: an ordering race. sb4edge-qrtr.conf force_drivers qrtr qrtr_smd (rd.driver.pre, before the
    qcom-adsp pre-udev hook boots the DSPs). Host-only itself changed no kernel timing (msm 3.14 vs 3.18 s); the
    loader time cannot be seen from the kernel (its clock starts at ~1.75 s on every boot).
  - Display chain on a normal boot (initcall_debug): DP controllers probed by 2.566 s, but udev loaded
    panel_samsung_atna33xc20 only at 2.700 s; its probe (548 ms) holds the HPD wait (~260 ms), the msm component
    bind (2.964 s), msm init (3.136 s) and fbdev (3.297 s); first modeset done 3.736 s. The same force_drivers
    list now also loads ps883x, pmic_glink_altmode, aux_hpd_bridge, the combo/eDP phys, msm and the panel before
    udev. Panel timings (HPD up to 200 ms, EL_ON3 400 ms after power-on) are the panel spec and stay.
  - Result of force-loading the display chain (boot 20:22): msm loaded at 2.00 s, but the eDP controller still
    probed only at 2.76 s (edp phy/aux bridges waiting for the retimers and gb4e-typec), msm initialized 3.21 s (no
    gain), and plymouth never drew: the first modeset was GDM's at 16.6 s. Reverted to qrtr/qrtr_smd only. Loaded
    before the CDSP, the IPCRTR probe runs in the glink worker (1.48 s that boot), not inside modprobe.
  - Wi-Fi slow after login (user): connect attempt only at 28.9 s although the radio was ready at 12.7 s. ath12k's
    11d scan (country detection) makes scans fail as busy until it finishes (country US at 19.9 s), then NM's
    retry backoff. ath12k.ko rebuilt from the 0011+0012 tree with -DCONFIG_ATH_REG_DYNAMIC_USER_REG_HINTS=1 (only
    reg.c changes; one more import, get_wiphy_regdom, CRC matches the kernel's), old module kept as
    .pre-country. Country via udev + /etc/default/sb4edge-wifi (laptop: US; distro default empty). The profile was
    also marked hidden (active probing on every scan) although the AP broadcasts its SSID: unhidden (laptop only).
    Gateway ping showed 45 ms average / 170 ms spikes in one run, 4.7 ms clean in two later runs (no scans then):
    intermittent, not explained yet. DHCP took 5.3 s (server side).
  - Splash missing again (boots 20:22 and 20:47, no display until GDM at 16.6 s) with only qrtr force-loaded: the
    host-only initramfs switches root ~0.6 s after msm initializes (3.72 vs msm 3.11 s), before plymouth's first
    modeset; plymouth then never drew. The boot that showed it switched at 4.38 s (AVR 3.74 s). dracut module
    95sb4edge-splash-wait: pre-pivot hook waits (<= 2.5 s) for card*-eDP-*/enabled while plymouth runs.
  - systemd-udev-settle cost 5.55 s on the critical chain, pulled in by sb4edge-windows-unlock.service (and a
    laptop-only sb4edge-fnkeys.service). The internal UFS partitions exist before root is mounted: After=local-fs.
  - Boot 20:47 with the country fix: REGDOM US at 12.84 s (no WORLD phase, no 11d), connect attempt 20.45 s, connected
    28.37 s (was 28.9 / 43.1 s). Remaining: NM's first full scan (~7.6 s) and the supplicant's scan at activation
    (~7.5 s). Full scan measured at 13.7 s while connected, 5 GHz-only 5.7 s. Laptop: PHCBP (multi-AP, 5600 MHz) set
    to band a. The intermittent ping spikes fit bgscan simple:30:-65:300 at a -62..-65 dBm signal.
  - Boot 21:05: graphical.target 7.6 s after the initramfs (was 12.6 s: udev-settle gone); Wi-Fi up 29.6 s (before
    login). Splash still missing: the hook returned after 17 ms because card1-eDP-1/enabled already reads "enabled"
    from the firmware handover. Splash shown when the switch came >= 1.2 s after msm init (plymouth's first enable,
    logged as "sb4edge: intf 5 AVR", ~0.6-0.8 s after msm init); missing at 0.84-0.88 s. Hook now waits for that
    kmsg line (timeout 2.5 s).
  - Logoff/restart "frozen screen" (user): GNOME Shell normally exits 0.5-1 s after "Shutting down"; once in ~28
    exits (20:46, Citrix Epic open, last message "Connection to xwayland lost") it hung until systemd's 5 s stop
    timeout killed it. After the shell, the restart took ~4 s, 3 s of it openlogi-agent (third-party Logitech tool,
    "watcher teardown exceeded the process-exit deadline timeout=3s"): laptop-only user drop-in TimeoutStopSec=1s.
    On logoff the screen keeps the last frame until GDM's new greeter shell is up (~2 s), as before.
