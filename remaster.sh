#!/bin/bash
# Remaster the Ubuntu 26.10 arm64 desktop ISO into Ubuntu 27.04 for the Samsung Galaxy Book4 Edge 16".
# Ubuntu publishes no 27.04 arm64 desktop image yet, so every layer of the 26.10 image is upgraded to 27.04
# ("tenacious") from ports.ubuntu.com while it is remastered.
# Runs inside the sb4build container (--privileged), /iso = scratch volume, /work = project dir.
set -euo pipefail
KVER=7.4.0-rc3-sb4edge
ORIG=/work/iso/ubuntu-26.10-desktop-arm64.iso
OUT=/work/out/ubuntu-27.04-sb4edge-desktop-arm64.iso
FROM_SUITE=stonking   # the ISO's release (its pool and sources)
SUITE=tenacious       # the release the layers are upgraded to
SRC=/iso/src
B=/iso/base
SQ="-comp xz -b 131072 -noappend -no-progress -processors 14"
log() { echo "=== $(date +%T) $*"; }

log "fresh copy of ISO tree"
rm -rf "$SRC"; mkdir -p "$SRC"
xorriso -osirrox on -indev "$ORIG" -extract / "$SRC" >/dev/null 2>&1
chmod -R u+w "$SRC"

log "extract base layer"
rm -rf "$B"; unsquashfs -no-progress -d "$B" $SRC/casper/minimal.squashfs >/dev/null
# *.size and the installer sizes are ISO-specific measurements; only add what we change, measured
# the same way before and after.
BASE_BEFORE=$(du -sB1 "$B" | cut -f1)
cp "$B/var/lib/dpkg/status" /iso/status.before

log "chroot setup"
for d in proc sys dev dev/pts; do mount --bind /$d "$B/$d"; done
mkdir -p "$B/cdrom"; mount --bind "$SRC" "$B/cdrom"
mkdir -p "$B/tmp/pkgs"
cp /work/out/linux-image-${KVER}_*.deb /work/out/linux-headers-${KVER}_*.deb "$B/tmp/pkgs/"
cp -a "$B/var/lib/apt/lists" /iso/apt-lists.orig

