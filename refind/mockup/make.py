# Minimalist USB tile variants for the sb4edge rEFInd theme + a screen mockup per variant.
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import os, math
T = os.path.join(os.path.dirname(__file__), "..", "theme", "sb4edge")
OUT = os.path.dirname(__file__)
S = 4  # supersampling

def trident(d, cx, cy, h, col, w):
    """USB symbol centred at (cx, cy), height h, stroke w (all at supersampled scale)."""
    top, bot = cy - h/2, cy + h/2
    # stem
    d.line([(cx, top + h*0.16), (cx, bot - h*0.10)], fill=col, width=int(w))
    # arrow head
    a = h*0.11
    d.polygon([(cx, top), (cx - a*0.85, top + a*1.35), (cx + a*0.85, top + a*1.35)], fill=col)
    # base circle
    r = h*0.085
    d.ellipse([cx - r, bot - 2*r, cx + r, bot], fill=col)
    # left branch -> circle
    y0 = cy + h*0.18; x1 = cx - h*0.24; y1 = cy - h*0.02
    d.line([(cx, y0), (x1, y0 - h*0.10), (x1, y1)], fill=col, width=int(w), joint="curve")
    rr = h*0.06
    d.ellipse([x1 - rr, y1 - 2*rr + rr*0.3, x1 + rr, y1 + rr*0.3], fill=col)
    # right branch -> square
    y0 = cy + h*0.04; x2 = cx + h*0.24; y2 = cy - h*0.16
    d.line([(cx, y0), (x2, y0 - h*0.10), (x2, y2)], fill=col, width=int(w), joint="curve")
    q = h*0.055
    d.rectangle([x2 - q, y2 - 2*q, x2 + q, y2], fill=col)

def tile(color, glyph="#ffffff", outline=False):
    n = 360*S
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    pad, rad = 80*S, 40*S          # same footprint as the Ubuntu tile (200 px, ~20% radius)
    box = [pad, pad, n - pad, n - pad]
    if outline:
        d.rounded_rectangle(box, rad, outline=color, width=int(9*S))
    else:
        d.rounded_rectangle(box, rad, fill=color)
    trident(d, n/2, n/2, 120*S, glyph, 13*S)
    return im.resize((360, 360), Image.LANCZOS)

def glyph_only(col):
    n = 360*S
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    trident(d, n/2, n/2, 170*S, col, 16*S)
    return im.resize((360, 360), Image.LANCZOS)

variants = {
    "A-graphite": tile((58, 64, 78, 255)),
    "B-outline": tile((235, 238, 245, 235), glyph=(235, 238, 245, 235), outline=True),
    "C-symbol": glyph_only((235, 238, 245, 240)),
    "D-teal": tile((32, 168, 160, 255)),
}

bg = Image.open(os.path.join(T, "background.png")).convert("RGBA").resize((1440, 900), Image.LANCZOS)
ub = Image.open(os.path.join(T, "os_ubuntu.png")).convert("RGBA")
win = Image.open(os.path.join(T, "os_windows.png")).convert("RGBA")
tools = [Image.open(os.path.join(T, f)).convert("RGBA") for f in ("func_shutdown.png", "func_reset.png", "func_firmware.png")]
sel = Image.open(os.path.join(T, "selection_big.png")).convert("RGBA")

def screen(usb, label):
    im = bg.copy()
    big = 260
    xs = [720 - 340, 720, 720 + 340]
    y = 420
    for i, icon in enumerate([ub, win, usb]):
        ic = icon.resize((big, big), Image.LANCZOS)
        if i == 2:  # show the USB tile selected
            im.alpha_composite(sel.resize((big, big), Image.LANCZOS), (xs[i] - big//2, y - big//2))
        im.alpha_composite(ic, (xs[i] - big//2, y - big//2))
    for j, t in enumerate(tools):
        tt = t.resize((60, 60), Image.LANCZOS)
        im.alpha_composite(tt, (720 - 130 + j*130 - 30, 680))
    d = ImageDraw.Draw(im)
    try:
        f = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 26)
    except Exception:
        f = ImageFont.load_default()
    d.text((40, 36), label, font=f, fill=(255, 255, 255, 200))
    return im

shots = []
for k, v in variants.items():
    v.save(os.path.join(OUT, f"os_usb-{k}.png"))
    shots.append(screen(v, f"{k}   (no badge)"))
# current, for comparison
cur = Image.open(os.path.join(T, "os_usb.png")).convert("RGBA")
badge = Image.open(os.path.join(T, "vol_external.png")).convert("RGBA")
c = cur.copy(); c.alpha_composite(badge.resize((90, 90)), (270, 270))
shots.insert(0, screen(c, "current (icon + badge)"))

# 2 x 3 sheet at half size
w, h = 720, 450
sheet = Image.new("RGB", (w*2 + 30, h*3 + 40), (20, 20, 24))
for i, s in enumerate(shots):
    sheet.paste(s.convert("RGB").resize((w, h), Image.LANCZOS), (10 + (i % 2)*(w + 10), 10 + (i//2)*(h + 10)))
sheet.save(os.path.join(OUT, "usb-icon-mockup.png"))
print("ok")

# individual screens for the page
names = ["current"] + list(variants)
for n, s in zip(names, shots):
    s.convert("RGB").resize((960, 600), Image.LANCZOS).save(os.path.join(OUT, f"screen-{n}.jpg"), quality=88)
