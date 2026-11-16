#!/bin/bash
# bash test/vm/run.sh install|boot   (HVF on the Mac; serial log in logs/qemu-<mode>.log)
set -e
cd "$(dirname "$0")"
M=$1; [ -f vars.fd ] || { truncate -s 64m vars.fd; }
ARGS=(-machine virt -accel hvf -cpu host -smp 6 -m 8192 -display none -monitor none -qmp unix:qmp-$M.sock,server,nowait
  -serial file:../../logs/qemu-$M.log -no-reboot
  -drive if=pflash,format=raw,readonly=on,file=/opt/homebrew/share/qemu/edk2-aarch64-code.fd
  -drive if=pflash,format=raw,file=vars.fd
  -device virtio-gpu-pci -device qemu-xhci -device usb-kbd
  -drive if=none,id=hd,format=raw,file=disk.raw -device virtio-blk-pci,drive=hd,bootindex=2)
[ "$M" = install ] && ARGS+=(-drive if=none,id=stick,format=raw,readonly=on,file=install.iso -device usb-storage,drive=stick,removable=on,bootindex=1)
exec timeout ${T:-3600} qemu-system-aarch64 "${ARGS[@]}"
