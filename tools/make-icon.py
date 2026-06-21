#!/usr/bin/env python3
"""Generate L'Horizon's opaque 1024² master app icon + the macOS icon tile set.

L'Horizon's identity is "cartographer of time": stacked horizon lines receding
into a dawn-to-night sky, five faint lanes (3mo/6mo/1an/3ans/5ans) and a single
rising sun cresting the furthest line. The master is OPAQUE (no alpha) so
Assets.car carries a real AppIcon; macOS slots are the inset rounded tile.

Run:  python3 tools/make-icon.py
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
import json, math

ICONSET = Path(__file__).resolve().parent.parent / \
    "Sources/Resources/Assets.xcassets/AppIcon.appiconset"
SRC = ICONSET / "icon-1024.png"
N = 1024
SS = 2  # supersample for the master art


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def build_master() -> Image.Image:
    W = N * SS
    img = Image.new("RGB", (W, W), (0, 0, 0))
    px = img.load()

    # Dawn-to-night vertical gradient sky: deep night at top → warm dawn at the
    # horizon band → dark foreground at the bottom.
    night = (18, 22, 46)       # deep indigo night (top)
    dusk = (58, 46, 86)        # violet
    dawn = (236, 150, 96)      # warm amber dawn at horizon
    glow = (250, 206, 130)     # sun glow
    fg_top = (40, 32, 52)      # foreground land top
    fg_bot = (16, 14, 26)      # foreground land bottom

    horizon_y = int(W * 0.60)   # the furthest horizon line sits at 60% down
    for y in range(W):
        if y < horizon_y:
            t = y / horizon_y
            # ease toward dawn near the horizon
            if t < 0.55:
                c = lerp(night, dusk, t / 0.55)
            else:
                c = lerp(dusk, dawn, (t - 0.55) / 0.45)
        else:
            t = (y - horizon_y) / (W - horizon_y)
            c = lerp(fg_top, fg_bot, t)
        for x in range(W):
            px[x, y] = c

    draw = ImageDraw.Draw(img, "RGBA")

    # Sun glow: a soft radial bloom cresting the furthest horizon line, slightly
    # right of center.
    sun_cx, sun_cy, sun_r = int(W * 0.5), horizon_y, int(W * 0.10)
    glow_layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow_layer)
    for rr, a in [(int(sun_r * 3.4), 26), (int(sun_r * 2.3), 40),
                  (int(sun_r * 1.5), 70), (sun_r, 230)]:
        gd.ellipse([sun_cx - rr, sun_cy - rr, sun_cx + rr, sun_cy + rr],
                   fill=glow + (a,))
    glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(W // 90))
    img = Image.alpha_composite(img.convert("RGBA"), glow_layer).convert("RGB")
    draw = ImageDraw.Draw(img, "RGBA")

    # Mask the lower half of the sun so it reads as "rising" behind the horizon.
    draw.rectangle([0, horizon_y, W, W], fill=lerp(fg_top, fg_bot, 0.0) + (255,))

    # Five horizon lanes receding upward from the foreground — the signature.
    # They get fainter and closer together toward the top (perspective).
    lane_color = (250, 232, 205)
    base_y = int(W * 0.92)
    for i in range(5):
        # geometric spacing → perspective compression toward the horizon
        frac = 1 - (1 - i / 5) ** 1.7
        y = int(base_y - (base_y - horizon_y) * frac)
        alpha = int(210 - i * 30)
        thick = max(int(SS * (5 - i * 0.7)), SS)
        # gentle inset so nearer lanes are wider
        inset = int(W * (0.06 + i * 0.05))
        draw.line([(inset, y), (W - inset, y)], fill=lane_color + (alpha,), width=thick)

    out = img.resize((N, N), Image.LANCZOS)
    out.save(SRC)
    return out


# (filename, px) for every mac idiom slot.
MAC_SLOTS = [
    ("mac-16.png", 16), ("mac-16@2x.png", 32),
    ("mac-32.png", 32), ("mac-32@2x.png", 64),
    ("mac-128.png", 128), ("mac-128@2x.png", 256),
    ("mac-256.png", 256), ("mac-256@2x.png", 512),
    ("mac-512.png", 512), ("mac-512@2x.png", 1024),
]

CANVAS = 1024
BODY = 824
MARGIN = (CANVAS - BODY) // 2
RADIUS = round(BODY * 0.2237)
TILE_SS = 4


def build_tile(master: Image.Image) -> Image.Image:
    src = master.convert("RGBA").resize((BODY * TILE_SS, BODY * TILE_SS), Image.LANCZOS)
    mask = Image.new("L", (BODY * TILE_SS, BODY * TILE_SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, BODY * TILE_SS - 1, BODY * TILE_SS - 1],
        radius=RADIUS * TILE_SS, fill=255)
    body = Image.new("RGBA", (BODY * TILE_SS, BODY * TILE_SS), (0, 0, 0, 0))
    body.paste(src, (0, 0), mask)
    body = body.resize((BODY, BODY), Image.LANCZOS)

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [MARGIN, MARGIN + 8, CANVAS - MARGIN, CANVAS - MARGIN + 8],
        radius=RADIUS, fill=(0, 0, 0, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    canvas = Image.alpha_composite(canvas, shadow)
    canvas.paste(body, (MARGIN, MARGIN), body)
    return canvas


def main() -> None:
    master = build_master()
    print(f"  wrote icon-1024.png (opaque {N}px master)")
    tile = build_tile(master)
    for name, px in MAC_SLOTS:
        tile.resize((px, px), Image.LANCZOS).save(ICONSET / name)
        print(f"  wrote {name} ({px}px)")

    images = [
        {"filename": "icon-1024.png", "idiom": "universal",
         "platform": "ios", "size": "1024x1024"},
    ]
    sizes = ["16x16", "16x16", "32x32", "32x32", "128x128", "128x128",
             "256x256", "256x256", "512x512", "512x512"]
    for (name, _), size in zip(MAC_SLOTS, sizes):
        scale = "2x" if "@2x" in name else "1x"
        images.append({"filename": name, "idiom": "mac", "scale": scale, "size": size})
    (ICONSET / "Contents.json").write_text(
        json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    print("  rewrote Contents.json (ios + mac idioms)")


if __name__ == "__main__":
    main()
