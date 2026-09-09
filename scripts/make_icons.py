#!/usr/bin/env python3
"""Generates the Unraid Drive app icons: a network drive whose front vents are the three Unraid bars.

Outputs, under App/Resources/Assets.xcassets:
  AppIcon.appiconset/{icon,icon_dark,icon_tinted}.png            default (Unraid orange → red)
  AppIcon-<key>.appiconset/{icon,icon_dark,icon_tinted}.png      alternate colours
  AppIconVision.solidimagestack/{Back,Middle,Front}.png          visionOS layers (default colour)
Run: python3 scripts/make_icons.py   (needs Pillow)
"""
import json, os
from PIL import Image, ImageDraw, ImageFilter

S = 1024          # output size
SS = 4            # supersampling
N = S * SS
OUT = os.path.join(os.path.dirname(__file__), "..", "App", "Resources", "Assets.xcassets")

# key: (label, bar gradient top, bar gradient bottom)
VARIANTS = {
    "default":  ("Unraid",     (0xFF, 0x8C, 0x2F), (0xE2, 0x28, 0x28)),
    "rosso":    ("Rosso",      (0xF0, 0x50, 0x50), (0xA8, 0x1C, 0x1C)),
    "blu":      ("Blu",        (0x4F, 0x8E, 0xFF), (0x1B, 0x4D, 0xB8)),
    "teal":     ("Verde acqua",(0x2F, 0xC4, 0xC4), (0x0B, 0x7C, 0x7C)),
    "viola":    ("Viola",      (0xA0, 0x74, 0xFF), (0x5A, 0x2F, 0xB8)),
    "grafite":  ("Grafite",    (0xD0, 0xD4, 0xD8), (0x7B, 0x83, 0x8B)),
}

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def vgradient(size, top, bottom):
    img = Image.new("RGBA", size)
    px = img.load()
    for y in range(size[1]):
        c = lerp(top, bottom, y / max(size[1] - 1, 1))
        for x in range(size[0]): px[x, y] = c + (255,)
    return img

def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return m

def background(dark: bool):
    top, bottom = ((0x2B, 0x2A, 0x29), (0x15, 0x14, 0x14)) if not dark else ((0x1A, 0x1A, 0x1A), (0x05, 0x05, 0x05))
    return vgradient((N, N), top, bottom)

def drive_layer(color=(255, 255, 255, 255), scale=1.0):
    """Network drive outline: sloped top, front face with a LED, network lead and plug below."""
    L = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(L)
    k = scale; cx = N / 2
    stroke = int(0.040 * N * k)
    def P(x, y): return (cx + (x - 0.5) * N * k, N / 2 + (y - 0.5) * N * k)
    # top (sloped body)
    top = [P(0.31, 0.17), P(0.69, 0.17), P(0.79, 0.49), P(0.21, 0.49)]
    d.polygon(top, outline=color, width=stroke)
    # front face
    fx0, fy0 = P(0.21, 0.49); fx1, fy1 = P(0.79, 0.66)
    d.rounded_rectangle([fx0, fy0, fx1, fy1], radius=int(0.02 * N * k), outline=color, width=stroke)
    # LED
    lx, ly = P(0.31, 0.575); r = 0.028 * N * k
    d.ellipse([lx - r, ly - r, lx + r, ly + r], outline=color, width=int(stroke * 0.8))
    # network lead: stem, horizontal line, plug
    sx, sy0 = P(0.50, 0.66); _, sy1 = P(0.50, 0.77)
    d.line([(sx, sy0), (sx, sy1)], fill=color, width=stroke)
    lx0, ly = P(0.16, 0.82); lx1, _ = P(0.84, 0.82)
    d.line([(lx0, ly), (lx1, ly)], fill=color, width=stroke, joint="curve")
    d.ellipse([lx0 - stroke / 2, ly - stroke / 2, lx0 + stroke / 2, ly + stroke / 2], fill=color)
    d.ellipse([lx1 - stroke / 2, ly - stroke / 2, lx1 + stroke / 2, ly + stroke / 2], fill=color)
    px0, py0 = P(0.42, 0.765); px1, py1 = P(0.58, 0.875)
    d.rounded_rectangle([px0, py0, px1, py1], radius=int(0.015 * N * k), fill=(0, 0, 0, 0), outline=color, width=stroke)
    # front face box for the bars (right part of the face)
    return L, (fx0, fy0, fx1 - fx0, fy1 - fy0, k)

