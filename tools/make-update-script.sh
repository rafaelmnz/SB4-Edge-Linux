#!/bin/sh
# Builds out/sb4edge-update.sh: a single script that brings an installed SB4-Edge-Linux release up to date with the
# fixes made since that release, without reinstalling. The fixed files are embedded (gzip + base64) with their
# SHA-256, so the script needs no network access. Build first: ./build.sh ssc usbc libfprint
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
# Run once:  sudo sh sb4edge-update.sh
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
#     Ubuntu's qcom-va-driver (ffmpeg, Citrix, ...) decode H.264/HEVC/AV1 in hardware (from the next boot).
set -eu
KREL=$KREL
KVER=$KVER
EOF
emb IIO out/ssc/root/usr/libexec/iio-sensor-proxy
emb FPI overlay/fingerprint/sb4edge-fingerprint-import
emb FPSVC overlay/fingerprint/sb4edge-fingerprint-import.service
emb FPDEF overlay/fingerprint/sb4edge-fingerprint.default
emb EDID display/g9/make-g9-edid.py
emb FAN overlay/sb4edge-fan
emb USBC out/sb4edge-usbc
emb KBD overlay/sensors/sb4edge-kbd-ambient
emb LFP "$LFP"
emb GIR "$GIR"
emb RES "$RES"
emb NPU out/sb4_cdsp_stats.ko
emb IRIS out/qcom-iris.ko
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

restart_iio=0 restart_fan=0 reload=0
put IIO /usr/lib/sb4edge/ssc/iio-sensor-proxy 755 && restart_iio=1
put FPI /usr/sbin/sb4edge-fingerprint-import 755 || true
put FPSVC /usr/lib/systemd/system/sb4edge-fingerprint-import.service 644 && reload=1
put EDID /usr/lib/sb4edge/make-g9-edid.py 644 || true
put FAN /usr/libexec/sb4edge-fan 755 && restart_fan=1
put USBC /usr/libexec/sb4edge-usbc 755 || true
put KBD /usr/libexec/sb4edge-kbd-ambient 755 || true

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

if command -v systemctl >/dev/null; then
	[ $reload = 0 ] && [ $restart_iio = 0 ] || systemctl daemon-reload 2>/dev/null || true
	if [ $restart_iio = 1 ] && { systemctl is-enabled --quiet iio-sensor-proxy 2>/dev/null || systemctl is-active --quiet iio-sensor-proxy; }; then
		systemctl restart iio-sensor-proxy && echo "sensor service restarted: $(systemctl is-active iio-sensor-proxy)"
		echo "log out and back in once so GNOME picks up the light sensor again (automatic brightness)"
	fi
	if [ $restart_fan = 1 ] && systemctl is-active --quiet sb4edge-fan; then
		systemctl restart sb4edge-fan && echo "fan control restarted: $(systemctl is-active sb4edge-fan)"
	fi
fi

if [ $changed = 1 ]; then echo "done; originals saved in $BK"; else echo "nothing to do: already up to date"; fi
EOF
} > "$OUT"
chmod 755 "$OUT"
sh -n "$OUT"
echo "$OUT: $(wc -c < "$OUT") bytes (commit $REV)"
