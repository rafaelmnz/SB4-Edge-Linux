#!/bin/bash
# sudo ab.sh -- guided listening test: records 8 s per variant while you talk, restores normal audio, plays them back.
#   A = no processing (48 kHz), B = Samsung mic EQ + Fluence (16 kHz, as before), C = same with mic gain +6 dB
#   Fluence NN is a 16 kHz algorithm: at 48 kHz it drops one 10 ms frame in 13 (clicks).
# Copies go to ~/Desktop. Replay later with: /tmp/sb4fr/play.sh
cd /tmp/sb4fr
pgrep -x adsprpcd >/dev/null || { LD_LIBRARY_PATH=/tmp/sb4fr/lib ADSP_LIBRARY_PATH=/tmp/sb4fr/adsp nohup ./sbin/adsprpcd audiopd >run.log 2>&1 & sleep 2; }
say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
V="A-no-processing:base.bin:48000:116 B-eq-fluence:eq-fluence16-cal.bin:16000:116 C-eq-fluence-plus6dB:eq-fluence16-cal.bin:16000:122"
for v in $V; do IFS=: read n t r g <<<"$v"
  say "$n: get ready, say the same sentence each time..."; VAVOL=$g RATE=$r DUR=8 ./try.sh $t 2 >/dev/null 2>&1 & sleep 4.5
  say ">>> TALK NOW (8 s)"; wait; cp rec-c2.wav $n.wav
done
say "Done recording. Restoring normal audio..."; ./restore.sh >/dev/null 2>&1; sleep 2
for v in $V; do install -o ubuntu -g ubuntu -m 644 ${v%%:*}.wav /home/ubuntu/Desktop/ 2>/dev/null; done
./play.sh
