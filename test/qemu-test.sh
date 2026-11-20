#!/bin/bash
# Boot the ISO in QEMU (generic virt machine) with a serial-console grub.cfg; log to logs/qemu-generic.log.
# Run from the project root: bash test/qemu-test.sh
# Exit status: 0 when the live system reached graphical.target (or started GDM) without a kernel panic or emergency
# mode; 1 when it did not; 2 when QEMU itself failed (anything but the expected stop at the 480 s timeout).
set -e
rm -f logs/qemu-generic.status
D=/usr/local/bin/docker
rm -f test/test.iso logs/qemu-generic.log
$D run --rm -v "$PWD":/work -w /work sb4build xorriso -indev out/ubuntu-27.04-sb4edge-desktop-arm64.iso \
    -outdev test/test.iso -boot_image any replay -map test/grub.cfg /boot/grub/grub.cfg >/dev/null 2>&1
$D run --rm -v "$PWD":/work -w /work sb4qemu bash -c '
cp /usr/share/AAVMF/AAVMF_VARS.fd /tmp/vars.fd
timeout 480 qemu-system-aarch64 -machine virt -accel tcg,thread=multi -cpu cortex-a76 -smp 4 -m 4096 \
  -nographic -no-reboot -nic none \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/AAVMF/AAVMF_CODE.no-secboot.fd \
  -drive if=pflash,format=raw,file=/tmp/vars.fd \
  -device virtio-scsi-pci -drive if=none,id=cd,media=cdrom,format=raw,readonly=on,file=test/test.iso \
  -device scsi-cd,drive=cd > logs/qemu-generic.log 2>&1; echo $? > logs/qemu-generic.status' || true
L=logs/qemu-generic.log
grep -aE "Reached target|gdm|Ubuntu 2[67]|Kernel panic|emergency|Failed to start" "$L" | tail -15 || true
rc=$(cat logs/qemu-generic.status 2>/dev/null || echo missing)
# timeout(1) returns 124 when it stops QEMU at 480 s (the expected end); QEMU exits 0 itself on a guest power-off.
case $rc in 0|124) ;; *) echo "FAIL: QEMU did not run to the timeout (status $rc)"; exit 2 ;; esac
if grep -aqE "Kernel panic|You are in emergency mode|Entering emergency mode" "$L"; then
	echo "FAIL: kernel panic or emergency mode"; exit 1
fi
if ! grep -aqE "Reached target .*graphical\.target|Started .*gdm\.service" "$L"; then
	echo "FAIL: never reached graphical.target / GDM"; exit 1
fi
echo "PASS: reached graphical.target / GDM ($(grep -ac 'Failed to start' "$L" || true) units failed to start; see $L)"
