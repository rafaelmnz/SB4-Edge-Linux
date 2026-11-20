#!/usr/bin/env python3
# Add a board-2.bin entry for the Galaxy Book4 Edge WCN7850 (subsystem 17cb:1107, board-id 255),
# reusing linux-firmware's shared OEM board-id 255 data (the generic NCM825 calibration, already
# used by 18 other subsystem IDs). Samsung's own bdwlan.elf from Windows makes the firmware crash
# during the board-data download (-110), so it cannot be used.
# linux-firmware 20261110 ships this entry itself (same data): then nothing is written and it exits 0, so the
# package file is used and later firmware updates are not shadowed by an override.
#   ath12k-board2-add.py IN_board-2.bin OUT_board-2.bin
import struct
import sys

MAGIC = b"QCA-ATH12K-BOARD\0"
IE_BOARD, SUB_NAME, SUB_DATA = 0, 0, 1
NEW = "bus=pci,vendor=17cb,device=1107,subsystem-vendor=17cb,subsystem-device=1107,qmi-chip-id=2,qmi-board-id=255"
DONOR = "bus=pci,vendor=17cb,device=1107,subsystem-vendor=105b,subsystem-device=e0ee,qmi-chip-id=2,qmi-board-id=255"


def pad(b):
    return b + b"\0" * (-len(b) % 4)


def tlvs(buf):
    o = 0
    while o < len(buf):
        t, n = struct.unpack("<II", buf[o:o + 8])
        yield t, buf[o + 8:o + 8 + n]
        o += 8 + n + (-n % 4)


def tlv(t, v):
    return struct.pack("<II", t, len(v)) + pad(v)


data = open(sys.argv[1], "rb").read()
assert data.startswith(MAGIC), "not an ath12k board-2.bin"
hdr = pad(MAGIC)
ies = list(tlvs(data[len(hdr):]))
donor = None
for t, v in ies:
    if t != IE_BOARD:
        continue
    subs = list(tlvs(v))
    names = [s.decode() for st, s in subs if st == SUB_NAME]
    if NEW in names:
        print(f"{NEW} already in the input: no override needed")
        sys.exit(0)
    if DONOR in names:
        donor = next(s for st, s in subs if st == SUB_DATA)
assert donor, "donor entry not found"
out = hdr + b"".join(tlv(t, v) for t, v in ies)
out += tlv(IE_BOARD, tlv(SUB_NAME, NEW.encode()) + tlv(SUB_DATA, donor))
open(sys.argv[2], "wb").write(out)
print(f"added {NEW} ({len(donor)} bytes of board data)")
