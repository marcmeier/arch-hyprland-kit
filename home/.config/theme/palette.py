#!/usr/bin/env python3
"""Derive two accent colours from a wallpaper. Prints JSON.

The dark base, text and warn/crit colours stay fixed on purpose (readability,
semantics); only the accents follow the image. Falls back to the classic
cyan/green pair when the image has too little colour.
"""

import colorsys
import json
import sys

from PIL import Image

BASE = (0x14, 0x16, 0x1C)
FALLBACK = ("#00ff99", "#33ccff")
BIN_DEGREES = 10  # hue histogram: 36 bins of 10 degrees


def luminance(rgb):
    """Relative luminance (WCAG) of an 8-bit RGB colour."""

    def linear(channel):
        channel /= 255
        return channel / 12.92 if channel <= 0.03928 else ((channel + 0.055) / 1.055) ** 2.4

    r, g, b = (linear(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    lum_a, lum_b = luminance(a), luminance(b)
    return (max(lum_a, lum_b) + 0.05) / (min(lum_a, lum_b) + 0.05)


def to_hex(rgb):
    return "#{:02x}{:02x}{:02x}".format(*rgb)


def make_accent(hue):
    """Vivid, light enough for the dark base (contrast >= 7)."""
    saturation, value = 0.80, 1.0
    for _ in range(20):
        rgb = tuple(round(c * 255) for c in colorsys.hsv_to_rgb(hue, saturation, value))
        if contrast(rgb, BASE) >= 7:
            break
        saturation = max(0.35, saturation - 0.04)
    return rgb


def dominant_hues(path, bins=360 // BIN_DEGREES):
    """Hue histogram of the image, weighted towards bright, saturated pixels.
    Returns (smoothed histogram, total weight, number of pixels)."""
    image = Image.open(path).convert("RGB")
    image.thumbnail((256, 256))
    histogram = [0.0] * bins
    total = 0.0
    pixels = image.tobytes()
    for offset in range(0, len(pixels), 3):
        r, g, b = pixels[offset], pixels[offset + 1], pixels[offset + 2]
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if s < 0.25 or v < 0.15:
            continue
        weight = s * v * v  # bright, saturated pixels count most
        histogram[int(h * bins) % bins] += weight
        total += weight
    # smooth over neighbouring bins so a hue split across a bin edge still wins
    smoothed = [histogram[i - 1] * 0.5 + histogram[i] + histogram[(i + 1) % bins] * 0.5 for i in range(bins)]
    return smoothed, total, image.width * image.height


def bin_hue(index):
    """Hue (0..1) at the centre of a histogram bin."""
    return (index * BIN_DEGREES + BIN_DEGREES / 2) / 360


def main(path):
    histogram, total, pixel_count = dominant_hues(path)
    bins = len(histogram)
    if total / pixel_count < 0.01:  # (almost) grey image
        return {"primary": FALLBACK[1], "secondary": FALLBACK[0], "source": "fallback"}
    top = max(range(bins), key=histogram.__getitem__)
    # second accent: strongest bin at least 40 degrees away, else the top hue shifted by 35 degrees
    distant = [i for i in range(bins) if min((i - top) % bins, (top - i) % bins) * BIN_DEGREES >= 40]
    second = max(distant, key=histogram.__getitem__) if distant else top
    if not distant or histogram[second] < histogram[top] * 0.12:
        second_hue = (top * BIN_DEGREES + BIN_DEGREES / 2 + 35) / 360
    else:
        second_hue = bin_hue(second)
    primary, secondary = make_accent(bin_hue(top)), make_accent(second_hue % 1)
    return {"primary": to_hex(primary), "secondary": to_hex(secondary), "source": "image"}


if __name__ == "__main__":
    print(json.dumps(main(sys.argv[1])))