def bars_layer(top, bottom, face, scale=1.0, mono=False):
    """Three Unraid bars as the drive's front vents (heights like the Unraid logo)."""
    L = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    fx0, fy0, fw, fh, k = face
    cy = fy0 + fh / 2
    bar_w = 0.045 * N * k; gap = 0.028 * N * k
    cx = fx0 + fw * 0.68
    heights = (0.56, 0.74, 0.44)
    xs = (cx - bar_w * 1.5 - gap, cx - bar_w / 2, cx + bar_w / 2 + gap)
    for bx, fhh in zip(xs, heights):
        bh = fhh * fh
        g = vgradient((int(bar_w), int(bh)), top, bottom) if not mono else Image.new("RGBA", (int(bar_w), int(bh)), (235, 235, 235, 255))
        m = rounded_mask((int(bar_w), int(bh)), int(bar_w / 2))
        L.paste(g, (int(bx), int(cy - bh / 2)), m)
    if not mono:
        glow = L.filter(ImageFilter.GaussianBlur(int(0.010 * N)))
        base = Image.new("RGBA", (N, N), (0, 0, 0, 0)); base.alpha_composite(glow); base.alpha_composite(L)
        return base
    return L

def compose(layers, size=S):
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    for l in layers: img.alpha_composite(l)
    return img.resize((size, size), Image.LANCZOS)

def write_json(path, obj):
    with open(path, "w") as f: json.dump(obj, f, indent=2); f.write("\n")

def appiconset(name, top, bottom):
    d = os.path.join(OUT, f"{name}.appiconset"); os.makedirs(d, exist_ok=True)
    drive, face = drive_layer()
    compose([background(False), drive, bars_layer(top, bottom, face)]).convert("RGB").save(os.path.join(d, "icon.png"))
    compose([background(True), drive, bars_layer(top, bottom, face)]).convert("RGB").save(os.path.join(d, "icon_dark.png"))
    # tinted: grayscale artwork on transparent background, the system supplies the colour
    tinted = compose([drive_layer(color=(200, 200, 200, 255))[0], bars_layer(top, bottom, face, mono=True)])
    tinted = Image.merge("RGBA", (*[tinted.convert("L")] * 3, tinted.split()[3]))
    tinted.save(os.path.join(d, "icon_tinted.png"))
    write_json(os.path.join(d, "Contents.json"), {"images": [
        {"filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
        {"appearances": [{"appearance": "luminosity", "value": "dark"}], "filename": "icon_dark.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
        {"appearances": [{"appearance": "luminosity", "value": "tinted"}], "filename": "icon_tinted.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
    ], "info": {"author": "xcode", "version": 1}})

def vision_layers(top, bottom):
    base = os.path.join(OUT, "AppIconVision.solidimagestack")
    drive, face = drive_layer(scale=0.78)
    compose([background(False)]).convert("RGB").save(os.path.join(base, "Back.solidimagestacklayer", "Content.imageset", "Back.png"))
    compose([drive]).save(os.path.join(base, "Middle.solidimagestacklayer", "Content.imageset", "Middle.png"))
    compose([bars_layer(top, bottom, face)]).save(os.path.join(base, "Front.solidimagestacklayer", "Content.imageset", "Front.png"))

if __name__ == "__main__":
    for key, (label, top, bottom) in VARIANTS.items():
        appiconset("AppIcon" if key == "default" else f"AppIcon-{key}", top, bottom)
    vision_layers(*VARIANTS["default"][1:])
    # a copy for README / App Store / kit
    os.makedirs(os.path.join(OUT, "..", "..", "..", "Screenshots"), exist_ok=True)
    print("icons written to", os.path.abspath(OUT))
