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
import json, os, re, subprocess, sys
from pathlib import Path

HOME = Path.home()
CFG = HOME / ".config"
TH = CFG / "theme"
BASE = (0x14, 0x16, 0x1c)
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


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def colors(pal):
    out = {}
    for n in ("primary", "secondary"):
        c = rgb(pal[n])
        out[n] = c
        out[n + "_dim"] = tuple(round(b + (a - b) * 0.33) for a, b in zip(c, BASE))
    return out


TOKEN = re.compile(r"@(primary|secondary)(_dim)?(_hex|_rgba)?(?:(\+[0-9a-f]{2})|:([0-9.]+)|(~))?@")


def render(text, cols):
    def sub(m):
        name = m.group(1) + (m.group(2) or "")
        r, g, b = cols[name]
        hx = "%02x%02x%02x" % (r, g, b)
        kind, plus, alpha, argb = m.group(3), m.group(4), m.group(5), m.group(6)
        if alpha:
            return f"rgba({r}, {g}, {b}, {alpha})"
        if argb:
            return "#ff" + hx
        if kind == "_hex":
            return hx
        if kind == "_rgba":
            return f"rgba({hx}{(plus or '+ff')[1:]})"
        return "#" + hx + (plus[1:] if plus else "")
    return TOKEN.sub(sub, text)


ICONS = CFG / "wlogout" / "icons"
# keep in step with the background block in hypr/hyprlock.conf (blur_passes 3, blur_size 6)
BLUR_SIGMA, BRIGHTNESS, CONTRAST = 22, 0.45, 0.9


def _screen_size():
    """Size of the first monitor (login image is cropped to it); desktop PC size as fallback."""
    try:
        out = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True, timeout=3).stdout
        m = json.loads(out)[0]
        return (int(m["width"]), int(m["height"]))
    except Exception:
        return (3440, 1440)


SCREEN = _screen_size()


def recolor_icons(cols):
    """The wlogout hover icons are flat single-colour PNGs: swap the colour, keep the alpha."""
    from PIL import Image
    r, g, b = cols["primary"]
    for f in ICONS.glob("*-hover.png"):
        a = Image.open(f).convert("RGBA").getchannel("A")
        out = Image.new("RGBA", a.size, (r, g, b, 0))
        out.putalpha(a)
        out.save(f)


def make_login_image(src):
    """Login screen background: same look as hyprlock (blurred, brightness 0.45, contrast 0.9)."""
    from PIL import Image, ImageFilter, ImageOps
    # crop/scale to the screen first (like swaybg "fill"): hyprlock blurs at screen resolution,
    # so the blur strength must not depend on the size of the source photo
    im = ImageOps.fit(Image.open(src).convert("RGB"), SCREEN, Image.LANCZOS)
    w, h = im.size
    small = im.resize((w // 4, h // 4), Image.LANCZOS).filter(ImageFilter.GaussianBlur(BLUR_SIGMA / 4))
    im = small.resize((w, h), Image.BICUBIC)
    lut = [round(max(0, min(255, ((v / 255 - 0.5) * CONTRAST + 0.5) * BRIGHTNESS * 255))) for v in range(256)]
    im = im.point(lut * 3)
    out = HOME / ".cache" / "theme" / "login.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    im.save(out.with_name("login.png.tmp"), "PNG")
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
        pal = dict(DEFAULT)
    elif argv and argv[0] == "--current":
        pal = json.loads((TH / "colors.json").read_text())
    elif argv:
        pal = json.loads(subprocess.check_output([sys.executable, str(TH / "palette.py"), argv[0]]))
    else:
        sys.exit(__doc__)
    pal = {k: pal[k] for k in ("primary", "secondary")} | {"source": pal.get("source", "default")}
    write(TH / "colors.json", json.dumps(pal, indent=1) + "\n")
    cols = colors(pal)
    for tpl, dest in TARGETS.items():
        write(CFG / dest, render((TH / "templates" / tpl).read_text(), cols))
    recolor_icons(cols)
    # login screen (root-owned): rendered here, installed by set-wallpaper.sh
    cache = HOME / ".cache" / "theme"
    cache.mkdir(parents=True, exist_ok=True)
    write(cache / "regreet.css", render((TH / "templates" / "regreet.css").read_text(), cols))
    make_login_image(CFG / "wall.png")
    print(f"primary {pal['primary']}  secondary {pal['secondary']}  ({pal['source']})")


if __name__ == "__main__":
    main(sys.argv[1:])
