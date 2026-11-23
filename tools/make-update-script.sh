#!/bin/sh
# Builds out/sb4edge-update.sh: a single script that brings an installed SB4-Edge-Linux release up to date with the
# fixes made since that release, without reinstalling. The fixed files are embedded (gzip + base64) with their
# SHA-256, so the script needs no network access (except to install missing packages for the Windows drive item). Build first: ./build.sh ssc usbc libfprint
#   tools/make-update-script.sh
set -eu
cd "$(dirname "$0")/.."
OUT=out/sb4edge-update.sh
REV=$(git describe --always --dirty)
LFP=$(ls out/libfprint/libfprint-2-2_*_arm64.deb)
GIR=$(ls out/libfprint/gir1.2-fprint-2.0_*_arm64.deb)
RES=$(ls out/resources/resources_*_arm64.deb)
# The NPU module is built against this kernel build: it is installed only next to the same kernel package.
KDEB=$(ls out/linux-image-*-sb4edge_*_arm64.deb)
KREL=$(basename "$KDEB" | sed 's/^linux-image-\(.*\)_\(.*\)_arm64\.deb$/\1/')
KVER=$(basename "$KDEB" | sed 's/^linux-image-\(.*\)_\(.*\)_arm64\.deb$/\2/')

emb() { # emb VAR file
	printf '%s_SHA=%s\n' "$1" "$(shasum -a 256 "$2" | cut -d' ' -f1)"
	printf "%s_B64='" "$1"
	gzip -9cn "$2" | base64 | tr -d '\n'
	printf "'\n"
}

