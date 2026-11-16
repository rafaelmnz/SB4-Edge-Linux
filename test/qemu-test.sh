#!/bin/bash
# Boot the ISO in QEMU (generic virt machine) with a serial-console grub.cfg; log to logs/qemu-generic.log.
# Run from the project root: bash test/qemu-test.sh
set -e
D=/usr/local/bin/docker
rm -f test/test.iso logs/qemu-generic.log
$D run --rm -v "$PWD":/work -w /work sb4build xorriso -indev out/ubuntu-26.04.1-sb4edge-desktop-arm64.iso \
    -outdev test/test.iso -boot_image any replay -map test/grub.cfg /boot/grub/grub.cfg >/dev/null 2>&1
$D run --rm -v "$PWD":/work -w /work sb4qemu bash -c '
cp /usr/share/AAVMF/AAVMF_VARS.fd /tmp/vars.fd
timeout 480 qemu-system-aarch64 -machine virt -accel tcg,thread=multi -cpu cortex-a76 -smp 4 -m 4096 \
  -nographic -no-reboot -nic none \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/AAVMF/AAVMF_CODE.no-secboot.fd \
  -drive if=pflash,format=raw,file=/tmp/vars.fd \
  -device virtio-scsi-pci -drive if=none,id=cd,media=cdrom,format=raw,readonly=on,file=test/test.iso \
  -device scsi-cd,drive=cd > logs/qemu-generic.log 2>&1 || true'
grep -aE "Reached target|gdm|Ubuntu 26|Kernel panic|emergency|Failed to start" logs/qemu-generic.log | tail -15
