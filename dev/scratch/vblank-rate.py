#!/usr/bin/env python3
"""Count vblanks per second on a DRM CRTC with DRM_IOCTL_WAIT_VBLANK (does not draw anything itself).
usage: vblank-rate.py [seconds=3] [crtc_index=0] [/dev/dri/cardN]"""
import ctypes, fcntl, glob, os, struct, sys, time

secs = float(sys.argv[1]) if len(sys.argv) > 1 else 3
crtc = int(sys.argv[2]) if len(sys.argv) > 2 else 0
dev = sys.argv[3] if len(sys.argv) > 3 else None
if dev is None:
    for d in sorted(glob.glob("/dev/dri/card*")):
        if os.path.exists(f"/sys/class/drm/{os.path.basename(d)}-eDP-1"):
            dev = d
fd = os.open(dev, os.O_RDWR)
DRM_IOCTL_WAIT_VBLANK = 0xC018643A  # _IOWR('d', 0x3a, union drm_wait_vblank) (24 bytes)
RELATIVE = 0x1
HIGH_CRTC_SHIFT = 1
typ = RELATIVE | (crtc << HIGH_CRTC_SHIFT if crtc > 1 else (0x40000000 if crtc == 1 else 0))
stamps = []
end = time.monotonic() + secs
while time.monotonic() < end:
    buf = bytearray(struct.pack("IIQQ", typ, 1, 0, 0))
    fcntl.ioctl(fd, DRM_IOCTL_WAIT_VBLANK, buf)
    _, seq, sec, usec = struct.unpack("IIqq", buf)
    stamps.append(sec + usec / 1e6)
if len(stamps) > 2:
    d = [b - a for a, b in zip(stamps, stamps[1:])]
    print(f"{dev}: {len(d)/(stamps[-1]-stamps[0]):.1f} Hz avg, frame {min(d)*1e3:.2f}..{max(d)*1e3:.2f} ms")
