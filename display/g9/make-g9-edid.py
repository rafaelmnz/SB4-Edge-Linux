#!/usr/bin/env python3
"""Adds 5120x1440 @ 75 Hz to the Samsung Odyssey G95NC's (57") HDMI EDID.

The laptop's HDMI port is a Realtek RTD2171 DP->HDMI converter whose DP input only accepts HBR2 x4
(17.28 Gbit/s), and its HDMI output is TMDS only (600 MHz max, like the monitor's non-FRL input), so the monitor's 5120x1440
@ 120 Hz (966 MHz) never shows up. The monitor's own 5120x1440 @ 60 timing (5280 x 1481 total) at 75 Hz needs
586.5 MHz. 90 Hz (703.8 MHz) fit the DP link but gave a garbled picture on the 57" (TMDS over 600 MHz).
It replaces the DisplayID 7680x2160 @ 120 Hz timing (2224.75 MHz: never usable here).
usage: make-g9-edid.py in.edid out.edid
"""
import sys

src, dst = sys.argv[1:3]
e = bytearray(open(src, "rb").read())
o = 256
assert e[o] == 0x70 and e[o + 5] == 0x03, "block 2 is not DisplayID with Type I timings first"
n = e[o + 7] // 20
slots = [o + 8 + 20 * i for i in range(n)]

def t(p):
    pclk = (e[p] | e[p + 1] << 8 | e[p + 2] << 16) + 1
    ha = (e[p + 4] | e[p + 5] << 8) + 1
    va = (e[p + 12] | e[p + 13] << 8) + 1
    return ha, va, pclk

src60 = next(p for p in slots if t(p) == (5120, 1440, 46900))
dst120 = next(p for p in slots if t(p)[:2] == (7680, 2160) and t(p)[2] == 222475)
new = bytearray(e[src60:src60 + 20])
PCLK = 58647                          # 10 kHz units: 586.47 MHz -> 75.000 Hz on 5280 x 1481
pclk = PCLK - 1
new[0:3] = bytes([pclk & 0xff, pclk >> 8 & 0xff, pclk >> 16])
new[3] &= 0x7f                        # not preferred
e[dst120:dst120 + 20] = new
e[o + 126] = (-sum(e[o + 1:o + 126])) & 0xff    # DisplayID section checksum
e[o + 127] = (-sum(e[o:o + 127])) & 0xff        # EDID block checksum
open(dst, "wb").write(e)
print("5120x1440 @ %.3f Hz added" % (PCLK * 1e4 / (5280 * 1481)))
