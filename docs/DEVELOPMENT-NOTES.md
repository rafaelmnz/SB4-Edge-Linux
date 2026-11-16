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
- "failed to load gen70500_sqe.fw" at boot is benign: the initramfs probe misses it, the GPU loads sqe + GMU v4.3.17 on first open.

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
