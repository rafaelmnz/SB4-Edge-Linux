#!/bin/bash
# Read-only hardware survey for the Galaxy Book4 Edge live session.
# Runs on the laptop (via ssh, with sudo); writes everything to $OUT and prints a summary.
# Never writes to, mounts or partitions the internal UFS disk; never touches EFI variables.
OUT=${1:-/tmp/hw-report}
mkdir -p "$OUT"
cd "$OUT" || exit 1

run() { # run <file> <command...>
	local f=$1; shift
	{ echo "\$ $*"; "$@"; } >"$f" 2>&1
}

run uname.txt          uname -a
run model.txt          sh -c 'tr -d "\0" </proc/device-tree/model; echo; tr "\0" " " </proc/device-tree/compatible; echo'
run cmdline.txt        cat /proc/cmdline
run dmesg.txt          dmesg
run dmesg-errwarn.txt  dmesg --level=err,warn
run journal.txt        journalctl -b --no-pager
run failed-units.txt   systemctl --failed --no-pager
run lsmod.txt          lsmod
run lsblk.txt          lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,PARTLABEL,RO,TRAN,MODEL
run lsusb.txt          lsusb -t
run lspci.txt          lspci -nnk
run dmi.txt            sh -c 'for f in /sys/class/dmi/id/*; do [ -f "$f" ] && [ -r "$f" ] && echo "$(basename $f): $(cat $f 2>/dev/null)"; done'
run drm.txt            sh -c 'for c in /sys/class/drm/card*-*; do echo "$c: $(cat $c/status) $(head -1 $c/modes 2>/dev/null)"; done; ls -l /dev/dri'
run backlight.txt      sh -c 'for b in /sys/class/backlight/*; do echo "$b max=$(cat $b/max_brightness) cur=$(cat $b/brightness)"; done'
run gpu.txt            sh -c 'command -v glxinfo >/dev/null && DISPLAY=:0 glxinfo -B; command -v eglinfo >/dev/null && eglinfo -B'
run xrandr.txt         sh -c 'cat /sys/class/drm/card*/device/uevent 2>/dev/null; for u in $(loginctl list-sessions --no-legend | awk "{print \$1}"); do loginctl show-session $u -p Type -p Name -p State; done'
run input.txt          sh -c 'cat /proc/bus/input/devices; ls -l /dev/input/by-path 2>/dev/null'
run net.txt            sh -c 'ip -br link; ip -br addr; nmcli dev status 2>/dev/null; iw dev 2>/dev/null'
run wifi-scan.txt      sh -c 'nmcli -f SSID,SIGNAL,CHAN,SECURITY dev wifi list 2>/dev/null | head -20'
run bluetooth.txt      sh -c 'rfkill list; hciconfig -a 2>/dev/null; bluetoothctl show 2>/dev/null; timeout 10 bluetoothctl --timeout 8 scan on 2>/dev/null | tail -5'
run typec.txt          sh -c 'for p in /sys/class/typec/*; do echo "$p: $(cat $p/data_role 2>/dev/null) $(cat $p/power_role 2>/dev/null)"; done; ls /sys/class/usb_role 2>/dev/null'
run power.txt          sh -c 'for p in /sys/class/power_supply/*; do echo "== $p"; cat $p/uevent; done'
run cpufreq.txt        sh -c 'for p in /sys/devices/system/cpu/cpufreq/policy*; do echo "$p: $(cat $p/scaling_driver) $(cat $p/scaling_governor) cur=$(cat $p/scaling_cur_freq) min=$(cat $p/cpuinfo_min_freq) max=$(cat $p/cpuinfo_max_freq)"; done'
run thermal.txt        sh -c 'for t in /sys/class/thermal/thermal_zone*; do echo "$(cat $t/type) $(cat $t/temp)"; done'
run suspend.txt        sh -c 'cat /sys/power/state /sys/power/mem_sleep'
run remoteproc.txt     sh -c 'for r in /sys/class/remoteproc/*; do echo "$r: $(cat $r/name) $(cat $r/firmware) $(cat $r/state)"; done; systemctl status pd-mapper qrtr-ns rmtfs --no-pager 2>&1 | head -40'
run firmware.txt       sh -c 'dmesg | grep -iE "firmware|direct firmware load|failed to load"; ls -lR /usr/lib/firmware/qcom/x1e80100/SAMSUNG 2>/dev/null'
run audio.txt          sh -c 'cat /proc/asound/cards; aplay -l 2>&1; dmesg | grep -iE "snd|audio|q6apm|topology"'
run camera.txt         sh -c 'ls /dev/video* /dev/media* 2>&1; dmesg | grep -iE "camss|cci|camera"'
run efi.txt            sh -c 'efibootmgr -v 2>&1; ls /sys/firmware/efi/efivars | wc -l; dmesg | grep -iE "qseecom|uefisecapp"'
run ufs.txt            sh -c 'dmesg | grep -iE "ufs|scsi"'
run grep-errors.txt    sh -c 'dmesg | grep -iE "fail|error|timeout|deferred|probe" | grep -v "^$"'

# summary
{
	echo "kernel:   $(uname -r)"
	echo "model:    $(tr -d '\0' </proc/device-tree/model 2>/dev/null)"
	echo "ufs disk: $(lsblk -dno NAME,SIZE,TRAN 2>/dev/null | grep -iE 'sd|ufs' | tr '\n' ' ')"
	echo "drm:      $(grep -h connected drm.txt | tr '\n' ' ')"
	echo "backlight:$(grep -c max= backlight.txt) device(s)"
	echo "gpu:      $(grep -iE 'renderer|device' gpu.txt | head -2 | tr '\n' ' ')"
	echo "wifi:     $(grep -iE 'wl' net.txt | head -2 | tr '\n' ' ') scan=$(($(wc -l <wifi-scan.txt) - 2)) networks"
	echo "bt:       $(grep -m1 -iE 'Powered|UP RUNNING' bluetooth.txt)"
	echo "battery:  $(grep -hE 'CAPACITY=|STATUS=' power.txt | tr '\n' ' ')"
	echo "remoteproc: $(cut -d' ' -f2- remoteproc.txt | grep -E 'running|offline|crashed' | tr '\n' ';')"
	echo "failed units: $(grep -c failed failed-units.txt)"
	echo "dmesg err/warn lines: $(($(wc -l <dmesg-errwarn.txt) - 1))"
} | tee summary.txt
chmod -R a+rX "$OUT"
