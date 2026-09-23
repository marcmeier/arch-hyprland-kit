#!/usr/bin/env python3
"""Derive two accent colours from a wallpaper. Prints JSON.

The dark base, text and warn/crit colours stay fixed on purpose (readability,
semantics); only the accents follow the image. Falls back to the classic
cyan/green pair when the image has too little colour.
"""
import colorsys, json, sys
from PIL import Image

BASE = (0x14, 0x16, 0x1c)
FALLBACK = ("#00ff99", "#33ccff")


def lum(rgb):
    def f(c):
        c /= 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (f(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def hexc(rgb):
    return "#%02x%02x%02x" % rgb


def make_accent(h):
    """Vivid, light enough for the dark base (contrast >= 7)."""
    s, v = 0.80, 1.0
    for _ in range(20):
        rgb = tuple(round(c * 255) for c in colorsys.hsv_to_rgb(h, s, v))
        if contrast(rgb, BASE) >= 7:
            break
        s = max(0.35, s - 0.04)
    return rgb


def dominant_hues(path, bins=36):
    im = Image.open(path).convert("RGB")
    im.thumbnail((256, 256))
    hist = [0.0] * bins
    total = 0.0
    raw = im.tobytes()
    for k in range(0, len(raw), 3):
        r, g, b = raw[k], raw[k + 1], raw[k + 2]
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if s < 0.25 or v < 0.15:
            continue
        w = s * v * v  # bright, saturated pixels count most
        hist[int(h * bins) % bins] += w
        total += w
    # smooth over neighbouring bins so a hue split across a bin edge still wins
    sm = [hist[i - 1] * 0.5 + hist[i] + hist[(i + 1) % bins] * 0.5 for i in range(bins)]
    return sm, total, im.width * im.height


def main(path):
    sm, total, npx = dominant_hues(path)
    bins = len(sm)
    if total / npx < 0.01:  # (almost) grey image
        return {"primary": FALLBACK[1], "secondary": FALLBACK[0], "source": "fallback"}
    i1 = max(range(bins), key=sm.__getitem__)
    # second accent: strongest bin at least 40 degrees away, else a neighbour shift
    far = [i for i in range(bins) if min((i - i1) % bins, (i1 - i) % bins) * 10 >= 40]
    i2 = max(far, key=sm.__getitem__) if far else i1
    if not far or sm[i2] < sm[i1] * 0.12:
        h2 = (i1 * 10 + 5 + 35) / 360
    else:
        h2 = (i2 * 10 + 5) / 360
    h1 = (i1 * 10 + 5) / 360
    a1, a2 = make_accent(h1), make_accent(h2 % 1)
    return {"primary": hexc(a1), "secondary": hexc(a2), "source": "image"}


if __name__ == "__main__":
    print(json.dumps(main(sys.argv[1])))
