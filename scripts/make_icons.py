#!/usr/bin/env python3
"""Builds the Unraid Drive icon set from the author's artwork in Design/:
  icon-light-source.png  (Unraid bars → line → network drive, light background)

Outputs under App/Resources/Assets.xcassets:
  AppIconDrive.appiconset/{icon,icon_dark,icon_tinted}.png       default colours (set renamed in build 16 so iOS/Files drop the cached old icon)
  AppIcon-<key>.appiconset/…                                    hue-shifted alternates (bars only)
  AppIconVision.solidimagestack/{Back,Middle,Front}.png          visionOS layers (background / drive / bars)
Run: python3 scripts/make_icons.py   (needs Pillow)
"""
import json, os
from PIL import Image, ImageChops

HERE = os.path.dirname(__file__)
DESIGN = os.path.join(HERE, "..", "Design")
OUT = os.path.join(HERE, "..", "App", "Resources", "Assets.xcassets")
S = 1024

# key: (label, hue for the bars on PIL's 0-255 hue scale; None = original orange, "grey" = desaturate)
VARIANTS = {
    "default": ("Unraid", None),
    "rosso":   ("Rosso", 253),
    "blu":     ("Blu", 152),
    "teal":    ("Verde acqua", 122),
    "viola":   ("Viola", 186),
    "grafite": ("Grafite", "grey"),
}

def load(name):
    return Image.open(os.path.join(DESIGN, name)).convert("RGB")

def square(im, crop=0.0):
    w, h = im.size
    side = min(w, h); l = (w - side) // 2; t = (h - side) // 2
    im = im.crop((l, t, l + side, t + side))
    if crop:
        c = int(side * crop)
        im = im.crop((c, c, side - c, side - c))
    return im.resize((S, S), Image.LANCZOS)

def bars_mask(rgb):
    """Soft mask of the orange/yellow artwork: saturated warm pixels."""
    h, s, v = rgb.convert("HSV").split()
    warm = h.point(lambda x: 255 if (x < 50 or x > 241) else 0)          # hue 0-70° or >340°
    sat = s.point(lambda x: 0 if x < 64 else min(255, (x - 64) * 5))      # ramps in above 25 % saturation
    bright = v.point(lambda x: 255 if x > 64 else 0)
    return ImageChops.multiply(ImageChops.multiply(warm, sat), bright)

def recolor(rgb, target):
    h, s, v = rgb.convert("HSV").split()
    if target == "grey":
        s2 = s.point(lambda x: x // 10); h2 = h
        v = v.point(lambda x: int(x * 0.62))          # graphite: mid grey, not white
    else:
        h2 = Image.new("L", h.size, int(target)); s2 = s
    new = Image.merge("HSV", (h2, s2, v)).convert("RGB")
    return Image.composite(new, rgb, bars_mask(rgb))

def darken(light):
    """Dark-appearance icon from the light artwork: dark background, the drive turned light grey
    (its shading inverted), bars untouched."""
    art = artwork_mask(light); bars = bars_mask(light)
    drive = ImageChops.subtract(art, bars)
    h, s, v = light.convert("HSV").split()
    v_inv = v.point(lambda x: int(255 - (255 - x) * 0.0 - x * 0.0 + (255 - x) * 0.65 + 60) if False else min(255, 255 - x + 95))
    light_drive = Image.merge("HSV", (h, s.point(lambda x: x // 3), v_inv)).convert("RGB")
    with_drive = Image.composite(light_drive, light, drive)
    w, hgt = light.size
    bg = Image.new("RGB", (w, hgt)); px = bg.load()
    top, bottom = (0x30, 0x35, 0x3D), (0x19, 0x1C, 0x22)
    for y in range(hgt):
        t = y / (hgt - 1); c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(w): px[x, y] = c
    return Image.composite(with_drive, bg, art)

def artwork_mask(rgb):
    """Everything that is not background (soft edge)."""
    bg = rgb.crop((2, 2, 10, 10)).resize((1, 1), Image.BOX).getpixel((0, 0))
    diff = ImageChops.difference(rgb, Image.new("RGB", rgb.size, bg)).convert("L")
    return diff.point(lambda x: 0 if x < 14 else min(255, (x - 14) * 6))

def tinted(rgb_light):
    """Grayscale artwork on a transparent background (iOS applies the tint)."""
    grey = rgb_light.convert("L").point(lambda x: int(255 - (255 - x) * 0.9))
    out = Image.merge("RGBA", (grey, grey, grey, artwork_mask(rgb_light)))
    return out

def vision_layers(light):
    art = artwork_mask(light); bars = bars_mask(light)
    drive = ImageChops.subtract(art, bars)
    r, g, b = light.split()
    bg = light.crop((2, 2, 10, 10)).resize((1, 1), Image.BOX).getpixel((0, 0))
    return Image.new("RGB", light.size, bg), Image.merge("RGBA", (r, g, b, drive)), Image.merge("RGBA", (r, g, b, bars))

def write_json(path, obj):
    with open(path, "w") as f: json.dump(obj, f, indent=2); f.write("\n")

def main():
    light = square(load("icon-light-source.png"))
    dark = darken(light)
    for key, (label, hue) in VARIANTS.items():
        d = os.path.join(OUT, "AppIconDrive.appiconset" if key == "default" else f"AppIcon-{key}.appiconset")
        os.makedirs(d, exist_ok=True)
        l = light if hue is None else recolor(light, hue)
        k = dark if hue is None else recolor(dark, hue)
        l.save(os.path.join(d, "icon.png")); k.save(os.path.join(d, "icon_dark.png")); tinted(l).save(os.path.join(d, "icon_tinted.png"))
        write_json(os.path.join(d, "Contents.json"), {"images": [
            {"filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
            {"appearances": [{"appearance": "luminosity", "value": "dark"}], "filename": "icon_dark.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
            {"appearances": [{"appearance": "luminosity", "value": "tinted"}], "filename": "icon_tinted.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
        ], "info": {"author": "xcode", "version": 1}})
    base = os.path.join(OUT, "AppIconVision.solidimagestack")
    back, drive, bars = vision_layers(light)
    back.save(os.path.join(base, "Back.solidimagestacklayer", "Content.imageset", "Back.png"))
    drive.save(os.path.join(base, "Middle.solidimagestacklayer", "Content.imageset", "Middle.png"))
    bars.save(os.path.join(base, "Front.solidimagestacklayer", "Content.imageset", "Front.png"))
    print("icons written to", os.path.abspath(OUT))

if __name__ == "__main__":
    main()
