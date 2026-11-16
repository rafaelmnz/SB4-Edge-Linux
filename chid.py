#!/usr/bin/env python3
# CHID computation ported from systemd src/fundamental/chid.c
import hashlib, struct, uuid, json, sys
NS = struct.pack("<IHH8s", 0x12d8ff70, 0x7f4c, 0x7d4c, bytes(8))  # as laid out in memory
def chid(values):
    h = hashlib.sha1(NS)
    for i, v in enumerate(values):
        if i: h.update("&".encode("utf-16le"))
        h.update(v.encode("utf-16le"))
    d = h.digest()[:16]
    d1, d2, d3 = struct.unpack(">IHH", d[:8])        # bswap from LE memory = read BE
    d3 = (d3 & 0x0fff) | (5 << 12)
    d4 = bytearray(d[8:]); d4[0] = (d4[0] & 0x3f) | 0x80
    return str(uuid.UUID(bytes=struct.pack(">IHH", d1, d2, d3) + bytes(d4)))
if __name__ == "__main__" and sys.argv[1:] == ["test"]:
    print(chid(["ASUSTeK COMPUTER INC.", "ASUS Vivobook S 15"]))