{
cat <<EOF
#!/bin/sh
# SB4-Edge-Linux update for an installed system (release v2026.11.16-27.04.2), from commit $REV.
# Run once:  sudo sh sb4edge-update.sh   (then log out and back in, or restart for the boot/Wi-Fi/Windows items)
# Originals are kept in /var/lib/sb4edge/update-backup/<date>/. Running it again changes nothing.
#
# 2026-11-18, crashes found on an installed laptop:
#  1. Sensor service (iio-sensor-proxy) aborted when an app watching the sensors closed at the wrong moment, leaving
#     automatic brightness off until a reboot. Replaced with a build that skips that case; it also restarts itself.
#  2. Fingerprint import crashed while exiting, after its work was done.
#  3. Odyssey G9 HDMI EDID script crashed on EDIDs without the timings it expects; it now stops with a message.
# 2026-11-18, independent review:
#  4. Fingerprint import no longer gives Windows Hello prints to your account without proof: run
#     "sudo sb4edge-fingerprint-import" and touch the sensor (AUTO_IMPORT=yes in /etc/default/sb4edge-fingerprint
#     brings back the touch-free import, for laptops where nobody else uses Windows Hello).
#  5. Fingerprint library: the repaired sensor certificate now goes through the full certificate check.
#  6. Fan: if the CPU temperature cannot be read, the fan runs at full speed instead of stopping.
#  7. USB-C helper: a disk behind LUKS/LVM or used for swap on a USB-C port keeps its power at start-up
#     (takes effect at the next boot).
#  8. Wi-Fi: Ubuntu's firmware now has this laptop's board entry (same data); the project's copy, which would hide
#     future Ubuntu Wi-Fi firmware updates, is removed (takes effect at the next boot).
#  9. Keyboard backlight and room light: kept at your level in normal light, one step dimmer below 10 lux, off above
#     40 lux (as on Windows) and while the display is off. Settings: DIM_BELOW=, OFF_ABOVE=, DIM_BY= in
#     /etc/default/sb4edge-kbd-ambient (from the next login).
# 10. NPU in Resources: a read-only module reads the Hexagon NPU's load (it never wakes the NPU), and Resources gets
#     an NPU page (load, temperature, firmware state) plus Oryon CPU temperature and core count.
# 11. Video decoder (Iris): fixes a crash report while seeking in videos, and adds what VA-API needs, so apps using
#     Ubuntu's qcom-va-driver (ffmpeg and other VA-API apps) decode H.264/HEVC/AV1 in hardware (from the next boot).
# 2026-11-20/21:
# 12. Wi-Fi driver: Resources and "iw" froze for seconds at a time once one firmware statistics request had timed out
#     (ath12k waited 3 s on every later one). Fixed module, used from the next boot.
# 13. Boot: no "Loading Linux ..." text between rEFInd and the boot splash, no blinking cursor.
# 14. GNOME extensions of the reference laptop, installed system-wide and on by default (unless you chose your own):
#     auto-hiding top bar on every monitor, top bar organizer, weather, screenshot without the selection box, OCR
#     from a screen area, RustDesk window helper, and overview: Esc / a click on empty space closes it and a click on
#     a neighbouring workspace switches to it. Ubuntu's snap search add-on (broke Esc in the overview) is turned off.
# 15. Ubuntu Dock: no more flicker or hiding by itself over maximized windows (Firefox) on the 166 % panel; reveals
#     reliably at the screen edge and forgives small pointer jumps. Fullscreen windows (Citrix, RustDesk) on that
#     panel no longer jump a few pixels when the top bar appears.
# 16. Fingerprint: one touch on the login screen's user list picks your account and logs in; the lock screen takes
#     a finger even with text in the password field.
# 17. Windows drive read-only, with "Unlock folder" / "Lock folder" (and Rename / Delete for unlocked folders) in
#     GNOME Files' right-click menu, from the next boot. ENABLED=no in /etc/default/sb4edge-windows-mount keeps it
#     writable as before.
# 18. These GNOME fixes are re-applied after package and release upgrades (sb4edge-gnome-persist), which also gives
#     the login screen your display setup: with two monitors the desktop no longer stutters for minutes after login.
# 2026-11-22:
# 19. Right-click menus: smoother edges in all apps (no dark outline line); desktop icon menus no longer cut off.
#     Boot: no more "Error running install command ... snd-pcm-oss" (sound OSS-emulation preload lines that fail in
#     the initramfs are removed; next boot).
# 20. Battery: the percentage no longer drops to 4 %/7 % or jumps to 100 % for a moment; Resources shows the design
#     capacity (next boot).
# 21. The project's own GNOME extensions (screenshot, OCR, overview, RustDesk window helper) are now one extension,
#     Book 4 Edge Tweaks XR, with a switch per feature in its preferences; the four old ones are removed. It also cleans
#     up after the extra top bars of the auto-hiding top bar ("already disposed" errors and leaked work after every
#     monitor change or unlock), and shows the accessibility menu only when "Always Show Accessibility Menu" is on,
#     on every top bar (GNOME showed it whenever Large Text was on). From the next login.
# 22. Battery life: the auto-hiding top bar and the Ubuntu Dock no longer poll the pointer (about 20 wakeups a second
#     less while idle); the fan control and the backlight memory no longer start processes every 2-3 s; the USB-C
#     helper reads fewer registers per check (from the next boot).
# 23. Wi-Fi driver: after the access point switched channels (DFS), every Wi-Fi status check blocked 3 s (ath12k
#     counted the restarted connection twice). Fixed module, used from the next boot.
# 24. Boot: the Ubuntu logo shows once (the splash waits for the display driver instead of flashing on the firmware
#     framebuffer first). Kernel crashes leave their log again (kdump falls back to vmcore-dmesg).
# 25. Boot: shorter black screen after rEFInd. The initramfs no longer carries other laptops' DSP firmware
#     (113 -> 76 MB for the boot loader to read), and is built for this laptop's hardware only (184 instead of ~2570
#     drivers, 52 MB). The full one stays as a rescue entry: hold Esc after choosing Ubuntu in rEFInd. The NPU's
#     message driver loads before the DSPs start (a race once stalled the boot, display included, for 5 s).
# 26. Wi-Fi connects sooner after boot: set COUNTRY in /etc/default/sb4edge-wifi (e.g. COUNTRY=US). The Wi-Fi chip
#     then skips its own country scan, which blocked every other scan for several seconds (driver rebuilt to accept
#     the setting).
# 27. Boot: the logo appears again with the faster initramfs (the switch to the main system waits until the splash is
#     on the panel, at most 2.5 s), and boot no longer waits ~5 s for "udev settle" (Windows unlock service).
set -eu
KREL=$KREL
KVER=$KVER
EOF
emb IIO out/ssc/root/usr/libexec/iio-sensor-proxy
emb FPI overlay/fingerprint/sb4edge-fingerprint-import
emb PLYC overlay/sb4edge-plymouthd.conf
emb SLIM overlay/sb4edge-slim-dracut.conf
emb SWM overlay/dracut/95sb4edge-splash-wait/module-setup.sh
emb SWS overlay/dracut/95sb4edge-splash-wait/sb4edge-splash-wait.sh
emb SWC overlay/dracut/sb4edge-splash-wait.conf
emb QRTR overlay/sb4edge-qrtr-dracut.conf
emb HOSTO overlay/sb4edge-hostonly-dracut.conf
emb RESCUE overlay/42_sb4edge_rescue
emb FPSVC overlay/fingerprint/sb4edge-fingerprint-import.service
emb FPDEF overlay/fingerprint/sb4edge-fingerprint.default
emb EDID display/g9/make-g9-edid.py
emb FAN overlay/sb4edge-fan
emb USBC out/sb4edge-usbc
emb KBD overlay/sensors/sb4edge-kbd-ambient
emb BKL overlay/backlight/sb4edge-backlight
emb LFP "$LFP"
emb GIR "$GIR"
emb RES "$RES"
emb NPU out/sb4_cdsp_stats.ko
emb IRIS out/qcom-iris.ko
emb ATH out/ath12k.ko
emb WCC overlay/wifi/sb4edge-wifi-country
emb WCR overlay/wifi/80-sb4edge-wifi-country.rules
emb WCD overlay/wifi/sb4edge-wifi-country-dracut.conf
emb WCF overlay/wifi/sb4edge-wifi.default
emb SGBAT out/samsung_galaxybook_battery.ko
emb GKERN overlay/sleep/zz-sb4edge-kernel.cfg
emb GREFI refind/zz-sb4edge-refind.cfg
emb DOCK overlay/gnome/sb4edge-dock-fix
emb DOCKH overlay/gnome/99-sb4edge-dock-fix
emb PERS overlay/gnome/sb4edge-gnome-persist
emb PERSS overlay/gnome/sb4edge-gnome-persist.service
emb PERSH overlay/gnome/99-sb4edge-gnome-persist
emb EXTO overlay/gnome/90-sb4edge-extensions.gschema.override
i=0; EXTS=
for z in overlay/gnome/extensions/*.zip; do
	i=$((i + 1)); emb "EXT$i" "$z"; EXTS="$EXTS EXT$i:$(basename "$z" .zip)"
done
echo "EXTS='$EXTS'"
emb FPID overlay/fingerprint/sb4edge-fp-identify
emb FPTOK overlay/fingerprint/sb4edge-fp-token
emb FPOVL overlay/fingerprint/sb4edge-gdm-fp-overlay
emb FPDBC overlay/fingerprint/org.sb4edge.FingerprintIdentify.conf
emb FPDBS overlay/fingerprint/org.sb4edge.FingerprintIdentify.dbus-service
emb FPUNIT overlay/fingerprint/sb4edge-fp-identify.service
emb FPGDM overlay/fingerprint/org.gnome.Shell@gdm-sb4edge-fp.conf
emb WINM windows/sb4edge-windows-mount
emb WINS windows/sb4edge-windows-mount.service
emb WINP windows/org.sb4edge.windows-write.policy
emb WINN windows/sb4edge-unlock-folder.py
cat <<'EOF'

[ "$(id -u)" = 0 ] || { echo "run it with sudo: sudo sh $0"; exit 1; }
[ -d /usr/lib/sb4edge ] || { echo "this is not an SB4-Edge-Linux system (no /usr/lib/sb4edge)"; exit 1; }
[ "$(uname -m)" = aarch64 ] || { echo "arm64 only"; exit 1; }

BK=/var/lib/sb4edge/update-backup/$(date +%Y%m%d-%H%M%S)
changed=0
backup() { [ -e "$1" ] || return 0; mkdir -p "$BK$(dirname "$1")"; cp -a "$1" "$BK$1"; }
extract() { # extract VAR file: writes the embedded file, checks its SHA-256
	eval "sha=\$${1}_SHA b64=\$${1}_B64"
	printf '%s' "$b64" | base64 -d | gunzip > "$2"
	[ "$(sha256sum "$2" | cut -d' ' -f1)" = "$sha" ] || { rm -f "$2"; echo "embedded file damaged: $1"; exit 1; }
}

put() { # put VAR target mode
	eval "sha=\$${1}_SHA"
	if [ -f "$2" ] && [ "$(sha256sum "$2" | cut -d' ' -f1)" = "$sha" ]; then
		echo "up to date: $2"; return 1
	fi
	mkdir -p "$(dirname "$2")"
	tmp=$(mktemp "$2.XXXXXX")
	extract "$1" "$tmp"
	backup "$2"
	chmod "$3" "$tmp"; mv -f "$tmp" "$2"
	echo "updated: $2"; changed=1
	return 0
}

restart_iio=0 restart_fan=0 restart_bkl=0 reload=0
put IIO /usr/lib/sb4edge/ssc/iio-sensor-proxy 755 && restart_iio=1
put FPI /usr/sbin/sb4edge-fingerprint-import 755 || true
put FPSVC /usr/lib/systemd/system/sb4edge-fingerprint-import.service 644 && reload=1
put EDID /usr/lib/sb4edge/make-g9-edid.py 644 || true
put FAN /usr/libexec/sb4edge-fan 755 && restart_fan=1
put USBC /usr/libexec/sb4edge-usbc 755 || true
put KBD /usr/libexec/sb4edge-kbd-ambient 755 || true
put BKL /usr/libexec/sb4edge-backlight 755 && restart_bkl=1

# The setting for the fingerprint import: added with the default (touch to import), never overwritten.
if [ ! -e /etc/default/sb4edge-fingerprint ]; then
	extract FPDEF /etc/default/sb4edge-fingerprint; chmod 644 /etc/default/sb4edge-fingerprint
	echo "added: /etc/default/sb4edge-fingerprint (AUTO_IMPORT=no: touch the sensor to import a Windows Hello print)"
	changed=1
else
	echo "kept: /etc/default/sb4edge-fingerprint ($(grep -E '^AUTO_IMPORT=' /etc/default/sb4edge-fingerprint || echo 'no AUTO_IMPORT line'))"
fi

D=/etc/systemd/system/iio-sensor-proxy.service.d/sb4edge.conf
if [ -f "$D" ] && ! grep -q '^Restart=on-failure' "$D"; then
	backup "$D"
	printf '%s\n' '# If it ever dies, bring automatic brightness back instead of waiting for a reboot.' \
		'Restart=on-failure' 'RestartSec=5' >> "$D"
	echo "updated: $D (restart on failure)"; changed=1; restart_iio=1 reload=1
elif [ -f "$D" ]; then
	echo "up to date: $D"
fi

# Fingerprint library (SB4-Edge build only; it stays held and pinned as before).
cur=$(dpkg-query -W -f='${Version}' libfprint-2-2 2>/dev/null || true)
case $cur in
*sb4edge*)
	T=$(mktemp -d)
	extract LFP "$T/libfprint-2-2.deb"; extract GIR "$T/gir1.2-fprint-2.0.deb"
	new=$(dpkg-deb -f "$T/libfprint-2-2.deb" Version)
	lib=$(dpkg -L libfprint-2-2 | grep -m1 'libfprint-2\.so\.2\.')
	if [ "$cur" = "$new" ] && cmp -s "$lib" "$(cd "$T" && dpkg-deb -x libfprint-2-2.deb x && echo "$T/x$lib")"; then
		echo "up to date: libfprint-2-2 $cur"
	else
		backup "$lib"
		holds=$(apt-mark showhold libfprint-2-2 gir1.2-fprint-2.0 2>/dev/null || true)
		gir=; dpkg-query -W -f='${Status}' gir1.2-fprint-2.0 2>/dev/null | grep -q 'ok installed' && gir="$T/gir1.2-fprint-2.0.deb"
		dpkg -i "$T/libfprint-2-2.deb" $gir >/dev/null
		[ -z "$holds" ] || apt-mark hold $holds >/dev/null
		echo "updated: libfprint-2-2 $cur -> $new"; changed=1
		systemctl try-restart fprintd 2>/dev/null || true
	fi
	rm -rf "$T" ;;
*) echo "skipped: libfprint-2-2 is not the SB4-Edge build (${cur:-not installed})" ;;
esac

# NPU load module (only next to the kernel package it was built for).
kv=$(dpkg-query -W -f='${Version}' "linux-image-$KREL" 2>/dev/null || true)
if dpkg-query -W -f='${Status}' sb4-cdsp-stats 2>/dev/null | grep -q 'ok installed'; then
	echo "kept: NPU load module (installed by the sb4-cdsp-stats package)"
elif [ "$kv" != "$KVER" ]; then
	echo "skipped: NPU load module (built for linux-image-$KREL $KVER; installed: ${kv:-none})"
else
	if put NPU "/usr/lib/modules/$KREL/updates/sb4_cdsp_stats.ko" 644; then depmod -a "$KREL"; fi
	C=/etc/modules-load.d/sb4edge.conf
	if ! grep -qx 'sb4_cdsp_stats' "$C" 2>/dev/null; then
		backup "$C"; mkdir -p "$(dirname "$C")"
		printf '%s\n' '# Firmware load counter for the Resources NPU graph' 'sb4_cdsp_stats' >> "$C"
		echo "updated: $C (load the NPU module at boot)"; changed=1
	fi
	if [ "$(uname -r)" = "$KREL" ] && [ ! -d /sys/module/sb4_cdsp_stats ]; then
		modprobe sb4_cdsp_stats && echo "NPU load module loaded"
	fi
fi

# Video decoder module with the Iris fixes (same kernel check; used from the next boot, as it is in use now).
if [ "$kv" != "$KVER" ]; then
	echo "skipped: video decoder module (built for linux-image-$KREL $KVER; installed: ${kv:-none})"
elif put IRIS "/usr/lib/modules/$KREL/updates/qcom-iris.ko" 644; then
	depmod -a "$KREL"
	echo "  the video decoder fix takes effect at the next boot"
fi

# Resources (system monitor) with the Snapdragon CPU, GPU and NPU pages; held like the other SB4-Edge packages.
cur=$(dpkg-query -W -f='${Version}' resources 2>/dev/null || true)
if [ -n "$cur" ]; then
	T=$(mktemp -d)
	extract RES "$T/resources.deb"
	new=$(dpkg-deb -f "$T/resources.deb" Version)
	if dpkg --compare-versions "$cur" gt "$new"; then
		echo "kept: resources $cur (newer than this update's $new)"
	elif [ "$cur" = "$new" ] && cmp -s /usr/bin/resources "$(cd "$T" && dpkg-deb -x resources.deb x && echo "$T/x/usr/bin/resources")"; then
		echo "up to date: resources $cur"
	else
		backup /usr/bin/resources
		dpkg -i "$T/resources.deb" >/dev/null
		apt-mark hold resources >/dev/null
		echo "updated: resources $cur -> $new (restart Resources if it is open)"; changed=1
	fi
	rm -rf "$T"
else
	echo "skipped: Resources is not installed"
fi

# Wi-Fi: drop the project's board-2.bin when Ubuntu's own file has this board with the same board data.
O=/usr/lib/firmware/updates/ath12k/WCN7850/hw2.0/board-2.bin
U=/usr/lib/firmware/ath12k/WCN7850/hw2.0/board-2.bin.zst
if [ -f "$O" ] && [ -f "$U" ] && command -v zstd >/dev/null && command -v python3 >/dev/null; then
	T=$(mktemp -d)
	zstd -qdc "$U" > "$T/ubuntu.bin"
	if python3 -I - "$T/ubuntu.bin" "$O" <<'PY'
import struct, sys
NEW = b"bus=pci,vendor=17cb,device=1107,subsystem-vendor=17cb,subsystem-device=1107,qmi-chip-id=2,qmi-board-id=255"
def board(path):
    d = open(path, "rb").read()
    m = b"QCA-ATH12K-BOARD\0"
    if not d.startswith(m):
        return None
    def tlvs(b):
        o = 0
        while o + 8 <= len(b):
            t, n = struct.unpack("<II", b[o:o + 8])
            yield t, b[o + 8:o + 8 + n]
            o += 8 + n + (-n % 4)
    for t, v in tlvs(d[len(m) + (-len(m) % 4):]):
        if t == 0:
            subs = list(tlvs(v))
            if any(st == 0 and s == NEW for st, s in subs):
                return next((s for st, s in subs if st == 1), None)
    return None
u, o = board(sys.argv[1]), board(sys.argv[2])
sys.exit(0 if u is not None and u == o else 1)
PY
	then
		backup "$O"; rm -f "$O"
		rmdir -p --ignore-fail-on-non-empty "$(dirname "$O")" 2>/dev/null || true
		echo "removed: $O (Ubuntu's firmware has the same entry; used from the next boot)"; changed=1
	else
		echo "kept: $O (Ubuntu's firmware does not have the same entry for this board)"
	fi
	rm -rf "$T"
fi

# Wi-Fi driver with the firmware statistics fix (same kernel check; in use now, so from the next boot).
if [ "$kv" != "$KVER" ]; then
	echo "skipped: Wi-Fi driver fix (built for linux-image-$KREL $KVER; installed: ${kv:-none})"
elif put ATH "/usr/lib/modules/$KREL/updates/ath12k.ko" 644; then
	depmod -a "$KREL"; plyc=1
	echo "  the Wi-Fi fix takes effect at the next boot"
fi

# Wi-Fi country at start (the chip skips its 11d scan); COUNTRY is the user's choice, kept if already set.
put WCC /usr/lib/sb4edge/sb4edge-wifi-country 755 || true
put WCR /usr/lib/udev/rules.d/80-sb4edge-wifi-country.rules 644 && { udevadm control --reload 2>/dev/null || true; } || true
[ -f /etc/default/sb4edge-wifi ] || { extract WCF /etc/default/sb4edge-wifi; chmod 644 /etc/default/sb4edge-wifi
	echo "added: /etc/default/sb4edge-wifi (set COUNTRY=<your country code> for a faster first Wi-Fi connection)"; }
put WCD /etc/dracut.conf.d/sb4edge-wifi-country.conf 644 && plyc=1 || true

# Battery driver with consistent EC reads (same kernel check; reloading it would drop the keyboard backlight driver
# too, so it takes effect at the next boot).
if [ "$kv" != "$KVER" ]; then
	echo "skipped: battery driver fix (built for linux-image-$KREL $KVER; installed: ${kv:-none})"
elif put SGBAT "/usr/lib/modules/$KREL/updates/samsung_galaxybook_battery.ko" 644; then
	depmod -a "$KREL"
	echo "  the battery fix takes effect at the next boot"
fi

# Silent boot: the sb4edge kernel as GRUB's top-level entry, no console cursor.
grub=0
put GKERN /etc/default/grub.d/zz-sb4edge-kernel.cfg 644 && grub=1
put GREFI /etc/default/grub.d/zz-sb4edge-refind.cfg 644 && grub=1
if [ $grub = 1 ] && command -v update-grub >/dev/null; then
	update-grub >/dev/null 2>&1 && echo "boot menu updated (silent boot from the next start)" || echo "update-grub failed: run sudo update-grub"
fi

# GNOME extensions, system-wide (a copy in ~/.local/share/gnome-shell/extensions still takes precedence).
schemas=0
# Replaced by sb4edge-tweaks-xr@sb4edge (2026-11-22): removed where this script installed them.
for uuid in no-screenshot-box-xr@sb4edge tesseract-ocr-xr@sb4edge sb4edge-overview-close@sb4edge rustdesk-window@sb4edge; do
	X=/usr/share/gnome-shell/extensions/$uuid M=/var/lib/sb4edge/extensions/$uuid.sha256
	[ -f "$M" ] || continue
	if [ -d "$X" ]; then
		backup "$X"; rm -rf "$X"
		echo "removed: extension $uuid (now part of sb4edge-tweaks-xr@sb4edge)"; changed=1
	fi
	rm -f "$M"
done
for e in $EXTS; do
	var=${e%%:*} uuid=${e#*:}
	eval "sha=\$${var}_SHA"
	X=/usr/share/gnome-shell/extensions/$uuid M=/var/lib/sb4edge/extensions/$uuid.sha256
	if [ -d "$X" ] && [ "$(cat "$M" 2>/dev/null)" = "$sha" ]; then echo "up to date: extension $uuid"; continue; fi
	T=$(mktemp -d); extract "$var" "$T/e.zip"
	[ -d "$X" ] && { backup "$X"; rm -rf "$X"; }
	mkdir -p "$X"; python3 -I -m zipfile -e "$T/e.zip" "$X"; rm -rf "$T"
	[ ! -d "$X/schemas" ] || glib-compile-schemas "$X/schemas"
	chmod -R u=rwX,go=rX "$X"
	mkdir -p "$(dirname "$M")"; echo "$sha" > "$M"
	echo "updated: extension $uuid"; changed=1
done
put EXTO /usr/share/glib-2.0/schemas/90-sb4edge-extensions.gschema.override 644 && schemas=1
if [ $schemas = 1 ]; then
	glib-compile-schemas /usr/share/glib-2.0/schemas && echo "  extensions are on by default from the next login (unless you set your own list)"
	echo "  own list of extensions? Turn on \"Book 4 Edge Tweaks XR\" in Extensions: it replaces the four sb4edge screenshot,"
	echo "  OCR, overview and RustDesk extensions (their earlier settings are not carried over)"
fi

# Ubuntu Dock and AppIndicators patches (re-applied after their package updates by the apt hook).
put DOCK /usr/lib/sb4edge/sb4edge-dock-fix 755 || true
put DOCKH /etc/apt/apt.conf.d/99-sb4edge-dock-fix 644 || true

# Fingerprint login straight from the login screen's user list.
fp=0
put FPID /usr/lib/sb4edge/sb4edge-fp-identify 755 && fp=1
put FPTOK /usr/lib/sb4edge/sb4edge-fp-token 755 || true
put FPOVL /usr/lib/sb4edge/sb4edge-gdm-fp-overlay 755 || true
put FPDBC /usr/share/dbus-1/system.d/org.sb4edge.FingerprintIdentify.conf 644 && fp=1
put FPDBS /usr/share/dbus-1/system-services/org.sb4edge.FingerprintIdentify.service 644 && fp=1
put FPUNIT /usr/lib/systemd/system/sb4edge-fp-identify.service 644 && reload=1
put FPGDM "/usr/lib/systemd/user/org.gnome.Shell@gdm.service.d/sb4edge-fp.conf" 644 || true
if [ $fp = 1 ]; then
	systemctl reload dbus 2>/dev/null || busctl call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig >/dev/null 2>&1 || true
	systemctl try-restart sb4edge-fp-identify 2>/dev/null || true
fi

# Keeps all of this in place after upgrades; its first run applies the dock patches, builds the login screen
# overlay and adds the PAM lines (gdm-password / gdm-fingerprint).
put PERS /usr/lib/sb4edge/sb4edge-gnome-persist 755 || true
put PERSS /usr/lib/systemd/system/sb4edge-gnome-persist.service 644 && reload=1
put PERSH /etc/apt/apt.conf.d/99-sb4edge-gnome-persist 644 || true
rm -f /etc/apt/apt.conf.d/99-sb4edge-gdm-fp
systemctl daemon-reload 2>/dev/null || true
systemctl enable sb4edge-gnome-persist.service >/dev/null 2>&1 || true
/usr/lib/sb4edge/sb4edge-gnome-persist | sed 's/^/  /'

# Windows drive read-only with Unlock / Lock folder in GNOME Files (needs bindfs, zenity, python3-nautilus, ntfs-3g).
need=
for p in python3-nautilus bindfs zenity ntfs-3g; do
	dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'ok installed' || need="$need $p"
done
[ -z "$need" ] || DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $need >/dev/null 2>&1 || true
missing=
for p in $need; do dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'ok installed' || missing="$missing $p"; done
if [ -n "$missing" ]; then
	echo "skipped: Windows drive Unlock/Lock folder (needs:$missing; connect to the internet and run this script again)"
else
	put WINM /usr/lib/sb4edge/sb4edge-windows-mount 755 || true
	put WINS /etc/systemd/system/sb4edge-windows-mount.service 644 && reload=1
	put WINP /usr/share/polkit-1/actions/org.sb4edge.windows-write.policy 644 || true
	put WINN /usr/share/nautilus-python/extensions/sb4edge-unlock-folder.py 644 || true
	systemctl daemon-reload 2>/dev/null || true
	if systemctl enable sb4edge-windows-mount.service >/dev/null 2>&1; then
		grep -qs '^ENABLED=no' /etc/default/sb4edge-windows-mount && echo "  Windows drive: kept writable (ENABLED=no)" ||
			echo "  Windows drive: read-only from the next boot; right-click a folder in Files -> Unlock folder to write there"
	fi
fi

# Boot splash: no splash on simpledrm (the logo showed twice when msm took over).
P=/etc/plymouth/plymouthd.conf
if ! grep -qs '^UseSimpledrm=0' "$P"; then
	backup "$P"; mkdir -p /etc/plymouth; extract PLYC "$P"; chmod 644 "$P"
	echo "updated: $P (Ubuntu logo shows once at boot)"; changed=1
	plyc=1
fi
# Initramfs: only this laptop's DSP firmware (the boot loader reads the whole image before the kernel starts).
put SLIM /etc/dracut.conf.d/sb4edge-slim.conf 644 && plyc=1 || true
put SWM /usr/lib/dracut/modules.d/95sb4edge-splash-wait/module-setup.sh 755 && plyc=1 || true
put SWS /usr/lib/dracut/modules.d/95sb4edge-splash-wait/sb4edge-splash-wait.sh 755 && plyc=1 || true
put SWC /etc/dracut.conf.d/sb4edge-splash-wait.conf 644 && plyc=1 || true
put QRTR /etc/dracut.conf.d/sb4edge-qrtr.conf 644 && plyc=1 || true
# Host-only initramfs (this laptop's drivers only); the generic one is kept as <initrd>.full for a GRUB rescue entry.
if [ ! -f /etc/dracut.conf.d/sb4edge-hostonly.conf ] && [ -d /sys/firmware/devicetree/base ]; then
	for i in /boot/initrd.img-*; do
		case $i in *.full|*.pre-*|*.old) continue;; esac
		[ -L "$i" ] || [ -f "$i.full" ] || cp -a "$i" "$i.full"
	done
	put HOSTO /etc/dracut.conf.d/sb4edge-hostonly.conf 644 && plyc=1 || true
fi
put RESCUE /etc/grub.d/42_sb4edge_rescue 755 && { command -v update-grub >/dev/null && update-grub >/dev/null 2>&1 || true; } || true
if [ "${plyc:-0}" = 1 ] && command -v update-initramfs >/dev/null; then
	update-initramfs -u >/dev/null 2>&1 && echo "  initramfs rebuilt (next boot)"
fi

# Sound: drop alsa-base's OSS-emulation preload lines, which fail at every boot in the initramfs.
A=/etc/modprobe.d/alsa-base.conf
if grep -qsE '^install snd(-pcm|-mixer|-seq|-rawmidi)? /sbin/modprobe --ignore-install ' "$A"; then
	backup "$A"
	sed -i -E '/^install snd(-pcm|-mixer|-seq|-rawmidi)? \/sbin\/modprobe --ignore-install /d' "$A"
	echo "updated: $A (OSS preload lines that failed at boot removed)"; changed=1
	if command -v update-initramfs >/dev/null; then update-initramfs -u >/dev/null 2>&1 && echo "  initramfs rebuilt (next boot)"; fi
fi

if command -v systemctl >/dev/null; then
	[ $reload = 0 ] && [ $restart_iio = 0 ] || systemctl daemon-reload 2>/dev/null || true
	if [ $restart_iio = 1 ] && { systemctl is-enabled --quiet iio-sensor-proxy 2>/dev/null || systemctl is-active --quiet iio-sensor-proxy; }; then
		systemctl restart iio-sensor-proxy && echo "sensor service restarted: $(systemctl is-active iio-sensor-proxy)"
		echo "log out and back in once so GNOME picks up the light sensor again (automatic brightness)"
	fi
	if [ $restart_fan = 1 ] && systemctl is-active --quiet sb4edge-fan; then
		systemctl restart sb4edge-fan && echo "fan control restarted: $(systemctl is-active sb4edge-fan)"
	fi
	if [ $restart_bkl = 1 ] && systemctl is-active --quiet sb4edge-backlight; then
		systemctl restart sb4edge-backlight && echo "backlight memory restarted: $(systemctl is-active sb4edge-backlight)"
	fi
fi

if [ $changed = 1 ]; then echo "done; originals saved in $BK"; else echo "nothing to do: already up to date"; fi
EOF
} > "$OUT"
chmod 755 "$OUT"
sh -n "$OUT"
echo "$OUT: $(wc -c < "$OUT") bytes (commit $REV)"
