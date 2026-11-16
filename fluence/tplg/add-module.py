#!/usr/bin/env python3
"""Insert a DSP module between stream<N>.mfc1 and stream<N>.pcm_converter1 in a decoded AudioReach topology.

usage: add-module.py in.conf out.conf <stream-index> <module-id-hex> <iid-dec> [name]
The new widget reuses the MFC's subgraph/container tuples; MFC's dst iid is pointed at it.
"""
import re
import sys

src, dst, sidx, mod_id, iid = sys.argv[1:6]
name = sys.argv[6] if len(sys.argv) > 6 else "custom1"
mod_id = int(mod_id, 16)
iid = int(iid)
s = f"stream{sidx}"
w = f"{s}.{name}"
t = open(src).read()

# 1. MFC tuple: find its iid and its old destination (the pcm converter)
m = re.search(rf"'{s}\.mfc1:tuple0' \{{.*?token201 (\d+).*?token209 (\d+)", t, re.S)
mfc_iid, cnv_iid = m.group(1), m.group(2)
blk_start = m.start()
blk_end = t.index("\n\t}\n", blk_start) + 4
mfc_blk = t[blk_start:blk_end]
t = t[:blk_start] + mfc_blk.replace(f"token209 {cnv_iid}", f"token209 {iid}") + t[blk_end:]

# 2. new tuple block, cloned from the MFC block
new_blk = (mfc_blk.replace(f"'{s}.mfc1:tuple0'", f"'{w}:tuple0'")
           .replace(f"tokens '{s}.mfc1'", f"tokens '{w}'")
           .replace(f"token201 {mfc_iid}", f"token201 {iid}")
           .replace(f"token208 {mfc_iid}", f"token208 {iid}"))
new_blk = re.sub(r"token200 \d+", f"token200 {mod_id}", new_blk)
t = t[:blk_end] + new_blk + t[blk_end:]

# 3. tokens set (clone the MFC one)
m = re.search(rf"\n\t'{s}\.mfc1' \{{\n\t\ttoken2 2.*?\n\t\}}\n", t, re.S)
t = t[:m.end()] + m.group(0)[1:].replace(f"'{s}.mfc1'", f"'{w}'") + t[m.end():]

# 4. SectionData entry
m = re.search(rf"\t'{s}\.mfc1:tuple0'\.tuples '{s}\.mfc1:tuple0'\n", t)
t = t[:m.end()] + f"\t'{w}:tuple0'.tuples '{w}:tuple0'\n" + t[m.end():]

# 5. widget (first occurrence = SectionWidget)
m = re.search(rf"\t'{s}\.mfc1' \{{\n\t\ttype 'src'.*?\n\t\}}\n", t, re.S)
t = t[:m.end()] + (f"\t'{w}' {{\n\t\ttype 'buffer'\n\t\tno_pm 1\n\t\tsubseq 10\n"
                   f"\t\tdata '{w}:tuple0'\n\t}}\n") + t[m.end():]

# 6. graph route
old = f"'{s}.pcm_converter1, , {s}.mfc1'"
assert old in t
t = t.replace(old, f"'{w}, , {s}.mfc1'\n\t\t\t'{s}.pcm_converter1, , {w}'")
open(dst, "w").write(t)
print(f"inserted {w} id=0x{mod_id:08x} iid={iid}: mfc {mfc_iid} -> {iid} -> {cnv_iid}")
