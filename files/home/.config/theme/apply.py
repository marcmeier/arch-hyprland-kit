#!/usr/bin/env python3
"""Render the theme templates with the current palette.

  apply.py <image>     derive the palette from an image (via palette.py) and render
  apply.py --current   re-render with the stored palette (colors.json)
  apply.py --default   reset to the classic cyan/green palette and render

Template tokens: @primary@ -> #rrggbb, @primary+88@ -> #rrggbb88 (alpha suffix),
@primary:0.45@ -> rgba(r, g, b, 0.45), @primary~@ -> #ffrrggbb (Qt ARGB),
@primary_hex@ -> rrggbb, @primary_rgba+ee@ -> rgba(rrggbbee) (Hyprland).
Names: primary, secondary, primary_dim, secondary_dim (dim = 33 % over the base).
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
CONFIG = HOME / ".config"
THEME = CONFIG / "theme"
BASE = (0x14, 0x16, 0x1C)
DEFAULT = {"primary": "#33ccff", "secondary": "#00ff99"}

# template (in theme/templates/) -> destination (relative to ~/.config)
TARGETS = {
    "colors.css": "theme/colors.css",
    "colors.lua": "theme/colors.lua",
    "ghostty-colors": "theme/ghostty-colors",
    "mako": "mako/config",
    "hyprlock.conf": "hypr/hyprlock.conf",
    "starship.toml": "starship.toml",
    "qt6ct-kit.conf": "qt6ct/colors/kit.conf",
    "gtk3.css": "gtk-3.0/gtk.css",
    "gtk4.css": "gtk-4.0/gtk.css",
}


def rgb(hex_color):
    digits = hex_color.lstrip("#")
    return tuple(int(digits[i : i + 2], 16) for i in (0, 2, 4))


def colors(palette):
    """RGB tuples for every template name: the accents and their dimmed variants."""
    result = {}
    for name in ("primary", "secondary"):
        color = rgb(palette[name])
        result[name] = color
        result[name + "_dim"] = tuple(
            round(base + (channel - base) * 0.33) for channel, base in zip(color, BASE, strict=False)
        )
    return result


TOKEN = re.compile(r"@(primary|secondary)(_dim)?(_hex|_rgba)?(?:(\+[0-9a-f]{2})|:([0-9.]+)|(~))?@")


def render(text, rgb_colors):
    def replace(match):
        name = match.group(1) + (match.group(2) or "")
        r, g, b = rgb_colors[name]
        hex_rgb = f"{r:02x}{g:02x}{b:02x}"
        kind, plus, alpha, argb = match.group(3), match.group(4), match.group(5), match.group(6)
        if alpha:
            return f"rgba({r}, {g}, {b}, {alpha})"
        if argb:
            return "#ff" + hex_rgb
        if kind == "_hex":
            return hex_rgb
        if kind == "_rgba":
            return f"rgba({hex_rgb}{(plus or '+ff')[1:]})"
        return "#" + hex_rgb + (plus[1:] if plus else "")

    return TOKEN.sub(replace, text)


ICONS = CONFIG / "wlogout" / "icons"
# keep in step with the background block in hypr/hyprlock.conf (blur_passes 3, blur_size 6)
BLUR_SIGMA, BRIGHTNESS, CONTRAST = 22, 0.45, 0.9


def _screen_size():
    """Size of the first monitor (login image is cropped to it); desktop PC size as fallback."""
    try:
        answer = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True, timeout=3).stdout
        monitor = json.loads(answer)[0]
        return (int(monitor["width"]), int(monitor["height"]))
    except Exception:
        return (3440, 1440)


SCREEN = _screen_size()


def recolor_icons(rgb_colors):
    """The wlogout hover icons are flat single-colour PNGs: swap the colour, keep the alpha."""
    from PIL import Image

    r, g, b = rgb_colors["primary"]
    for icon in ICONS.glob("*-hover.png"):
        alpha = Image.open(icon).convert("RGBA").getchannel("A")
        recolored = Image.new("RGBA", alpha.size, (r, g, b, 0))
        recolored.putalpha(alpha)
        recolored.save(icon)


def make_login_image(src):
    """Login screen background: same look as hyprlock (blurred, brightness 0.45, contrast 0.9)."""
    from PIL import Image, ImageFilter, ImageOps

    # crop/scale to the screen first (like swaybg "fill"): hyprlock blurs at screen resolution,
    # so the blur strength must not depend on the size of the source photo
    image = ImageOps.fit(Image.open(src).convert("RGB"), SCREEN, Image.LANCZOS)
    width, height = image.size
    small = image.resize((width // 4, height // 4), Image.LANCZOS).filter(ImageFilter.GaussianBlur(BLUR_SIGMA / 4))
    image = small.resize((width, height), Image.BICUBIC)
    levels = [
        round(max(0, min(255, ((value / 255 - 0.5) * CONTRAST + 0.5) * BRIGHTNESS * 255))) for value in range(256)
    ]
    image = image.point(levels * 3)
    out = HOME / ".cache" / "theme" / "login.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    image.save(out.with_name("login.png.tmp"), "PNG")
    os.replace(out.with_name("login.png.tmp"), out)


def write(dest, text):
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_name(dest.name + ".tmp")
    tmp.write_text(text)
    if dest.exists():
        os.chmod(tmp, dest.stat().st_mode & 0o777)
    os.replace(tmp, dest)


def main(argv):
    if argv and argv[0] == "--default":
        palette = dict(DEFAULT)
    elif argv and argv[0] == "--current":
        palette = json.loads((THEME / "colors.json").read_text())
    elif argv:
        palette = json.loads(subprocess.check_output([sys.executable, str(THEME / "palette.py"), argv[0]]))
    else:
        sys.exit(__doc__)
    palette = {key: palette[key] for key in ("primary", "secondary")} | {"source": palette.get("source", "default")}
    write(THEME / "colors.json", json.dumps(palette, indent=1) + "\n")
    rgb_colors = colors(palette)
    for template, dest in TARGETS.items():
        write(CONFIG / dest, render((THEME / "templates" / template).read_text(), rgb_colors))
    recolor_icons(rgb_colors)
    # login screen (root-owned): rendered here, installed by set-wallpaper.sh
    cache = HOME / ".cache" / "theme"
    cache.mkdir(parents=True, exist_ok=True)
    write(cache / "regreet.css", render((THEME / "templates" / "regreet.css").read_text(), rgb_colors))
    make_login_image(CONFIG / "wall.png")
    print(f"primary {palette['primary']}  secondary {palette['secondary']}  ({palette['source']})")


if __name__ == "__main__":
    main(sys.argv[1:])
