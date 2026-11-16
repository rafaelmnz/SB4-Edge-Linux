#!/usr/bin/env python3
"""Generates the sb4edge rEFInd theme as SVG (rendered to PNG by build-theme.sh with rsvg-convert).
Screen: 2880x1800 (Galaxy Book4 Edge 16). Tiles carry their own logo + name (rEFInd's label text is hidden)."""
import math, os, sys
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
W, H = 2880, 1800
T = 360                      # big icon (tile) size, = big_icon_size
S = 120                      # small icon size, = small_icon_size
FONT = "Ubuntu Sans"

def save(name, svg): open(f"{out}/{name}.svg", "w").write(svg)

# ---------- background ----------
save("background", f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
 <defs>
  <linearGradient id="base" x1="0" y1="0" x2="0.35" y2="1">
   <stop offset="0" stop-color="#0d1020"/><stop offset="1" stop-color="#05060c"/></linearGradient>
  <radialGradient id="warm" cx="0.5" cy="0.5" r="0.5">
   <stop offset="0" stop-color="#e95420" stop-opacity="0.34"/><stop offset="1" stop-color="#e95420" stop-opacity="0"/></radialGradient>
  <radialGradient id="cool" cx="0.5" cy="0.5" r="0.5">
   <stop offset="0" stop-color="#1e78ff" stop-opacity="0.30"/><stop offset="1" stop-color="#1e78ff" stop-opacity="0"/></radialGradient>
  <radialGradient id="violet" cx="0.5" cy="0.5" r="0.5">
   <stop offset="0" stop-color="#7a3cff" stop-opacity="0.16"/><stop offset="1" stop-color="#7a3cff" stop-opacity="0"/></radialGradient>
  <radialGradient id="vig" cx="0.5" cy="0.45" r="0.75">
   <stop offset="0.55" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity="0.55"/></radialGradient>
 </defs>
 <rect width="{W}" height="{H}" fill="url(#base)"/>
 <ellipse cx="{W*0.22}" cy="{H*0.86}" rx="{W*0.42}" ry="{H*0.55}" fill="url(#warm)"/>
 <ellipse cx="{W*0.80}" cy="{H*0.12}" rx="{W*0.44}" ry="{H*0.58}" fill="url(#cool)"/>
 <ellipse cx="{W*0.55}" cy="{H*0.55}" rx="{W*0.35}" ry="{H*0.40}" fill="url(#violet)"/>
 <rect width="{W}" height="{H}" fill="url(#vig)"/>
</svg>''')

# ---------- tiles ----------
def tile(logo, name):
    # minimalist: the logo alone, floating on the background (name/title hidden)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{T}" height="{T}" viewBox="0 0 {T} {T}">
 <g transform="translate({T/2},{T*0.46})">{logo}</g>
</svg>'''

def ubuntu_logo(sz):
    # Ubuntu-style app badge: orange rounded square, white "circle of friends" (ring in three arcs + three heads)
    h = sz / 2; R = sz * 0.225; w = sz * 0.07; hr = sz * 0.072; hd = R + sz * 0.085
    parts = [f'<rect x="{-h}" y="{-h}" width="{sz}" height="{sz}" rx="{sz*0.22}" fill="#e95420"/>']
    heads = [180, 60, 300]
    for a in heads:
        x, y = hd * math.cos(math.radians(a)), -hd * math.sin(math.radians(a))
        parts.append(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="{hr:.2f}" fill="#fff"/>')
    gap = 36   # degrees of ring left open around each head
    for i, a in enumerate(heads):
        a0 = a + gap; a1 = heads[(i + 1) % 3] - gap
        if a1 <= a0: a1 += 360
        p0 = (R * math.cos(math.radians(a0)), -R * math.sin(math.radians(a0)))
        p1 = (R * math.cos(math.radians(a1)), -R * math.sin(math.radians(a1)))
        parts.append(f'<path d="M{p0[0]:.2f},{p0[1]:.2f} A{R},{R} 0 0 0 {p1[0]:.2f},{p1[1]:.2f}" '
                     f'fill="none" stroke="#fff" stroke-width="{w:.2f}" stroke-linecap="round"/>')
    return "".join(parts)

def windows_logo(sz):
    g = sz * 0.045; q = (sz - g) / 2; o = -sz / 2
    grad = ('<defs><linearGradient id="wb" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#3fb4ff"/>'
            '<stop offset="1" stop-color="#0063d6"/></linearGradient></defs>')
    sq = "".join(f'<rect x="{o + i*(q+g):.2f}" y="{o + j*(q+g):.2f}" width="{q:.2f}" height="{q:.2f}" rx="{sz*0.025:.2f}" fill="url(#wb)"/>'
                 for i in (0, 1) for j in (0, 1))
    return grad + sq

save("os_ubuntu", tile(ubuntu_logo(T * 0.50), "Ubuntu"))
save("os_windows", tile(windows_logo(T * 0.44), "Windows"))

# ---------- removable media (USB stick / SD card): rEFInd scans external volumes ----------
def usb_logo(sz):
    # a USB stick: rounded body with a soft gradient, metal plug with two contacts, small trident mark
    bw, bh = sz * 0.46, sz * 0.66; pw, ph = sz * 0.30, sz * 0.22
    by = -bh / 2 + ph * 0.45
    grad = ('<defs><linearGradient id="ub" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#5ee0c6"/>'
            '<stop offset="1" stop-color="#1d8f9e"/></linearGradient></defs>')
    plug = (f'<rect x="{-pw/2:.2f}" y="{by - ph:.2f}" width="{pw:.2f}" height="{ph + sz*0.04:.2f}" rx="{sz*0.03:.2f}" fill="#d7dbe6"/>'
            f'<rect x="{-pw*0.30:.2f}" y="{by - ph*0.72:.2f}" width="{pw*0.18:.2f}" height="{ph*0.26:.2f}" fill="#5b6275"/>'
            f'<rect x="{pw*0.12:.2f}" y="{by - ph*0.72:.2f}" width="{pw*0.18:.2f}" height="{ph*0.26:.2f}" fill="#5b6275"/>')
    body = f'<rect x="{-bw/2:.2f}" y="{by:.2f}" width="{bw:.2f}" height="{bh:.2f}" rx="{sz*0.10:.2f}" fill="url(#ub)"/>'
    cy = by + bh * 0.55; s = sz * 0.13; w = sz * 0.028
    mark = (f'<g stroke="#fff" stroke-width="{w:.2f}" stroke-linecap="round" fill="none">'
            f'<path d="M0,{cy + s:.2f} V{cy - s:.2f}"/>'
            f'<path d="M0,{cy + s*0.35:.2f} L{-s*0.6:.2f},{cy - s*0.05:.2f} V{cy - s*0.4:.2f}"/>'
            f'<path d="M0,{cy + s*0.6:.2f} L{s*0.6:.2f},{cy + s*0.2:.2f} V{cy - s*0.15:.2f}"/></g>'
            f'<circle cx="0" cy="{cy - s - w:.2f}" r="{w*1.3:.2f}" fill="#fff"/>')
    return grad + plug + body + mark

usb = tile(usb_logo(T * 0.50), "USB")
# rEFInd picks os_<name> from the loader/volume it finds on the stick; anything that is not the internal Ubuntu
# or Windows gets the USB tile (os_ubuntu/os_windows stay the internal systems' logos; external entries also
# carry the vol_external badge).
for n in ("usb", "unknown", "legacy", "linux", "win", "win8", "grub", "refind", "debian", "fedora", "arch",
          "mint", "elementary", "redhat", "suse", "opensuse", "centos", "gentoo", "manjaro", "pop", "kali"):
    save(f"os_{n}", usb)

# badges: only removable media get a mark (bottom-right of the tile); internal volumes get none
B = T // 4
save("vol_external", f'''<svg xmlns="http://www.w3.org/2000/svg" width="{B}" height="{B}" viewBox="0 0 {B} {B}">
 <circle cx="{B/2}" cy="{B/2}" r="{B*0.42}" fill="#0e1424" fill-opacity="0.85" stroke="#5ee0c6" stroke-width="{B*0.05}"/>
 <g transform="translate({B/2},{B*0.47})">{usb_logo(B * 0.62).replace('id="ub"', 'id="ubb"').replace('url(#ub)', 'url(#ubb)')}</g>
</svg>''')
for n in ("internal", "optical", "net"):
    save(f"vol_{n}", f'<svg xmlns="http://www.w3.org/2000/svg" width="{B}" height="{B}" viewBox="0 0 {B} {B}"/>')

# ---------- selection highlights ----------
save("selection_big", f'''<svg xmlns="http://www.w3.org/2000/svg" width="{T}" height="{T}" viewBox="0 0 {T} {T}">
 <defs><radialGradient id="g" cx="0.5" cy="0.5" r="0.5">
  <stop offset="0" stop-color="#ffffff" stop-opacity="0.26"/><stop offset="0.55" stop-color="#ffffff" stop-opacity="0.08"/>
  <stop offset="1" stop-color="#ffffff" stop-opacity="0"/></radialGradient></defs>
 <circle cx="{T/2}" cy="{T*0.46}" r="{T*0.47}" fill="url(#g)"/>
 <circle cx="{T/2}" cy="{T*0.92}" r="7" fill="#ffffff" fill-opacity="0.9"/>
</svg>''')
save("selection_small", f'''<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">
 <defs><radialGradient id="g" cx="0.5" cy="0.5" r="0.5">
  <stop offset="0" stop-color="#ffffff" stop-opacity="0.22"/><stop offset="1" stop-color="#ffffff" stop-opacity="0"/></radialGradient></defs>
 <circle cx="{S/2}" cy="{S/2}" r="{S/2}" fill="url(#g)"/>
</svg>''')

# ---------- tool icons (line icons in a faint circle) ----------
def tool(paths):
    c = S / 2
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">
 <g transform="translate({c},{c})" fill="none" stroke="#ffffff" stroke-opacity="0.55" stroke-width="4" stroke-linecap="round" stroke-linejoin="round">{paths}</g>
</svg>'''
rr = 22
def arc(r, a0, a1):
    p = lambda a: (r * math.sin(math.radians(a)), -r * math.cos(math.radians(a)))
    (x0, y0), (x1, y1) = p(a0), p(a1); large = 1 if (a1 - a0) % 360 > 180 else 0
    return f'M{x0:.2f},{y0:.2f} A{r},{r} 0 {large} 1 {x1:.2f},{y1:.2f}'
save("func_shutdown", tool(f'<path d="{arc(rr, 40, 320)}"/><path d="M0,-28 V-4"/>'))
save("func_reset", tool(f'<path d="{arc(rr, 60, 350)}"/><path d="M2,-31 L-4,-22 L6,-15"/>'))
pins = " ".join(f"M{x},-24 V-31 M{x},24 V31 M-24,{x} H-31 M24,{x} H31" for x in (-9, 0, 9))
save("func_firmware", tool(f'<rect x="-19" y="-19" width="38" height="38" rx="7"/><rect x="-7" y="-7" width="14" height="14" rx="2"/><path d="{pins}" stroke-width="4"/>'))
print("svg written to", out)