log "firmware, hwids, hook"
FW="$B/usr/lib/firmware/qcom/x1e80100/SAMSUNG/galaxy-book4-edge"
mkdir -p "$FW" "$B/usr/share/sb4edge/hwids"
cp /work/fw/*.mbn /work/fw/*.elf /work/fw/*.jsn "$FW/"
cp /work/overlay/hwids/*.json "$B/usr/share/sb4edge/hwids/"
install -m755 /work/overlay/50-sb4edge-stubble "$B/etc/kernel/postinst.d/50-sb4edge-stubble"
# bindeb-pkg kernels ship a modules.dep without updates/ (our EC/USB-C drivers): rebuild it before the initramfs
install -m755 /work/overlay/00-sb4edge-depmod "$B/etc/kernel/postinst.d/00-sb4edge-depmod"
# The hook needs systemd-ukify, stubble and python3-pefile on the installed system (installed with the network
# packages below): without them a kernel deb installed later boots without a devicetree and the laptop resets.

log "install packages in chroot (ISO pool only, so nothing gets upgraded)"
echo "deb [trusted=yes] file:/cdrom $FROM_SUITE main" > "$B/tmp/cdrom.list"
chroot "$B" /bin/bash -euxc "
export DEBIAN_FRONTEND=noninteractive FK_MACHINE=none
APT='-o Dir::Etc::sourcelist=/tmp/cdrom.list -o Dir::Etc::sourceparts=/nonexistent'
apt-get \$APT update
apt-get \$APT install -y --no-install-recommends ubuntu-x1e-settings
apt-get \$APT install -y --no-install-recommends /tmp/pkgs/linux-image-${KVER}_*.deb /tmp/pkgs/linux-headers-${KVER}_*.deb
apt-mark hold linux-image-${KVER}
apt-get clean
rm -rf /tmp/pkgs /tmp/cdrom.list
"
rm -rf "$B/var/lib/apt/lists"; mv /iso/apt-lists.orig "$B/var/lib/apt/lists"

# Upgrade a layer to $SUITE from the Ubuntu archive. Uses only ubuntu.sources (not the cdrom source), rewritten to
# $SUITE on ports.ubuntu.com (arm64 for the development series is only there), so the installed system follows
# $SUITE too. dist-upgrade: a release upgrade brings new and renamed packages; removals are listed in the log.
# Held packages (our kernel) stay. Generic kernels are never pulled in: the installer gets linux-image-$KVER.
cat > /iso/net-upgrade.sh <<"EOS"
#!/bin/bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive FK_MACHINE=none
F=/etc/apt/sources.list.d/ubuntu.sources
sed -i -e "s/\b@FROM@\b/@SUITE@/g" -e "s|http://archive.ubuntu.com/ubuntu/\?|http://ports.ubuntu.com/ubuntu-ports/|" \
       -e "s|http://security.ubuntu.com/ubuntu/\?|http://ports.ubuntu.com/ubuntu-ports/|" "$F"
grep -q "@SUITE@" "$F"
mkdir -p /tmp/net-sources
cp "$F" /tmp/net-sources/
APT=(-o Dir::Etc::sourcelist=/dev/null -o Dir::Etc::sourceparts=/tmp/net-sources
     -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
apt-get "${APT[@]}" update
# In an upper layer, packages may pin exact versions of libraries the lower layer just upgraded;
# let apt bring them along first, but never accept a removal.
if ! apt-get "${APT[@]}" check >/dev/null 2>&1; then
	if apt-get "${APT[@]}" -s -f install | grep -q "^Remv "; then
		apt-get "${APT[@]}" -s -f install | grep "^Remv "; echo "fix-broken would remove packages" >&2; exit 1
	fi
	apt-get "${APT[@]}" -y -f install
fi
apt-get "${APT[@]}" -s dist-upgrade | grep "^Remv " || true
apt-get "${APT[@]}" -y dist-upgrade
apt-get clean
rm -rf /tmp/net-sources
EOS
sed -i -e "s/@FROM@/$FROM_SUITE/g" -e "s/@SUITE@/$SUITE/g" /iso/net-upgrade.sh
chroot_net_upgrade() { # chroot_net_upgrade <root>  (proc/sys/dev already bound)
	mount -t tmpfs tmpfs "$1/run"
	mkdir -p "$1/run/systemd/resolve"; cp /etc/resolv.conf "$1/run/systemd/resolve/stub-resolv.conf"
	install -m755 /iso/net-upgrade.sh "$1/tmp/net-upgrade.sh"
	chroot "$1" /tmp/net-upgrade.sh
	rm -f "$1/tmp/net-upgrade.sh"; umount "$1/run"
}

log "upgrade base layer from the Ubuntu archive"
cp -a "$B/var/lib/apt/lists" /iso/apt-lists.orig
chroot_net_upgrade "$B"
rm -rf "$B/var/lib/apt/lists"; mv /iso/apt-lists.orig "$B/var/lib/apt/lists"

log "remote access tools in the base layer: curl, openssh-server"
# Live session and installed system both get them. sshd is enabled but the live "ubuntu" user has no
# password (sshd refuses empty passwords), so nothing is reachable until a password or key is set.
cp -a "$B/var/lib/apt/lists" /iso/apt-lists.orig
mount -t tmpfs tmpfs "$B/run"
mkdir -p "$B/run/systemd/resolve"; cp /etc/resolv.conf "$B/run/systemd/resolve/stub-resolv.conf"
chroot "$B" /bin/bash -euxc "
export DEBIAN_FRONTEND=noninteractive FK_MACHINE=none
mkdir -p /tmp/net-sources; cp /etc/apt/sources.list.d/ubuntu.sources /tmp/net-sources/
APT='-o Dir::Etc::sourcelist=/dev/null -o Dir::Etc::sourceparts=/tmp/net-sources'
apt-get \$APT update
apt-get \$APT install -y --no-install-recommends curl openssh-server nvtop gstreamer1.0-plugins-bad libopenh264-8 systemd-ukify stubble python3-pefile ddcutil libprotobuf-c1 fake-hwclock python3-nautilus ntfs-3g bindfs zenity
systemctl enable ssh.service
apt-get clean; rm -rf /tmp/net-sources
"
umount "$B/run"
# openssh-server's postinst generated host keys inside the image: every machine would share them. Remove them and
# generate per machine before sshd starts (ssh-keygen -A only creates missing keys).
rm -f "$B"/etc/ssh/ssh_host_*
mkdir -p "$B/etc/systemd/system/ssh.service.d"
printf '[Service]\nExecStartPre=/usr/bin/ssh-keygen -A\n' > "$B/etc/systemd/system/ssh.service.d/sb4edge-hostkeys.conf"
rm -rf "$B/var/lib/apt/lists"; mv /iso/apt-lists.orig "$B/var/lib/apt/lists"

log "GNOME Settings + settings daemon with the sb4edge patches (out/gnome, build-gnome.sh)"
# Fingerprint rename in Settings (Windows Hello prints are numbered, not named) and the automatic-brightness modes.
# Installed in the base layer, so both install options get them. sb4edge-gnome-rebuild (apt hook) rebuilds them
# from source after a GNOME update from the archive; the pkexec rule gives the rename its password prompt.
mkdir -p "$B/tmp/gnome"; cp /work/out/gnome/*.deb "$B/tmp/gnome/"
chroot "$B" /bin/bash -euxc '
debs=(); for d in /tmp/gnome/*.deb; do p=$(dpkg-deb -f "$d" Package)
    dpkg-query -W -f="\${Status}" "$p" 2>/dev/null | grep -q "ok installed" && debs+=("$d"); done
dpkg -i "${debs[@]}"; rm -rf /tmp/gnome
dpkg-query -W -f="\${Version}" gnome-control-center | grep -q sb4edge
dpkg-query -W -f="\${Version}" gnome-settings-daemon | grep -q sb4edge'
for d in gnome-control-center gnome-settings-daemon; do
    install -Dm644 -t "$B/usr/share/sb4edge/patches/$d" /work/patches/$d/*.patch
done
install -Dm755 /work/overlay/gnome-rebuild/sb4edge-gnome-rebuild "$B/usr/lib/sb4edge/sb4edge-gnome-rebuild"
install -Dm644 /work/overlay/gnome-rebuild/sb4edge-gnome-rebuild@.service "$B/usr/lib/systemd/system/sb4edge-gnome-rebuild@.service"
install -Dm644 /work/overlay/gnome-rebuild/99-sb4edge-gnome-rebuild "$B/etc/apt/apt.conf.d/99-sb4edge-gnome-rebuild"
install -Dm644 /work/overlay/fingerprint/org.sb4edge.fingerprint-rename.policy "$B/usr/share/polkit-1/actions/org.sb4edge.fingerprint-rename.policy"

log "hardware fixes from the first USB boot (hw-report/)"
# Wi-Fi: board-2.bin has no entry for this board (subsystem 17cb:1107, board-id 255). Samsung's Windows
# bdwlan.elf crashes the firmware during the board-data download, so add an entry that reuses
# linux-firmware's shared board-id 255 (generic NCM825) data. /lib/firmware/updates wins over the package file.
W=usr/lib/firmware/ath12k/WCN7850/hw2.0
zstd -dc "$B/$W/board-2.bin.zst" > /iso/board-2.orig.bin
# linux-firmware 20261110 has the entry itself (same data): the helper then writes nothing and no override is installed.
mkdir -p "$B/usr/lib/firmware/updates/ath12k/WCN7850/hw2.0"
python3 /work/ath12k-board2-add.py /iso/board-2.orig.bin "$B/usr/lib/firmware/updates/ath12k/WCN7850/hw2.0/board-2.bin"
[ -s "$B/usr/lib/firmware/updates/ath12k/WCN7850/hw2.0/board-2.bin" ] ||
	rmdir -p --ignore-fail-on-non-empty "$B/usr/lib/firmware/updates/ath12k/WCN7850/hw2.0"
rm -f /iso/board-2.orig.bin "$B/$W/board.bin"
# Use the in-kernel qcom_pd_mapper only (the userspace one races it for the servreg locator).
ln -sf /dev/null "$B/etc/systemd/system/pd-mapper.service"
# Bluetooth: the controller comes up unconfigured (no public address).
install -Dm755 /work/overlay/sb4edge-bt-addr "$B/usr/libexec/sb4edge-bt-addr"
install -Dm644 /work/overlay/sb4edge-bt-addr.service "$B/etc/systemd/system/sb4edge-bt-addr.service"
mkdir -p "$B/etc/systemd/system/bluetooth.target.wants"
ln -sf ../sb4edge-bt-addr.service "$B/etc/systemd/system/bluetooth.target.wants/sb4edge-bt-addr.service"
# Keyboard: udev classifies it as a tablet pad (it also reports BTN_0/BTN_1 + ABS_VOLUME).
install -Dm644 /work/overlay/61-sb4edge-keyboard.rules "$B/usr/lib/udev/rules.d/61-sb4edge-keyboard.rules"

# Battery: EC driver (Saddytech, GPL; reads the EC mailbox on the keyboard's I2C bus), built and signed
# against this kernel; its DT node comes with the kernel deb (patch 0002). qcom_battmgr is blacklisted (it never
# answers here). The DTB is the deb's: an out/ override would shadow later DT patches (it hid 0008 once).
install -Dm644 /work/out/samsung_galaxybook_battery.ko "$B/usr/lib/modules/$KVER/updates/samsung_galaxybook_battery.ko"
# Keyboard backlight (extra/samsung-galaxybook-kbd; DT node kbd-backlight@62 on &i2c5, patch 0007).
install -Dm644 /work/out/samsung_galaxybook_kbd.ko "$B/usr/lib/modules/$KVER/updates/samsung_galaxybook_kbd.ko"
# USB-C SuperSpeed (patches/sb4edge-local/0008): PS8830 retimers in the DT, gb4e_typec lets the usbc helper set
# orientation/mode. Hubs kept awake (usbcore is built in): udev rule + cmdline for the installed system.
install -Dm644 /work/out/gb4e_typec.ko "$B/usr/lib/modules/$KVER/updates/gb4e_typec.ko"
install -Dm644 /work/out/sb4_cdsp_stats.ko "$B/usr/lib/modules/$KVER/updates/sb4_cdsp_stats.ko"
install -Dm644 /work/overlay/sb4edge-modules.conf "$B/etc/modules-load.d/sb4edge.conf"
install -Dm644 /work/overlay/63-sb4edge-usb-hub-pm.rules "$B/usr/lib/udev/rules.d/63-sb4edge-usb-hub-pm.rules"
install -Dm644 /work/overlay/sb4edge-grub.cfg "$B/etc/default/grub.d/60-sb4edge.cfg"
# Sleep (overlay/sleep): s2idle (deep returns at once on X1E), and no suspend while an HDMI/USB-C monitor is
# connected (the msm DP bridge does not come back after s2idle and GNOME freezes). The newest -sb4edge kernel stays
# GRUB's default even when the archive brings a newer Ubuntu kernel.
install -Dm644 /work/overlay/sleep/sb4edge-s2idle.conf "$B/etc/systemd/sleep.conf.d/sb4edge-s2idle.conf"
install -Dm755 /work/overlay/sleep/sb4edge-hdmi-sleep-guard "$B/usr/lib/sb4edge/sb4edge-hdmi-sleep-guard"
install -Dm644 /work/overlay/sleep/sb4edge-hdmi-sleep-guard.service "$B/etc/systemd/system/sb4edge-hdmi-sleep-guard.service"
mkdir -p "$B/etc/systemd/system/multi-user.target.wants"
ln -sf ../sb4edge-hdmi-sleep-guard.service "$B/etc/systemd/system/multi-user.target.wants/sb4edge-hdmi-sleep-guard.service"
install -Dm644 /work/overlay/sleep/zz-sb4edge-kernel.cfg "$B/etc/default/grub.d/zz-sb4edge-kernel.cfg"
chroot "$B" depmod -a "$KVER"
install -Dm644 /work/overlay/sb4edge-battery.conf "$B/etc/modprobe.d/sb4edge-battery.conf"
install -Dm644 /work/overlay/sb4edge-battery-dracut.conf "$B/etc/dracut.conf.d/sb4edge-battery.conf"
install -Dm644 /work/display/sb4edge-edid.bin "$B/usr/lib/firmware/edid/sb4edge-edid.bin"
install -Dm644 /work/overlay/sb4edge-edid-dracut.conf "$B/etc/dracut.conf.d/sb4edge-edid.conf"
# Adreno X1-85 microcode in the initramfs: msm probes there, and without it "failed to load gen70500_sqe.fw" was
# logged at every boot and the GPU only came up after the switch to the real root.
install -Dm644 /work/overlay/sb4edge-gpu-dracut.conf "$B/etc/dracut.conf.d/sb4edge-gpu.conf"
# alsa-base's "install snd" line (preloads snd-seq) fails at every boot: in the initramfs modprobe is busybox, which
# rejects --ignore-install/--use-blacklist. snd-seq autoloads through its devname:snd/seq alias anyway.
sb4edge_cleanup() { # sb4edge_cleanup <root>: also re-run on the standard layer after its upgrade
	[ ! -f "$1/etc/modprobe.d/alsa-base.conf" ] || sed -i '/^install snd \/sbin\/modprobe --ignore-install snd /d' "$1/etc/modprobe.d/alsa-base.conf"
	if grep -qs "^install snd " "$1/etc/modprobe.d/alsa-base.conf"; then echo "alsa-base fix failed in $1"; exit 1; fi
	# libmalcontent-common ships D-Bus files for the malcontent-webd/timerd daemons, which are not installed (nor
	# their system users): dbus-daemon logged "Invalid user name" at every boot. dpkg excludes keep them out.
	rm -f "$1"/usr/share/dbus-1/system-services/org.freedesktop.Malcontent{Web1,Timer1,Timer1.ExtensionAgent}.service \
	      "$1"/usr/share/dbus-1/system.d/org.freedesktop.Malcontent{Web1,Timer1,Timer1.ExtensionAgent}.conf
}
install -Dm644 /work/overlay/sb4edge-no-malcontent-daemons "$B/etc/dpkg/dpkg.cfg.d/sb4edge-no-malcontent-daemons"
sb4edge_cleanup "$B"
# brltty's udev rule has an invalid line (logged at every boot) and grabs USB-serial adapters; masked (no braille
# display). The package stays: ubuntu-desktop-minimal depends on it.
install -Dm644 /work/overlay/85-brltty-masked.rules "$B/etc/udev/rules.d/85-brltty.rules"
# Variable refresh: kernel patch 0015 (msm AVR), enabled by msm.vrr=3 in overlay/sb4edge-grub.cfg. It replaced the
# 60/120 Hz AC/battery switcher (display/sb4edge-refresh, kept in the project but not installed).
# USB-C power roles (omarchy's usbc helper). Verified on the 16" (third boot): both S2MM006 answer at 0x33 on
# a84000/a9c000 with the documented registers, and the helper re-detects and powers devices.
install -Dm755 /work/out/sb4edge-usbc "$B/usr/libexec/sb4edge-usbc"
install -Dm644 /work/overlay/sb4edge-usbc.service "$B/etc/systemd/system/sb4edge-usbc.service"
# Enabled (verified on the installed 16", 2026-11-15): without it a charger plugged in after boot is never
# switched in (the S2MM006 waits for the host, as for EmuEc.sys on Windows), so the battery does not charge after
# a replug; with it: "charger attached, input switch on", 20 V/3 A contract. It also sets retimer orientation
# (SuperSpeed). Powered ports are left alone at start, so a USB-C boot stick keeps power.
# Fan curve (EC fan target through samsung_galaxybook_kbd's hwmon), per performance mode (GNOME Power Mode),
# with the CPU cap of Quiet. Enabled: without it the fan never runs.
install -Dm755 /work/overlay/sb4edge-fan "$B/usr/libexec/sb4edge-fan"
install -Dm644 /work/overlay/sb4edge-fan.service "$B/etc/systemd/system/sb4edge-fan.service"
mkdir -p "$B/etc/systemd/system/multi-user.target.wants"
ln -sf ../sb4edge-fan.service "$B/etc/systemd/system/multi-user.target.wants/sb4edge-fan.service"
ln -sf ../sb4edge-usbc.service "$B/etc/systemd/system/multi-user.target.wants/sb4edge-usbc.service"
# Windows files (windows/): BitLocker partitions with a clear key (suspended / device encryption not yet bound
# to an account) are opened at boot so Files lists the drive; others unlock in Files with the recovery key.
# NTFS mounts use ntfs-3g only: it refuses read-write on a hibernated (Fast Startup) volume, ntfs3 does not.
# Verified on the 16" (live, 2026-11-15): clear key -> /dev/mapper/bitlk-sda4, ntfs-3g mount of C:.
install -Dm755 /work/windows/sb4edge-windows-unlock "$B/usr/lib/sb4edge/sb4edge-windows-unlock"
install -Dm644 /work/windows/sb4edge-windows-unlock.service "$B/etc/systemd/system/sb4edge-windows-unlock.service"
ln -sf ../sb4edge-windows-unlock.service "$B/etc/systemd/system/multi-user.target.wants/sb4edge-windows-unlock.service"
install -Dm644 /work/windows/mount_options.conf "$B/etc/udisks2/mount_options.conf"
# The Windows system drive (the NTFS volume with Windows/System32, found at boot) is mounted read-only so Linux can't
# damage Windows by accident; GNOME Files' right-click menu offers "Unlock folder" (writable, after a password
# prompt, remembered across reboots) and "Lock folder" on unlocked ones. ENABLED=no in
# /etc/default/sb4edge-windows-mount mounts it the normal way. A BitLocker volume unlocked later in Files is normal.
install -Dm755 /work/windows/sb4edge-windows-mount "$B/usr/lib/sb4edge/sb4edge-windows-mount"
install -Dm644 /work/windows/sb4edge-windows-mount.service "$B/etc/systemd/system/sb4edge-windows-mount.service"
ln -sf ../sb4edge-windows-mount.service "$B/etc/systemd/system/multi-user.target.wants/sb4edge-windows-mount.service"
install -Dm644 /work/windows/org.sb4edge.windows-write.policy "$B/usr/share/polkit-1/actions/org.sb4edge.windows-write.policy"
install -Dm644 /work/windows/sb4edge-unlock-folder.py "$B/usr/share/nautilus-python/extensions/sb4edge-unlock-folder.py"
# HDMI (display/g9): the port's RTD2171 converter only takes HBR2 x4 (17.28 Gbit/s). For the Samsung Odyssey
# G95NC a hotplug helper loads an EDID with 5120x1440 @ 75 Hz while it is connected (cleared on unplug).
install -Dm755 /work/display/g9/sb4edge-hdmi-edid "$B/usr/lib/sb4edge/sb4edge-hdmi-edid"
install -Dm644 /work/display/g9/make-g9-edid.py "$B/usr/lib/sb4edge/make-g9-edid.py"
install -Dm644 /work/display/g9/66-sb4edge-hdmi-edid.rules "$B/etc/udev/rules.d/66-sb4edge-hdmi-edid.rules"
# External monitor brightness (DDC/CI, verified on the Odyssey G95NC over HDMI, 2026-11-15): ddcutil (network packages
# above), uaccess on msm's DP AUX I2C buses only (ddcutil's own rule matches PCI display adapters), and the GNOME
# extension "Brightness control using ddcutil" (daitj/gnome-display-brightness-ddcutil, GPL-3.0, v59 from
# extensions.gnome.org, GNOME 49-50) enabled by default: a slider per monitor in the system menu.
install -Dm644 /work/overlay/70-sb4edge-ddc.rules "$B/usr/lib/udev/rules.d/70-sb4edge-ddc.rules"
EXT=display-brightness-ddcutil@themightydeity.github.com
mkdir -p "$B/usr/share/gnome-shell/extensions/$EXT"
python3 -m zipfile -e "/work/overlay/gnome/$EXT.zip" "$B/usr/share/gnome-shell/extensions/$EXT"
# v59 declares GNOME 49-50 and works on 51 unchanged. Defaults: skip the display-state check (the Odyssey G95NC
# reports D6=x00 and was skipped, stuck on "initializing") and --noverify (verify reads back too early, the retries
# made the slider jump the wrong way).
python3 - "$B/usr/share/gnome-shell/extensions/$EXT/metadata.json" <<"PY"
import json, sys
p = sys.argv[1]; m = json.load(open(p))
m["shell-version"] = sorted(set(m["shell-version"]) | {"51"}, key=int)
json.dump(m, open(p, "w"), indent=2)
PY
X="$B/usr/share/gnome-shell/extensions/$EXT/schemas/org.gnome.shell.extensions.display-brightness-ddcutil.gschema.xml"
python3 - "$X" <<"PY"
import re, sys
p = sys.argv[1]; s = open(p).read()
def default(key, value):
    global s
    s, n = re.subn(r'(<key type="\w" name="%s">\s*<default>)(.*?)(</default>)' % key, lambda m: m.group(1) + value + m.group(3), s, flags=re.S)
    assert n == 1, key
default("disable-display-state-check", "true")
default("ddcutil-additional-args", "'--noverify'")
open(p, "w").write(s)
PY
chroot "$B" glib-compile-schemas "/usr/share/gnome-shell/extensions/$EXT/schemas"
chmod -R u=rwX,go=rX "$B/usr/share/gnome-shell/extensions/$EXT"
# Extensions installed on the reference laptop (overlay/gnome/extensions/*.zip, hidetopbar-multimonitor with sb4edge
# fixes), system-wide and enabled by 90-sb4edge-extensions.gschema.override.
for Z in /work/overlay/gnome/extensions/*.zip; do
	U=$(basename "$Z" .zip); X="$B/usr/share/gnome-shell/extensions/$U"
	rm -rf "$X"; mkdir -p "$X"; python3 -m zipfile -e "$Z" "$X"
	[ ! -d "$X/schemas" ] || chroot "$B" glib-compile-schemas "/usr/share/gnome-shell/extensions/$U/schemas"
	chmod -R u=rwX,go=rX "$X"
	grep -q "\"uuid\": *\"$U\"" "$X/metadata.json" || { echo "extension $U: uuid mismatch"; exit 1; }
done
install -Dm644 /work/overlay/gnome/90-sb4edge-extensions.gschema.override "$B/usr/share/glib-2.0/schemas/90-sb4edge-extensions.gschema.override"
# authd (cloud/OIDC login) and USBGuard are not installed: Ubuntu's defaults made every login/unlock log "PAM service
# gdm-authd was not found" and GNOME's USB protection "Failed to fetch USBGuard parameters".
install -Dm644 /work/overlay/gnome/99_sb4edge.gschema.override "$B/usr/share/glib-2.0/schemas/99_sb4edge.gschema.override"
# Ubuntu's bundled extensions: the dock kept handlers of docks destroyed by a monitor hotplug (hundreds of "already
# disposed" stack traces per minute), AppIndicators threw at every screen lock. Patched here and after every update
# of gnome-shell-ubuntu-extensions (apt hook).
install -Dm755 /work/overlay/gnome/sb4edge-dock-fix "$B/usr/lib/sb4edge/sb4edge-dock-fix"
install -Dm644 /work/overlay/gnome/99-sb4edge-dock-fix "$B/etc/apt/apt.conf.d/99-sb4edge-dock-fix"
chroot "$B" /usr/lib/sb4edge/sb4edge-dock-fix
for f in ubuntu-dock@ubuntu.com/theming.js:sb4edge-dock-fix ubuntu-appindicators@ubuntu.com/settingsManager.js:sb4edge-appindicator-fix ubuntu-dock@ubuntu.com/docking.js:sb4edge-dock-edge-hover ubuntu-dock@ubuntu.com/docking.js:sb4edge-dock-unredirect; do
	X="$B/usr/share/gnome-shell/extensions/${f%%:*}"; [ ! -f "$X" ] || grep -q "${f#*:}" "$X" || { echo "extension patch failed: $f"; exit 1; }
done
# Keeps these GNOME fixes after package and release upgrades: re-runs the dock patches and the login-screen
# fingerprint overlay, restores the PAM line, and adds a new GNOME Shell version to sb4edge's own extensions so a
# GNOME upgrade doesn't silently disable them. After every dpkg run (apt hook) and at every boot before GDM.
install -Dm755 /work/overlay/gnome/sb4edge-gnome-persist "$B/usr/lib/sb4edge/sb4edge-gnome-persist"
install -Dm644 /work/overlay/gnome/sb4edge-gnome-persist.service "$B/usr/lib/systemd/system/sb4edge-gnome-persist.service"
install -Dm644 /work/overlay/gnome/99-sb4edge-gnome-persist "$B/etc/apt/apt.conf.d/99-sb4edge-gnome-persist"
mkdir -p "$B/etc/systemd/system/graphical.target.wants"
ln -sf /usr/lib/systemd/system/sb4edge-gnome-persist.service "$B/etc/systemd/system/graphical.target.wants/sb4edge-gnome-persist.service"
chroot "$B" glib-compile-schemas /usr/share/glib-2.0/schemas
# Panel and keyboard backlight kept across boots (overlay/backlight): at shutdown the login screen resets the brightness to the
# value it cached at boot before systemd-backlight saves it, so every boot started at that value. A service records
# the brightness while an unlocked user session is active; a systemd-backlight@ drop-in writes it back after the save.
install -Dm755 /work/overlay/backlight/sb4edge-backlight "$B/usr/libexec/sb4edge-backlight"
install -Dm644 /work/overlay/backlight/sb4edge-backlight.service "$B/etc/systemd/system/sb4edge-backlight.service"
install -Dm644 /work/overlay/backlight/50-sb4edge-backlight.conf "$B/usr/lib/systemd/system/systemd-backlight@.service.d/50-sb4edge-backlight.conf"
ln -sf ../sb4edge-backlight.service "$B/etc/systemd/system/multi-user.target.wants/sb4edge-backlight.service"
# The real cause (verified 2026-11-15): the login screen dims the panel when idle (idle-brightness 30% = 628/2047)
# and a session started from it keeps that level. GDM compiles /usr/share/gdm/dconf at every start.
install -Dm644 /work/overlay/backlight/95-sb4edge-greeter "$B/usr/share/gdm/dconf/95-sb4edge-greeter"
# Audio (overlay/audio/SOURCE): ADSP topology, four-speaker WSA883x UCM linked under the card's long name
# (DMI vendor-product-version-board) for both sizes, amps kept runtime-active, PipeWire upmix to the woofers.
install -Dm644 /work/overlay/audio/X1E80100-GalaxyBook4Edge-tplg.bin "$B/usr/lib/firmware/updates/qcom/x1e80100/X1E80100-GalaxyBook4Edge-tplg.bin"
install -Dm644 -t "$B/usr/share/alsa/ucm2/Samsung/GalaxyBook4Edge" /work/overlay/audio/ucm/*.conf
mkdir -p "$B/usr/share/alsa/ucm2/conf.d/x1e80100"
for n in NP960XMB_KB1US NP944XMA_MC1US; do
    ln -sf ../../Samsung/GalaxyBook4Edge/GalaxyBook4Edge.conf \
        "$B/usr/share/alsa/ucm2/conf.d/x1e80100/SAMSUNGELECTRONICSCO.LTD.-GalaxyBook4Edge-2.1-$n.conf"
done
install -Dm644 /work/overlay/audio/62-sb4edge-wsa883x.rules "$B/usr/lib/udev/rules.d/62-sb4edge-wsa883x.rules"
install -Dm644 /work/overlay/audio/50-sb4edge-upmix.conf "$B/usr/share/pipewire/client.conf.d/50-sb4edge-upmix.conf"
install -Dm644 /work/overlay/audio/50-sb4edge-upmix.conf "$B/usr/share/pipewire/pipewire-pulse.conf.d/50-sb4edge-upmix.conf"
# Internal mics: the VA capture graph only starts with 4 channels (51-sb4edge-mic.conf explains)
install -Dm644 /work/overlay/audio/51-sb4edge-mic.conf "$B/usr/share/wireplumber/wireplumber.conf.d/51-sb4edge-mic.conf"
# Mic gain +32 dB (UCM HiFi.conf) and WebRTC noise suppression as the default input (the DMICs hiss at that gain)
install -Dm644 /work/overlay/audio/60-sb4edge-mic-ns.conf "$B/usr/share/pipewire/pipewire.conf.d/60-sb4edge-mic-ns.conf"
# Fluence (fluence/NOTES.md): "Microphone (Fluence)", the default input. Topology MultiMedia8 runs Samsung's mic EQ +
# Qualcomm Fluence NN noise suppression on the ADSP with Samsung's calibration (kernel patch 0013); the DSP fetches the
# Fluence modules from the Windows ADSP package through adsprpcd (quic/fastrpc) in sb4edge-fluence.service.
grep -aq MultiMedia8 /work/overlay/audio/X1E80100-GalaxyBook4Edge-tplg.bin || { echo "topology lacks MultiMedia8 (Fluence)"; exit 1; }
FD="$B/usr/lib/sb4edge/fluence"; FB=/work/fluence/fastrpc-build/usr/local
WADSP=/work/windows-files/adsp   # from the Windows driver qcsubsys_ext_adsp8380 (ADSP folder)
[ -f "$WADSP/fluence_nn_module_fvxiii.so.1" ] || { echo "Windows ADSP package (Fluence modules) missing"; exit 1; }
install -Dm755 "$FB/sbin/adsprpcd" "$FD/adsprpcd"
mkdir -p "$FD/lib" "$FD/adsp"
cp -a "$FB"/lib/libadsprpc.so* "$FB"/lib/libadsp_default_listener.so* "$FD/lib/"
cp -a "$WADSP"/. "$FD/adsp/"
install -m644 /work/overlay/audio/fluence/README "$FD/README"
install -Dm644 /work/overlay/audio/fluence/sb4edge-fluence.service "$B/usr/lib/systemd/system/sb4edge-fluence.service"
ln -sf /usr/lib/systemd/system/sb4edge-fluence.service "$B/etc/systemd/system/multi-user.target.wants/sb4edge-fluence.service"
# The PipeWire source is added after the card is up by a user service (an ALSA node in pipewire.conf.d is opened at
# daemon start, before the card exists, and its failure kills PipeWire: the desktop portal then hangs every app).
install -m755 /work/overlay/audio/fluence/sb4edge-fluence-source "$FD/sb4edge-fluence-source"
install -Dm644 /work/overlay/audio/fluence/sb4edge-fluence-source.service "$B/usr/lib/systemd/user/sb4edge-fluence-source.service"
mkdir -p "$B/etc/systemd/user/pipewire.service.wants"
ln -sf /usr/lib/systemd/user/sb4edge-fluence-source.service "$B/etc/systemd/user/pipewire.service.wants/sb4edge-fluence-source.service"
rm -f "$B/usr/share/pipewire/pipewire.conf.d/61-sb4edge-fluence.conf"
# Ambient light sensor (overlay/sensors): VEML3328 behind the ADSP (Qualcomm SSC), data type "color". The ADSP sensors
# domain reads/writes its registry through adsprpcd sensorspd (sb4edge-sensors.service; the firmware asserts and takes
# the laptop down if the registry is read-only, as with hexagonrpcd); iio-sensor-proxy 3.9 + libssc (build-ssc.sh) feed
# GNOME's automatic screen brightness; sb4edge-kbd-ambient dims the keyboard backlight one step in dim light, off in bright light.
QS=/usr/share/qcom/x1e80100/Samsung/galaxy-book4-edge-16
[ -s /work/sensors/qcom-root/sensors/sns_reg.conf ] || { echo "sensor registry/config (sensors/qcom-root) missing"; exit 1; }
mkdir -p "$B$QS"; cp -a /work/sensors/qcom-root/sensors /work/sensors/qcom-root/socinfo "$B$QS/"
chown -R 0:0 "$B$QS"; chmod -R u=rwX,go=rX "$B$QS"
install -Dm755 /work/overlay/sensors/sb4edge-sensors-setup "$B/usr/lib/sb4edge/sb4edge-sensors-setup"
install -Dm644 /work/overlay/sensors/sb4edge-sensors.service "$B/etc/systemd/system/sb4edge-sensors.service"
ln -sf ../sb4edge-sensors.service "$B/etc/systemd/system/multi-user.target.wants/sb4edge-sensors.service"
install -Dm644 /work/overlay/sensors/sb4edge-sensors.tmpfiles "$B/usr/lib/tmpfiles.d/sb4edge-sensors.conf"
ln -sf /dev/null "$B/etc/systemd/system/hexagonrpcd.service"   # read-only file service: crashes the sensors domain
SS=/work/out/ssc/root
[ -x "$SS/usr/libexec/iio-sensor-proxy" ] || { echo "out/ssc missing (run build-ssc.sh)"; exit 1; }
install -Dm644 "$SS/usr/lib/aarch64-linux-gnu/libssc.so.2" "$B/usr/lib/sb4edge/ssc/libssc.so.2"
install -m755 "$SS/usr/libexec/iio-sensor-proxy" "$SS/usr/bin/ssccli" "$B/usr/lib/sb4edge/ssc/"
install -Dm644 /work/overlay/sensors/iio-sensor-proxy-sb4edge.conf "$B/etc/systemd/system/iio-sensor-proxy.service.d/sb4edge.conf"
install -Dm644 /work/overlay/sensors/81-sb4edge-ssc-light.rules "$B/usr/lib/udev/rules.d/81-sb4edge-ssc-light.rules"
install -Dm755 /work/overlay/sensors/sb4edge-kbd-ambient "$B/usr/libexec/sb4edge-kbd-ambient"
install -Dm644 /work/overlay/sensors/sb4edge-kbd-ambient.service "$B/usr/lib/systemd/user/sb4edge-kbd-ambient.service"
mkdir -p "$B/etc/systemd/user/graphical-session.target.wants"
ln -sf /usr/lib/systemd/user/sb4edge-kbd-ambient.service "$B/etc/systemd/user/graphical-session.target.wants/sb4edge-kbd-ambient.service"
# rEFInd boot menu for the installed system (refind/): sb4edge-refind.service copies it to the internal EFI partition
# and keeps it first in the boot order; GRUB's own menu is hidden and Windows detection is left to rEFInd.
RD="$B/usr/lib/sb4edge/refind"; rm -rf /iso/rxi; mkdir -p /iso/rxi; dpkg-deb -x /work/refind/refind_*_arm64.deb /iso/rxi
install -Dm644 /iso/rxi/usr/share/refind/refind/refind_aa64.efi "$RD/refind_aa64.efi"
install -m644 /work/refind/refind-installed.conf "$RD/refind.conf"
mkdir -p "$RD/themes"; cp -r /work/refind/theme/sb4edge "$RD/themes/"
install -m755 /work/refind/sb4edge-refind-install "$RD/sb4edge-refind-install"
install -Dm644 /work/refind/sb4edge-refind.service "$B/usr/lib/systemd/system/sb4edge-refind.service"
ln -sf /usr/lib/systemd/system/sb4edge-refind.service "$B/etc/systemd/system/multi-user.target.wants/sb4edge-refind.service"
install -Dm644 /work/refind/zz-sb4edge-refind.cfg "$B/etc/default/grub.d/zz-sb4edge-refind.cfg"
log "wrap kernel with stubble (ukify runs in the build container)"
I="$B/boot/vmlinuz-$KVER"
DTB="$B/usr/lib/linux-image-$KVER/qcom/x1e84100-samsung-galaxy-book4-edge-16.dtb"
DTS=$(dtc -I dtb -O dts "$DTB" 2>/dev/null)   # not piped into grep -q: with pipefail, SIGPIPE fails the check
for c in parade,ps8830 samsung,galaxy-book4-edge-kbd-backlight samsung,galaxybook-battery ovti,ov02c10; do
    [[ $DTS == *"\"$c\""* ]] || { echo "DTB lacks $c (wrong kernel deb?)"; exit 1; }
done
# SD card reader (sdhc_2 enabled, card detect gpio71) since 7.4rc2-12 (patches/sb4edge-local/0014)
[[ $DTS == *"sdc2-card-det-state"* ]] || { echo "DTB lacks the SD card reader (0014)"; exit 1; }
# Video codec (iris, qcvss8380.mbn from fw/) enabled since 7.4rc3-2
[[ $DTS == *"qcvss8380.mbn"* ]] || { echo "DTB lacks the video codec (iris)"; exit 1; }
[ -f "$FW/qcvss8380.mbn" ] || { echo "video codec firmware missing"; exit 1; }
# The camera (CCI0 + CAMSS + OV02C10) is in the deb's DTB since 7.4rc2-10 (patches/sb4edge-local/0012), so the
# default entries and installed systems have it; the separate camera-test entry is gone.
ukify build --stub=/usr/lib/stubble/stubble.efi --linux="$I" --hwids=/work/overlay/hwids \
    --devicetree-auto="$B/usr/lib/linux-image-$KVER/qcom/x1e84100-samsung-galaxy-book4-edge-16.dtb" \
    --uname="$KVER" --output="$I.stubble"
mv "$I.stubble" "$I"
python3 - "$I" <<"PY"
import pefile, sys
p = pefile.PE(sys.argv[1], fast_load=True)
names = [s.Name.rstrip(b"\0").decode() for s in p.sections]
print("sections:", names)
assert any(n.startswith(".dtbauto") for n in names), "kernel was not wrapped with stubble"
PY
ls -la "$B/boot"

# The kernel for the live boot entry (the live initrd is built at the end, from the upgraded layers).
cp "$B/boot/vmlinuz-$KVER" /iso/vmlinuz-sb4edge

log "chroot teardown"
umount "$B/cdrom"; for d in dev/pts dev sys proc; do umount "$B/$d"; done
# /cdrom was only the chroot bind-mount point; the stock squashfs has none, and the installer (subiquity
# configure_apt) fails with "File exists" when it creates its own.
rmdir "$B/cdrom"

log "collect changed dpkg stanzas"
python3 /work/dpkgstatus.py diff /iso/status.before "$B/var/lib/dpkg/status" /iso/changed.json

log "rebuild base layer"
mksquashfs "$B" $SRC/casper/minimal.squashfs.new $SQ >/dev/null
mv $SRC/casper/minimal.squashfs.new $SRC/casper/minimal.squashfs
DELTA=$(( $(du -sB1 "$B" | cut -f1) - BASE_BEFORE ))
echo "base size delta: $DELTA"
echo $(( $(cat $SRC/casper/minimal.size) + DELTA )) > $SRC/casper/minimal.size
rm -rf "$B"

log "upgrade desktop layer (minimal.standard) over the upgraded base"
# The layer's tree is the overlay upperdir, so upgraded files (and whiteouts/opaque dirs for
# anything removed) land in this layer only. Its dpkg status first gets the base changes.
S=/iso/std M=/iso/std-m
rm -rf $S /iso/std-w $M /iso/std-b; mkdir -p /iso/std-w $M /iso/std-b
unsquashfs -no-progress -d $S $SRC/casper/minimal.standard.squashfs >/dev/null
STD_BEFORE=$(du -sB1 $S | cut -f1)
python3 /work/dpkgstatus.py merge $S/var/lib/dpkg/status /iso/changed.json /iso/status.before
cp $S/var/lib/dpkg/status /iso/std-status.before
rm -rf /iso/std-lists.orig; [ ! -e $S/var/lib/apt/lists ] || cp -a $S/var/lib/apt/lists /iso/std-lists.orig
mount -t squashfs -o loop,ro $SRC/casper/minimal.squashfs /iso/std-b
mount -t overlay overlay -o lowerdir=/iso/std-b,upperdir=$S,workdir=/iso/std-w,index=off,redirect_dir=off,metacopy=off $M
for d in proc sys dev dev/pts; do mount --bind /$d $M/$d; done
chroot_net_upgrade $M
# The standard layer's upgrade may bring its own copies of files fixed in the base layer: fix them here too.
sb4edge_cleanup $M
chroot $M /usr/lib/sb4edge/sb4edge-dock-fix
# Camera: libcamera rebuilt with the OV02C10 sensor helper (extra/libcamera, out/libcamera). It lives in this
# layer, so it is replaced here (a copy in the base layer would be shadowed). Only packages already installed
# are replaced, and they are held so an archive update does not drop the helper.
# BitLocker: cryptsetup rebuilt to skip unknown VMK entries (build-cryptsetup.sh, patches/cryptsetup); recent
# Windows 11 volumes were otherwise rejected, so GNOME Files could not unlock the Windows partition.
# Resources: Adreno GPU page (build-resources.sh, patches/resources).
# Fingerprint: libfprint with SDCP (extra/libfprint: MR !547 plus the model certificate fix); without SDCP the
# EgisTec 1c7a:05a1 keeps no enrolled print.
mkdir -p $M/tmp/lc; cp /work/out/libcamera/*.deb /work/out/cryptsetup/*.deb /work/out/resources/*.deb /work/out/libfprint/libfprint-2-2_*.deb /work/out/libfprint/gir1.2-fprint-2.0_*.deb $M/tmp/lc/
chroot $M /bin/bash -euxc '
debs=(); pk=()
for d in /tmp/lc/*.deb; do p=$(dpkg-deb -f "$d" Package)
    if dpkg-query -W -f="\${Status}" "$p" 2>/dev/null | grep -q "ok installed"; then debs+=("$d"); pk+=("$p"); fi; done
dpkg -i "${debs[@]}"; apt-mark hold "${pk[@]}"; rm -rf /tmp/lc
# Holds do not stop every frontend (GNOME Software put stock libcamera back over ours): pin the +sb4edge builds too.
printf "Package: %s\nPin: version *+sb4edge*\nPin-Priority: 1001\n" "${pk[*]}" > /etc/apt/preferences.d/sb4edge-rebuilt
dpkg-query -W -f="\${Version}" libcryptsetup12 | grep -q sb4edge
dpkg-query -W -f="\${Version}" libfprint-2-2 | grep -q sb4edge
# Fingerprint for sudo, polkit and login too (common-auth): one try, 10 s, then the password prompt as before.
DEBIAN_FRONTEND=noninteractive pam-auth-update --enable fprintd
grep -q pam_fprintd.so /etc/pam.d/common-auth
! dpkg-query -W -f="\${Status}" resources 2>/dev/null | grep -q "ok installed" || dpkg-query -W -f="\${Version}" resources | grep -q sb4edge'
# The sensor's prints live on the chip and are shared with Windows; enrolling the same finger on both sides makes
# each delete the other's. sb4edge-fingerprint-import gives a Linux user a finger enrolled in Windows Hello once that
# user touches the sensor with it (the chip's prints carry no owner). At boot and login it only reports new prints,
# unless AUTO_IMPORT=yes in /etc/default/sb4edge-fingerprint (touch-free, single-user laptops only).
install -Dm755 /work/overlay/fingerprint/sb4edge-fingerprint-import $M/usr/sbin/sb4edge-fingerprint-import
install -Dm644 /work/overlay/fingerprint/sb4edge-fingerprint.default $M/etc/default/sb4edge-fingerprint
install -Dm644 /work/overlay/fingerprint/sb4edge-fingerprint-import.service $M/usr/lib/systemd/system/sb4edge-fingerprint-import.service
ln -sf /usr/lib/systemd/system/sb4edge-fingerprint-import.service $M/etc/systemd/system/multi-user.target.wants/sb4edge-fingerprint-import.service
install -Dm644 /work/overlay/fingerprint/sb4edge-fingerprint.pam-config $M/usr/share/pam-configs/sb4edge-fingerprint
chroot $M env DEBIAN_FRONTEND=noninteractive pam-auth-update --enable sb4edge-fingerprint
grep -q sb4edge-fingerprint-import $M/etc/pam.d/common-session
# Fingerprint login straight from the GDM user chooser: sb4edge-fp-identify (root, D-Bus activated) verifies the
# finger against each enrolled user while the greeter's user list is shown; the greeter (loginDialog.js overlay
# built by sb4edge-gdm-fp-overlay, loaded only by the greeter's shell) selects the matching user, and the
# gdm-fingerprint PAM stack accepts that fresh one-time match (sb4edge-fp-token), so one touch logs in.
for f in sb4edge-fp-identify sb4edge-fp-token sb4edge-gdm-fp-overlay; do install -Dm755 /work/overlay/fingerprint/$f $M/usr/lib/sb4edge/$f; done
install -Dm644 /work/overlay/fingerprint/org.sb4edge.FingerprintIdentify.conf $M/usr/share/dbus-1/system.d/org.sb4edge.FingerprintIdentify.conf
install -Dm644 /work/overlay/fingerprint/org.sb4edge.FingerprintIdentify.dbus-service $M/usr/share/dbus-1/system-services/org.sb4edge.FingerprintIdentify.service
install -Dm644 /work/overlay/fingerprint/sb4edge-fp-identify.service $M/usr/lib/systemd/system/sb4edge-fp-identify.service
install -Dm644 /work/overlay/fingerprint/org.gnome.Shell@gdm-sb4edge-fp.conf "$M/usr/lib/systemd/user/org.gnome.Shell@gdm.service.d/sb4edge-fp.conf"
chroot $M /usr/lib/sb4edge/sb4edge-gnome-persist
grep -q sb4edge-fp-token $M/etc/pam.d/gdm-fingerprint || { echo "gdm-fingerprint: user-chooser token line missing"; exit 1; }
install -Dm644 /work/extra/libcamera/ov02c10.yaml $M/usr/share/libcamera/ipa/simple/ov02c10.yaml
install -Dm644 /work/extra/libcamera/configuration.yaml $M/usr/share/libcamera/configuration.yaml
install -Dm644 /work/extra/libcamera/52-sb4edge-hide-raw-camss.conf $M/usr/share/wireplumber/wireplumber.conf.d/52-sb4edge-hide-raw-camss.conf
# Snapshot records VP8 with GStreamer's "Profile Realtime" preset, which leaves vp8enc at its 256 kbit/s default
# (unwatchably blocky at 1080p). Divert the stock preset file and add 8 Mbit/s VBR + 4 threads to that profile
# (measured 32.6 fps at 1080p from the camera, no backlog).
P=/usr/share/gstreamer-1.0/presets/GstVP8Enc.prs
chroot $M dpkg-divert --local --rename --add $P
sed "/^\[Profile Realtime\]/a target-bitrate=8000000\nthreads=4\nend-usage=vbr\nundershoot=95\nbuffer-size=6000\nbuffer-initial-size=4000\nbuffer-optimal-size=5000" \
    "$M$P.distrib" > "$M$P"
grep -q "^target-bitrate=8000000" "$M$P" || { echo "VP8 preset patch failed"; exit 1; }
for d in dev/pts dev sys proc; do umount $M/$d; done
umount $M /iso/std-b
rm -rf $S/var/lib/apt/lists $S/var/cache/apt/*.bin
[ ! -e /iso/std-lists.orig ] || mv /iso/std-lists.orig $S/var/lib/apt/lists
python3 /work/dpkgstatus.py diff /iso/std-status.before $S/var/lib/dpkg/status /iso/changed-std.json
mksquashfs $S $SRC/casper/minimal.standard.squashfs.new $SQ \
    -xattrs-exclude '^trusted\.overlay\.(origin|impure|nlink|upper|redirect|metacopy)$' >/dev/null
mv $SRC/casper/minimal.standard.squashfs.new $SRC/casper/minimal.standard.squashfs
STDDELTA=$(( $(du -sB1 $S | cut -f1) - STD_BEFORE ))
echo "desktop layer size delta: $STDDELTA"
echo $(( $(cat $SRC/casper/minimal.standard.size) + STDDELTA )) > $SRC/casper/minimal.standard.size
rm -rf $S /iso/std-w $M /iso/std-b

log "upgrade live layer (minimal.standard.live) over the upgraded desktop and base layers"
# The live session's own packages (casper, installer support) are upgraded the same way as the desktop layer.
LV=/iso/lv LM=/iso/lv-m
rm -rf $LV $LM /iso/lv-w /iso/lv-b /iso/lv-s; mkdir -p $LM /iso/lv-w /iso/lv-b /iso/lv-s
unsquashfs -no-progress -d $LV $SRC/casper/minimal.standard.live.squashfs >/dev/null
LIVE_BEFORE=$(du -sB1 $LV | cut -f1)
python3 /work/dpkgstatus.py merge $LV/var/lib/dpkg/status /iso/changed.json /iso/status.before
python3 /work/dpkgstatus.py merge $LV/var/lib/dpkg/status /iso/changed-std.json /iso/std-status.before
rm -rf /iso/lv-lists.orig; [ ! -e $LV/var/lib/apt/lists ] || cp -a $LV/var/lib/apt/lists /iso/lv-lists.orig
mount -t squashfs -o loop,ro $SRC/casper/minimal.squashfs /iso/lv-b
mount -t squashfs -o loop,ro $SRC/casper/minimal.standard.squashfs /iso/lv-s
mount -t overlay overlay -o lowerdir=/iso/lv-s:/iso/lv-b,upperdir=$LV,workdir=/iso/lv-w,index=off,redirect_dir=off,metacopy=off $LM
for d in proc sys dev dev/pts; do mount --bind /$d $LM/$d; done
chroot_net_upgrade $LM
for d in dev/pts dev sys proc; do umount $LM/$d; done
umount $LM /iso/lv-s /iso/lv-b
rm -rf $LV/var/lib/apt/lists $LV/var/cache/apt/*.bin
[ ! -e /iso/lv-lists.orig ] || mv /iso/lv-lists.orig $LV/var/lib/apt/lists
mksquashfs $LV $SRC/casper/minimal.standard.live.squashfs.new $SQ \
    -xattrs-exclude '^trusted\.overlay\.(origin|impure|nlink|upper|redirect|metacopy)$' >/dev/null
mv $SRC/casper/minimal.standard.live.squashfs.new $SRC/casper/minimal.standard.live.squashfs
echo $(( $(cat $SRC/casper/minimal.standard.live.size) + $(du -sB1 $LV | cut -f1) - LIVE_BEFORE )) > $SRC/casper/minimal.standard.live.size
rm -rf $LV $LM /iso/lv-w /iso/lv-b /iso/lv-s

log "live initrd (initramfs-tools + casper) via overlay of live layers"
L=/iso/live; rm -rf $L; mkdir -p $L/{base,std,live,upper,work,root}
mount -t squashfs -o loop,ro $SRC/casper/minimal.squashfs $L/base
mount -t squashfs -o loop,ro $SRC/casper/minimal.standard.squashfs $L/std
mount -t squashfs -o loop,ro $SRC/casper/minimal.standard.live.squashfs $L/live
mount -t overlay overlay -o lowerdir=$L/live:$L/std:$L/base,upperdir=$L/upper,workdir=$L/work $L/root
for d in proc sys dev; do mount --bind /$d $L/root/$d; done
# The casper hook writes a random UUID (uuidgen -r); casper only accepts a medium whose
# .disk/casper-uuid-generic matches it, so run after casper and pin the ISO's UUID.
cat > $L/root/etc/initramfs-tools/hooks/zz-sb4edge-casper-uuid <<HOOK
#!/bin/sh
PREREQ="casper"
prereqs() { echo "\$PREREQ"; }
case "\$1" in prereqs) prereqs; exit 0 ;; esac
mkdir -p "\$DESTDIR/conf/conf.d"
echo "$(cat $SRC/.disk/casper-uuid-generic)" > "\$DESTDIR/conf/uuid.conf"
echo 'ROOT=""' > "\$DESTDIR/conf/conf.d/default_root"
HOOK
chmod +x $L/root/etc/initramfs-tools/hooks/zz-sb4edge-casper-uuid
chroot $L/root mkinitramfs -o /tmp/initrd-sb4edge $KVER
mkdir -p /iso/chk && (cd /iso/chk && chroot $L/root unmkinitramfs /tmp/initrd-sb4edge /tmp/chk && { cat $L/root/tmp/chk/main/conf/uuid.conf $L/root/tmp/chk/conf/uuid.conf 2>/dev/null || true; }; rm -rf $L/root/tmp/chk)
echo "expected uuid: $(cat $SRC/.disk/casper-uuid-generic)"
cp $L/root/tmp/initrd-sb4edge $SRC/casper/initrd-sb4edge
for d in proc sys dev; do umount $L/root/$d; done
umount $L/root $L/live $L/std $L/base
rm -rf $L
mv /iso/vmlinuz-sb4edge $SRC/casper/vmlinuz-sb4edge
ls -la $SRC/casper/*sb4edge*

log "merge dpkg status into upper layers"
for f in $SRC/casper/minimal.*.squashfs; do
    case "$(basename $f)" in minimal.standard.squashfs|minimal.standard.live.squashfs) continue;; esac
    d=/iso/layer; rm -rf $d; unsquashfs -no-progress -d $d $f >/dev/null
    if [ -f $d/var/lib/dpkg/status ]; then
        python3 /work/dpkgstatus.py merge $d/var/lib/dpkg/status /iso/changed.json /iso/status.before
        case "$(basename $f)" in minimal.standard.*)
            python3 /work/dpkgstatus.py merge $d/var/lib/dpkg/status /iso/changed-std.json /iso/std-status.before ;;
        esac
        mksquashfs $d $f.new $SQ >/dev/null && mv $f.new $f
        echo "  merged $(basename $f)"
    fi
done
rm -rf /iso/layer

log "installer sizes"
# Source sizes are cumulative: both grow by the base delta, the full desktop also by its layer delta.
python3 - $SRC/casper/install-sources.yaml $DELTA $STDDELTA <<"PY2"
import re, sys
p, base, std = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
out, path = [], None
for line in open(p).read().splitlines():
    m = re.match(r"^  path: (\S+)$", line)
    if m:
        path = m.group(1)
    m = re.match(r"^(  size: )(\d+)$", line)
    if m:
        line = m.group(1) + str(int(m.group(2)) + base + (std if path == "minimal.standard.squashfs" else 0))
    out.append(line)
open(p, "w").write("\n".join(out) + "\n")
PY2
# The installer installs kernel.default and removes every other kernel found in the image (QEMU install test
# 2026-11-14: linux-image-7.4.0-rc2-sb4edge removed, linux-generic-hwe 7.0 installed and booted). Point it at ours.
sed -i "s/^  default: linux-generic-hwe-[0-9.]*$/  default: linux-image-${KVER}/" $SRC/casper/install-sources.yaml
grep -q "^  default: linux-image-${KVER}$" $SRC/casper/install-sources.yaml
grep -E "path:|size:|default: linux" $SRC/casper/install-sources.yaml

log "grub menu"
cp /work/overlay/grub.cfg $SRC/boot/grub/grub.cfg
if [ "${SB4_DEV:-0}" = 1 ]; then
    # Development build: first entry chains to sb4dev/grub.cfg on the stick's "writable" partition (SSH keys,
    # Tailscale state, test kernels live there; see dev/). Falls back to the normal entry when it is absent.
    python3 - $SRC/boot/grub/grub.cfg <<"PY2"
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("set timeout=1\n", "set timeout=1\nset default=0\nset fallback=1\n", 1)
dev = """menuentry "Galaxy Book4 Edge dev boot (writable/sb4dev/grub.cfg)" {
    search --no-floppy --label writable --set=w
    configfile ($w)/sb4dev/grub.cfg
}
"""
i = s.index("menuentry ")
open(p, "w").write(s[:i] + dev + s[i:])
PY2
fi

log "md5sums"
(cd $SRC && find . -type f ! -name md5sum.txt ! -path "./boot/boot.cat" -print0 | xargs -0 md5sum > md5sum.txt)

log "build iso"
# -partition_offset 16 (stock uses 0): partition 1 then holds a mountable iso9660 copy of the filesystem, so
# casper mounts /dev/sdX1 instead of the whole disk, and the other partitions (e.g. "writable" for
# persistence) stay mountable. With offset 0, the whole-disk mount claims the disk and persistence fails.
# EFI partition: our own GRUB (refind/build-grub.sh, silent early config; Ubuntu's signed ISO GRUB prints
# "error: file '/boot/' not found.") is the boot program, with the live grub.cfg (menu hidden, Esc shows it).
# rEFInd lives only on the internal disk (installed system). Secure Boot is off, so GRUB needs no signing. 16 MiB FAT.
RF=/work/refind
# Label SB4EDGE: the installed rEFInd recognises this stick by it and shows one tile for EFI/boot/sb4live.efi
# (it skips SB4EDGE:\EFI\boot\bootaa64.efi, the same GRUB, so the stick is not listed twice).
rm -f /iso/efi.img; mkfs.vfat -C -n SB4EDGE /iso/efi.img 16384 >/dev/null
mmd -i /iso/efi.img ::EFI ::EFI/boot
bash $RF/build-grub.sh >/dev/null
mcopy -i /iso/efi.img $RF/grubaa64-live.efi ::EFI/boot/bootaa64.efi
mcopy -i /iso/efi.img $RF/grubaa64-live.efi ::EFI/boot/sb4live.efi
mdir -/ -i /iso/efi.img ::EFI/boot | grep -cE "bootaa64|sb4live" | grep -qx 2 || { echo "EFI image incomplete"; exit 1; }
mkdir -p /work/out
rm -f "$OUT"
xorriso -as mkisofs -r -V "Ubuntu 27.04 arm64" -o "$OUT" \
  --protective-msdos-label -partition_cyl_align off -partition_offset 16 --mbr-force-bootable \
  -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b /iso/efi.img -appended_part_as_gpt \
  -c /boot/boot.cat -e --interval:appended_partition_2:all:: -no-emul-boot \
  "$SRC" 2>&1 | tail -3
ls -la "$OUT"
(cd /work/out && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256")
log done
