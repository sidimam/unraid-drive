#!/usr/bin/env python3
"""Generates the Unraid Drive app icons: a Files-style folder holding the three Unraid bars.

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

def folder_layer(color=(255, 255, 255, 255), scale=1.0):
    """Files-style folder outline (tab + body drawn as one shape), centred."""
    w = 0.66 * N * scale; h = 0.50 * N * scale
    x0 = (N - w) / 2; y0 = (N - h) / 2 + 0.03 * N
    stroke = int(0.045 * N * scale)
    r = int(0.075 * N * scale)
    tab_w = 0.40 * w; tab_top = y0; body_top = y0 + 0.10 * h
    def union(inset):
        m = Image.new("L", (N, N), 0); d = ImageDraw.Draw(m)
        d.rounded_rectangle([x0 + inset, body_top + inset, x0 + w - inset, y0 + h - inset], radius=max(r - inset, 1), fill=255)
        d.rounded_rectangle([x0 + inset, tab_top + inset, x0 + tab_w - inset, body_top + r], radius=max(int(r * 0.6) - inset, 1), fill=255)
        return m
    outer, inner = union(0), union(stroke)
    outline = Image.eval(Image.composite(Image.new("L", (N, N), 0), outer, inner), lambda v: v)
    L = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    L.paste(Image.new("RGBA", (N, N), color), (0, 0), outline)
    return L, (x0, body_top, w, h - 0.10 * h)

def bars_layer(top, bottom, body, scale=1.0, mono=False):
    """Three Unraid bars inside the folder body (heights like the Unraid logo)."""
    L = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    x0, y0, w, h = body
    cx = x0 + w / 2; cy = y0 + h / 2 + 0.02 * h
    bar_w = 0.085 * w; gap = 0.075 * w
    heights = (0.46, 0.62, 0.36)
    xs = (cx - bar_w * 1.5 - gap, cx - bar_w / 2, cx + bar_w / 2 + gap)
    for bx, fh in zip(xs, heights):
        bh = fh * h
        by0 = cy - bh / 2; by1 = cy + bh / 2
        g = vgradient((int(bar_w), int(bh)), top, bottom) if not mono else Image.new("RGBA", (int(bar_w), int(bh)), (235, 235, 235, 255))
        m = rounded_mask((int(bar_w), int(bh)), int(bar_w / 2))
        L.paste(g, (int(bx), int(by0)), m)
    if not mono:
        glow = L.filter(ImageFilter.GaussianBlur(int(0.012 * N)))
        glow = Image.eval(glow, lambda v: v)  # keep as is
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
    folder, body = folder_layer()
    compose([background(False), folder, bars_layer(top, bottom, body)]).convert("RGB").save(os.path.join(d, "icon.png"))
    compose([background(True), folder, bars_layer(top, bottom, body)]).convert("RGB").save(os.path.join(d, "icon_dark.png"))
    # tinted: grayscale artwork on transparent background, the system supplies the colour
    tinted = compose([folder_layer(color=(200, 200, 200, 255))[0], bars_layer(top, bottom, body, mono=True)])
    tinted = Image.merge("RGBA", (*[tinted.convert("L")] * 3, tinted.split()[3]))
    tinted.save(os.path.join(d, "icon_tinted.png"))
    write_json(os.path.join(d, "Contents.json"), {"images": [
        {"filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
        {"appearances": [{"appearance": "luminosity", "value": "dark"}], "filename": "icon_dark.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
        {"appearances": [{"appearance": "luminosity", "value": "tinted"}], "filename": "icon_tinted.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
    ], "info": {"author": "xcode", "version": 1}})

def vision_layers(top, bottom):
    base = os.path.join(OUT, "AppIconVision.solidimagestack")
    folder, body = folder_layer(scale=0.78)
    compose([background(False)]).convert("RGB").save(os.path.join(base, "Back.solidimagestacklayer", "Content.imageset", "Back.png"))
    compose([folder]).save(os.path.join(base, "Middle.solidimagestacklayer", "Content.imageset", "Middle.png"))
    compose([bars_layer(top, bottom, body, scale=0.78)]).save(os.path.join(base, "Front.solidimagestacklayer", "Content.imageset", "Front.png"))

if __name__ == "__main__":
    for key, (label, top, bottom) in VARIANTS.items():
        appiconset("AppIcon" if key == "default" else f"AppIcon-{key}", top, bottom)
    vision_layers(*VARIANTS["default"][1:])
    # a copy for README / App Store / kit
    os.makedirs(os.path.join(OUT, "..", "..", "..", "Screenshots"), exist_ok=True)
    print("icons written to", os.path.abspath(OUT))
