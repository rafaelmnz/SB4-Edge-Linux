#!/bin/sh
# Per-boot diagnostics, saved on the stick (survive a failed boot). Called by setup.sh with the sb4dev dir.
D=$1; L="$D/logs/$(date +%Y%m%d-%H%M%S)-$(uname -v | cut -d' ' -f1)"; mkdir -p "$L"
cp /run/sb4dev.log "$L/" 2>/dev/null
( sleep 60
  dmesg > "$L/dmesg.txt"
  journalctl -b --no-pager > "$L/journal.txt"
  cat /proc/asound/cards > "$L/asound.txt" 2>&1
  ls /dev/media* /dev/video* > "$L/media.txt" 2>&1
  for m in /dev/media*; do media-ctl -p -d "$m" >> "$L/media.txt" 2>&1; done
  cat /sys/class/power_supply/*/uevent > "$L/power.txt" 2>&1
  sync ) &
exit 0
