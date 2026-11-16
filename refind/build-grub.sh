#!/bin/bash
# Builds refind/grubaa64-live.efi: GRUB for the live USB with a silent early config (Ubuntu's signed ISO GRUB prints
# "error: file '/boot/' not found." from its built-in config before it finds the ISO). Secure Boot is off, so it
# needs no signature. Runs in sb4build (grub-efi-arm64-bin). Modules: everything the live grub.cfg uses.
set -e
cd "$(dirname "$0")"
grub-mkimage -O arm64-efi -o grubaa64-live.efi -c grub-live-early.cfg -p /boot/grub \
  part_gpt part_msdos fat iso9660 ext2 search search_fs_file search_fs_uuid search_label \
  normal configfile echo test regexp smbios mmap linux gzio xzio zstd loadenv sleep \
  all_video efi_gop video video_fb font gfxterm gfxmenu terminal ls cat true reboot halt efifwsetup chain \
  probe minicmd gettext
ls -l grubaa64-live.efi
