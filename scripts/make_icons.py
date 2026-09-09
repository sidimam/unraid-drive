#!/usr/bin/env python3
"""Builds the Unraid Drive icon set from the author's artwork in Design/:
  icon-light-source.png  (Unraid bars → line → network drive, light background)

Outputs under App/Resources/Assets.xcassets:
  AppIconDrive.appiconset/{icon,icon_dark,icon_tinted}.png       default colours (set renamed in build 16 so iOS/Files drop the cached old icon)
  AppIcon-<key>.appiconset/…                                    hue-shifted alternates (bars only)
  AppIconVision.solidimagestack/{Back,Middle,Front}.png          visionOS layers (background / drive / bars)
  AppIconMac.appiconset/mac_*.png                                 macOS (rounded square + shadow, 16–512 pt @1x/@2x)
  MenuBarIcon.imageset/menubar@{1,2}x.png                         macOS menu bar template glyph
  ../FileProvider/Resources/FPIcon.icns                           extension icon (Finder sidebar glyph)
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

def mac_icon(light):
    """macOS app icon: the light artwork inside the standard rounded square (824/1024 canvas,
    corner radius ~22.4 %), with the system-style drop shadow, on a transparent background."""
    from PIL import ImageDraw, ImageFilter
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    inset = 100; side = S - 2 * inset; r = int(side * 0.2237)
    mask = Image.new("L", (side, side), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, side - 1, side - 1), radius=r, fill=255)
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sh = Image.new("L", (S, S), 0); sh.paste(mask, (inset, inset + 10))
    shadow.putalpha(sh.filter(ImageFilter.GaussianBlur(14)).point(lambda a: int(a * 0.35)))
    canvas.alpha_composite(shadow)
    art = light.resize((side, side), Image.LANCZOS).convert("RGBA"); art.putalpha(mask)
    canvas.alpha_composite(art, (inset, inset))
    return canvas

def write_mac_icon_images(light):
    """Coloured variants of the Mac icon as plain images (the app swaps NSApp.applicationIconImage)."""
    for key, (label, hue) in VARIANTS.items():
        if key == "default": continue
        d = os.path.join(OUT, f"MacIcon-{key}.imageset"); os.makedirs(d, exist_ok=True)
        mac_icon(recolor(light, hue)).resize((512, 512), Image.LANCZOS).save(os.path.join(d, "icon.png"))
        write_json(os.path.join(d, "Contents.json"), {"images": [{"filename": "icon.png", "idiom": "universal", "scale": "1x"}, {"idiom": "universal", "scale": "2x"}, {"idiom": "universal", "scale": "3x"}], "info": {"author": "xcode", "version": 1}})

def write_mac_iconset(light):
    d = os.path.join(OUT, "AppIconMac.appiconset"); os.makedirs(d, exist_ok=True)
    big = mac_icon(light); images = []
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = pt * scale; name = f"mac_{pt}x{pt}@{scale}x.png"
            big.resize((px, px), Image.LANCZOS).save(os.path.join(d, name))
            images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}"})
    write_json(os.path.join(d, "Contents.json"), {"images": images, "info": {"author": "xcode", "version": 1}})

def write_menubar_icon(light):
    """Template image for the macOS menu bar (black glyph, alpha from the artwork), 18 pt @1x/@2x."""
    d = os.path.join(OUT, "MenuBarIcon.imageset"); os.makedirs(d, exist_ok=True)
    alpha = artwork_mask(light)
    glyph = Image.merge("RGBA", (Image.new("L", light.size, 0),) * 3 + (alpha,))
    bbox = alpha.getbbox(); glyph = glyph.crop(bbox)
    w, h = glyph.size; side = max(w, h) + 40
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0)); canvas.paste(glyph, ((side - w) // 2, (side - h) // 2))
    images = []
    for scale in (1, 2):
        px = 18 * scale; name = f"menubar@{scale}x.png"
        canvas.resize((px, px), Image.LANCZOS).save(os.path.join(d, name))
        images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x"})
    write_json(os.path.join(d, "Contents.json"), {"images": images, "info": {"author": "xcode", "version": 1},
                                                  "properties": {"template-rendering-intent": "template"}})

def write_fp_icon(light):
    """Icon of the File Provider extension itself: the Finder sidebar (macOS) draws the extension's
    icon as a monochrome glyph, so it is the artwork alone on a transparent background, as .icns."""
    import subprocess, shutil, tempfile
    alpha = artwork_mask(light)
    grey = light.convert("L").point(lambda x: int(x * 0.25))  # dark glyph, iOS/Finder tint it
    glyph = Image.merge("RGBA", (grey, grey, grey, alpha)).crop(alpha.getbbox())
    w, h = glyph.size; side = int(max(w, h) * 1.12)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0)); canvas.paste(glyph, ((side - w) // 2, (side - h) // 2))
    tmp = tempfile.mkdtemp(); iconset = os.path.join(tmp, "FPIcon.iconset"); os.makedirs(iconset)
    for pt in (16, 32, 128, 256, 512):
        canvas.resize((pt, pt), Image.LANCZOS).save(os.path.join(iconset, f"icon_{pt}x{pt}.png"))
        canvas.resize((pt * 2, pt * 2), Image.LANCZOS).save(os.path.join(iconset, f"icon_{pt}x{pt}@2x.png"))
    out = os.path.join(HERE, "..", "FileProvider", "Resources"); os.makedirs(out, exist_ok=True)
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.join(out, "FPIcon.icns")], check=True)
    shutil.rmtree(tmp)
    # Same glyph as an asset-catalog app icon of the extension (CFBundleIconName), for Launch Services.
    d = os.path.join(out, "Assets.xcassets", "FPIcon.appiconset"); os.makedirs(d, exist_ok=True)
    write_json(os.path.join(out, "Assets.xcassets", "Contents.json"), {"info": {"author": "xcode", "version": 1}})
    images = []
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            name = f"fp_{pt}x{pt}@{scale}x.png"
            canvas.resize((pt * scale, pt * scale), Image.LANCZOS).save(os.path.join(d, name))
            images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}"})
    write_json(os.path.join(d, "Contents.json"), {"images": images, "info": {"author": "xcode", "version": 1}})

def write_json(path, obj):
    with open(path, "w") as f: json.dump(obj, f, indent=2); f.write("\n")

def main():
    light = square(load("icon-light-source.png"))
    dark = darken(light)
    write_mac_iconset(light)
    write_mac_icon_images(light)
    write_menubar_icon(light)
    write_fp_icon(light)
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
