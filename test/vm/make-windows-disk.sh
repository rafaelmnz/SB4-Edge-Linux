#!/bin/bash
# Make a 64 GiB virtual disk laid out like a Windows 11 install that was shrunk to leave free space:
#   1 ESP 260 MiB (FAT32, EFI/Microsoft/Boot/bootmgfw.efi placeholder)  2 MSR 16 MiB
#   3 "C:" NTFS 28 GiB (Windows/System32 dirs)  4 Recovery NTFS 1 GiB  then ~34.7 GiB unallocated.
# Runs in a throwaway container: bash test/vm/make-windows-disk.sh  (writes test/vm/disk.raw)
set -e
docker run --rm -v "$PWD/test/vm:/vm" sb4build bash -euc '
apt-get -qq update >/dev/null && apt-get -qq install -y ntfs-3g >/dev/null
D=/vm/disk.raw; rm -f $D; truncate -s 64G $D
sgdisk -o \
  -n 1:2048:+260M   -t 1:ef00 -c 1:"EFI system partition" \
  -n 2:0:+16M       -t 2:0c01 -c 2:"Microsoft reserved partition" \
  -n 3:0:+28G       -t 3:0700 -c 3:"Basic data partition" \
  -n 4:0:+1G        -t 4:2700 -c 4:"Basic data partition" $D
sgdisk -A 4:set:0 -A 4:set:63 $D >/dev/null
sgdisk -p $D
st() { sgdisk -i $1 $D | awk "/First sector/{print \$3}"; }
sz() { sgdisk -i $1 $D | awk -F"[ (]+" "/Partition size/{print \$3}"; }
# ESP
truncate -s $(( $(sz 1) * 512 )) /tmp/esp; mkfs.vfat -F 32 -n SYSTEM /tmp/esp >/dev/null
printf "MZ fake Windows Boot Manager\n" > /tmp/bootmgfw.efi
mmd -i /tmp/esp ::/EFI ::/EFI/Microsoft ::/EFI/Microsoft/Boot ::/EFI/Boot
mcopy -i /tmp/esp /tmp/bootmgfw.efi ::/EFI/Microsoft/Boot/bootmgfw.efi
printf "regf fake BCD\n" > /tmp/BCD; mcopy -i /tmp/esp /tmp/BCD ::/EFI/Microsoft/Boot/BCD  # os-prober needs bootmgfw.efi + BCD
mcopy -i /tmp/esp /tmp/bootmgfw.efi ::/EFI/Boot/bootaa64.efi
dd if=/tmp/esp of=$D bs=512 seek=$(st 1) conv=notrunc status=none; rm /tmp/esp
# C: and Recovery
for p in 3 4; do
  truncate -s $(( $(sz $p) * 512 )) /tmp/ntfs
  mkntfs -q -F -f -L $([ $p = 3 ] && echo Windows || echo Recovery) /tmp/ntfs
  if [ $p = 3 ]; then mkdir -p /tmp/m && ntfs-3g /tmp/ntfs /tmp/m 2>/dev/null && mkdir -p /tmp/m/Windows/System32 /tmp/m/Users && umount /tmp/m || echo "(no fuse: C: left empty)"; fi
  dd if=/tmp/ntfs of=$D bs=1M seek=$(( $(st $p) / 2048 )) conv=notrunc,sparse status=none; rm /tmp/ntfs
done
sgdisk -v $D | tail -2
'
