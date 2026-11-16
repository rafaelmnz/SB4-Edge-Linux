#!/bin/bash
# shots.sh <img> <prefix> <t1> <t2> ...: boots in QEMU and saves screenshots at the given seconds after start.
IMG=$1; P=$2; shift 2; D=$(dirname "$0")
cp /opt/homebrew/share/qemu/edk2-arm-vars.fd "$D/vars.fd"; truncate -s 64M "$D/vars.fd"; rm -f "$D/mon.sock"
qemu-system-aarch64 -M virt -cpu cortex-a72 -m 2048 -accel tcg \
  -drive if=pflash,format=raw,readonly=on,file=/opt/homebrew/share/qemu/edk2-aarch64-code.fd \
  -drive if=pflash,format=raw,file="$D/vars.fd" \
  -device qemu-xhci -device usb-kbd -drive if=none,id=u,format=raw,readonly=on,file="$IMG" -device usb-storage,drive=u \
  -device ramfb -display none -monitor unix:"$D/mon.sock",server,nowait -serial file:"$D/serial.log" 2>/dev/null &
Q=$!; t0=$(date +%s)
for t in "$@"; do while [ $(( $(date +%s) - t0 )) -lt $t ]; do sleep 1; done
  echo "screendump $D/s.ppm" | nc -U -w1 "$D/mon.sock" >/dev/null; sleep 1; sips -s format png "$D/s.ppm" --out "$D/$P-$t.png" >/dev/null; done
kill $Q; wait $Q 2>/dev/null; echo done
