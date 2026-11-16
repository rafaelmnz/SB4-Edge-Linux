#!/bin/bash
# Builds X1E80100-GalaxyBook4Edge-tplg.bin for the ISO (runs in sb4build: needs m4, alsatplg, python3).
#   stream7 = MultiMedia8: mfc -> pre (Samsung IIR EQ, ACDB iid 0x4017) -> custom (Fluence NN NS, ACDB iid 0x48ee)
# Calibration from Samsung's Windows ACDB (GKV 69, sg 0xb0000003), dumped by ../caldump into ../cal and ../cal-chain.
set -e
cd "$(dirname "$0")"; R=${R:-/work/research/audioreach-topology}
m4 -I . -I "$R" X1E80100-GalaxyBook4Edge-sb4edge.m4 > sb4edge.conf
python3 pre-route.py sb4edge.conf 7
python3 add-cfg.py sb4edge.conf sb4edge.conf 7 0x60ef ../cal/np-ckv0-iid48ee-*.bin
python3 add-cfg.py sb4edge.conf sb4edge.conf 7:pre 0x60ee ../cal-chain/np-ckv0-iid4017-*.bin
alsatplg -c sb4edge.conf -o X1E80100-GalaxyBook4Edge-sb4edge-tplg.bin 2>&1 | grep -v "undefined s" || true
ls -l X1E80100-GalaxyBook4Edge-sb4edge-tplg.bin
