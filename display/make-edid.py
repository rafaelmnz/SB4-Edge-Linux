#!/usr/bin/env python3
"""Add a 60 Hz mode to the Galaxy Book4 Edge panel EDID (Samsung ATNA60CL07-0, 2880x1800@120).

The panel is adaptive-sync (EDID range 48-120 Hz), so 60 Hz is the 120 Hz timing with a longer
vertical front porch: same pixel clock and line timing, vtotal doubled (as Windows' 60 Hz mode does).
The new detailed timing goes into the empty third descriptor slot; the base block checksum is fixed.
usage: make-edid.py in.bin out.bin [refresh=60]
"""
import sys

src, dst = sys.argv[1:3]
hz = float(sys.argv[3]) if len(sys.argv) > 3 else 60.0
e = bytearray(open(src, "rb").read())
d = e[0x36:0x48]
clk = (d[0] | d[1] << 8) * 10  # kHz
hact = d[2] | (d[4] & 0xF0) << 4
hbl = d[3] | (d[4] & 0x0F) << 8
vact = d[5] | (d[7] & 0xF0) << 4
vbl = d[6] | (d[7] & 0x0F) << 8
vfp = (d[10] >> 4) | ((d[11] >> 2) & 3) << 4
htot, vtot = hact + hbl, vact + vbl
print(f"orig: {hact}x{vact} clk {clk} kHz htot {htot} vtot {vtot} vfp {vfp} -> {clk*1000/(htot*vtot):.3f} Hz")
new_vtot = round(clk * 1000 / (htot * hz))
add = new_vtot - vtot
nvbl = vbl + add
nvfp = vfp + add
assert nvbl < 4096, nvbl
# vfp has only 6 bits in a DTD (max 63): put the extra lines in the back porch instead (sync position unchanged
# relative to the front porch, and vblank is what the panel sees as the idle period).
n = bytearray(d)
n[6] = nvbl & 0xFF
n[7] = (n[7] & 0xF0) | (nvbl >> 8)
print(f"new : vtot {new_vtot} (vblank {vbl} -> {nvbl}) -> {clk*1000/(htot*new_vtot):.3f} Hz")
slot = 0x5A
assert not any(e[slot:slot + 18]), "descriptor slot 3 is not empty"
e[slot:slot + 18] = n
e[0x7F] = (-sum(e[0:0x7F])) & 0xFF
open(dst, "wb").write(e)
print("wrote", dst)
