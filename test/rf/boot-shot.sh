#!/bin/bash
# boot-shot.sh <disk image> <out.png> [seconds] [keys...]: boots the image as a USB disk in QEMU (UEFI), optional
# key presses via the monitor (sendkey), then saves a screenshot and stops the VM (by PID).
IMG=$1; OUT=$2; T=${3:-25}; shift 3; D=$(dirname "$0")
cp /opt/homebrew/share/qemu/edk2-arm-vars.fd "$D/vars.fd"; truncate -s 64M "$D/vars.fd"
rm -f "$D/mon.sock"
qemu-system-aarch64 -M virt -cpu cortex-a72 -m 2048 -accel tcg \
  -drive if=pflash,format=raw,readonly=on,file=/opt/homebrew/share/qemu/edk2-aarch64-code.fd \
  -drive if=pflash,format=raw,file="$D/vars.fd" \
  -device qemu-xhci -device usb-kbd -drive if=none,id=u,format=raw,readonly=on,file="$IMG" -device usb-storage,drive=u \
  -device ramfb -display none -monitor unix:"$D/mon.sock",server,nowait -serial file:"$D/serial.log" &
Q=$!; sleep "$T"
for k in "$@"; do echo "sendkey $k" | nc -U -w1 "$D/mon.sock" >/dev/null; sleep 2; done
[ $# -gt 0 ] && sleep 15
echo "screendump $D/shot.ppm" | nc -U -w1 "$D/mon.sock" >/dev/null; sleep 2
kill $Q; wait $Q 2>/dev/null
sips -s format png "$D/shot.ppm" --out "$OUT" >/dev/null && echo "saved $OUT"
