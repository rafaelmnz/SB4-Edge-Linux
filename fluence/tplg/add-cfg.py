#!/usr/bin/env python3
"""Attach an ACDB calibration blob (APM param list) to stream<N>.custom1 in an m4-generated topology conf.
usage: add-cfg.py in.conf out.conf <stream-index>[:<widget, default custom>] <new-iid> <param .bin files...>
Each .bin is iid,pid,size,err + payload (caldump output); iid is rewritten, payloads padded to 8 bytes."""
import struct, sys
src, dst, sidx, iid = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4], 0)
blob = b""
for f in sorted(sys.argv[5:]):
    d = open(f, "rb").read()
    _, pid, psz, err = struct.unpack_from("<4I", d)
    pay = d[16:16 + psz]
    blob += struct.pack("<4I", iid, pid, psz, 0) + pay + b"\0" * ((-psz) % 8)
hdr = struct.pack("<4I", len(blob), 0x01001006, 0, 0)   # audioreach_module_priv_data: size = bytes of data[]
raw = hdr + blob
sidx, _, wname = sidx.partition(":")
w = f"stream{sidx}.{wname or 'custom'}1"
sec = f'SectionData."{w}_cfg" {{\n        bytes "' + ",".join(f"0x{b:02x}" for b in raw) + '"\n}\n'
t = open(src).read()
old = f'                "{w}_data"\n'
assert t.count(old) == 1, t.count(old)
t = t.replace(old, old + f'                "{w}_cfg"\n') + "\n" + sec
open(dst, "w").write(t)
print(f"{w}: {len(sys.argv) - 5} params, blob {len(blob)} bytes, iid {iid:#x}")
