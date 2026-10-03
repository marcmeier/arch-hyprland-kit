#!/usr/bin/env python3
"""Render the theme templates with the current palette, in the dark or the light look.

  apply.py <image>                     derive the palette from an image (via palette.py) and render
  apply.py --current                   re-render with the stored palette (colors.json)
  apply.py --default                   reset to the classic cyan/green palette and render
  apply.py --appearance dark|light|auto   choose the look and render it (auto: light from sunrise
                                       to sunset, the weather feed's times, else 7 to 19 o'clock)
  apply.py --follow-sun                with auto: render again when the sun has risen or set since

Template tokens: @primary@ -> #rrggbb, @primary+88@ -> #rrggbb88 (alpha suffix),
@primary:0.45@ -> rgba(r, g, b, 0.45), @primary~@ -> #ffrrggbb (Qt ARGB),
@primary_hex@ -> rrggbb, @primary_rgba+ee@ -> rgba(rrggbbee) (Hyprland), @home@ -> your home.
Names: every colour of scheme.py (fg, bg, dim, line, red, ..., primary, secondary, primary_dim)
in the look that is on; @scheme@ -> dark|light, @gtk_theme@, @qt_style@, @shadow_alpha@, @terminal_opacity@ (first, so
@shadow:@shadow_alpha@@ works).
The login screen and the fallback lock screen stay dark in both looks (night, like the greeter).

Everything written here is per machine and not in the repository (.gitignore): the wallpaper
~/.config/wall.png, the rendered configs, the round avatar from ~/.face and the login screen files in
~/.cache/theme (set-wallpaper.sh installs those as root; the shell's lock screen shows the same image).
The shell (bar, notifications, lock screen, power menu) reads colors.json itself and follows it live.
"""

import datetime
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import scheme  # noqa: E402

HOME = Path.home()
CONFIG = HOME / ".config"
THEME = CONFIG / "theme"
TEMPLATES = HERE / "templates"
DEFAULT = {"primary": "#33ccff", "secondary": "#00ff99"}
STATE = Path(os.environ.get("XDG_STATE_HOME") or HOME / ".local" / "state") / "theme"
APPEARANCE = STATE / "appearance"  # dark | light | auto, per machine
SUN = HOME / ".cache" / "theme" / "sun.json"  # {"sunrise": "07:24", "sunset": "18:55"}, weather.py

# template (in theme/templates/) -> destination (relative to ~/.config); NIGHT ones are always dark
TARGETS = {
    "colors.css": "theme/colors.css",
    "colors.lua": "theme/colors.lua",
    "ghostty-colors": "theme/ghostty-colors",
    "hyprlock.conf": "hypr/hyprlock.conf",
    "starship.toml": "starship.toml",
    "qt6ct-colors.conf": "qt6ct/colors/driftless.conf",
    "qt6ct.conf": "qt6ct/qt6ct.conf",
    "walker.css": "walker/themes/driftless/style.css",
    "walker-wallpapers.css": "walker/themes/driftless-wallpapers/style.css",
    "gtk3.css": "gtk-3.0/gtk.css",
    "gtk4.css": "gtk-4.0/gtk.css",
    "btop.theme": "btop/themes/driftless.theme",
}
NIGHT = {"hyprlock.conf"}
PREVIEW = ("glass", "bg", "bg_alt", "fg", "dim", "line", "overlay", "primary", "secondary")


def appearance():
    """The chosen look: dark, light or auto."""
    try:
        chosen = APPEARANCE.read_text().strip()
    except OSError:
        return "dark"
    return chosen if chosen in ("dark", "light", "auto") else "dark"


def sun_is_up(now=None):
    """Between today's sunrise and sunset (weather.py notes them), else between 7 and 19 o'clock."""
    now = now or datetime.datetime.now()
    rise, down = datetime.time(7), datetime.time(19)
    try:
        sun = json.loads(SUN.read_text())
        rise, down = (datetime.time.fromisoformat(sun[key]) for key in ("sunrise", "sunset"))
    except (OSError, ValueError, KeyError, TypeError):
        pass
    return rise <= now.time() < down


def look(chosen=None):
    """The look to render now: dark or light."""
    chosen = chosen or appearance()
    if chosen == "auto":
        return "light" if sun_is_up() else "dark"
    return chosen


STRINGS = {
    "dark": {
        "scheme": "dark",
        "gtk_theme": "adw-gtk3-dark",
        "qt_style": "Adwaita-Dark",
        "shadow_alpha": "0.45",
        "terminal_opacity": "0.94",
    },
    "light": {
        "scheme": "light",
        "gtk_theme": "adw-gtk3",
        "qt_style": "Adwaita",
        "shadow_alpha": "0.16",
        "terminal_opacity": "0.975",
    },
}


def token_pattern(names):
    alternatives = "|".join(sorted(names, key=len, reverse=True))
    return re.compile(rf"@({alternatives})(_hex|_rgba)?(?:(\+[0-9a-f]{{2}})|:([0-9.]+)|(~))?@")


def render(text, rgb_colors, name="dark"):
    text = text.replace("@home@", str(HOME))
    for key, value in STRINGS[name].items():
        text = text.replace(f"@{key}@", value)

    def replace(match):
        r, g, b = rgb_colors[match.group(1)]
        hex_rgb = f"{r:02x}{g:02x}{b:02x}"
        kind, plus, alpha, argb = match.group(2), match.group(3), match.group(4), match.group(5)
        if alpha:
            return f"rgba({r}, {g}, {b}, {alpha})"
        if argb:
            return "#ff" + hex_rgb
        if kind == "_hex":
            return hex_rgb
        if kind == "_rgba":
            return f"rgba({hex_rgb}{(plus or '+ff')[1:]})"
        return "#" + hex_rgb + (plus[1:] if plus else "")

    return token_pattern(rgb_colors).sub(replace, text)


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


def make_avatar(rgb_colors):
    """Round avatar from ~/.face for the bar (THEME/avatar.png) and the login screen (cache).
    Without ~/.face: the first letter of the login name on the primary colour."""
    from PIL import Image, ImageDraw, ImageFont

    size, big = 256, 1024
    face = HOME / ".face"
    if face.exists():
        image = Image.open(face).convert("RGB")
        side = min(image.size)
        image = image.crop(
            (
                (image.width - side) // 2,
                (image.height - side) // 2,
                (image.width + side) // 2,
                (image.height + side) // 2,
            )
        )
        image = image.resize((size, size), Image.LANCZOS)
    else:
        image = Image.new("RGB", (size, size), rgb_colors["primary_dim"])
        letter = (os.environ.get("USER") or "?")[0].upper()
        try:
            font = ImageFont.truetype("/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Bold.ttf", 140)
        except OSError:
            font = ImageFont.load_default(140)
        ImageDraw.Draw(image).text((size / 2, size / 2), letter, font=font, fill=rgb_colors["primary"], anchor="mm")
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, big - 1, big - 1), fill=255)
    image.putalpha(mask.resize((size, size), Image.LANCZOS))
    for dest in (THEME / "avatar.png", HOME / ".cache" / "theme" / "avatar.png"):
        dest.parent.mkdir(parents=True, exist_ok=True)
        image.save(dest.with_name(dest.name + ".tmp"), "PNG")
        os.replace(dest.with_name(dest.name + ".tmp"), dest)


def make_login_image(src):
    """Login and lock screen background (the greeter, the shell's lock screen and the hyprlock fallback
    look alike): blurred, brightness 0.45, contrast 0.9."""
    from PIL import Image, ImageFilter, ImageOps

    # crop/scale to the screen first (like the wallpaper, awww "crop"): hyprlock blurs at screen resolution,
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


def btop_use_theme():
    """btop rewrites btop.conf itself, so only the two theme keys are set (a fresh file is fine:
    btop fills in the rest). No theme background: the terminal's blur shows through."""
    conf = CONFIG / "btop" / "btop.conf"
    wanted = {"color_theme": '"driftless"', "theme_background": "False"}
    lines = conf.read_text().splitlines() if conf.exists() else []
    for key, value in wanted.items():
        line = f"{key} = {value}"
        index = next((i for i, old in enumerate(lines) if old.split("=")[0].strip() == key), None)
        if index is None:
            lines.append(line)
        else:
            lines[index] = line
    write(conf, "\n".join(lines) + "\n")


VSCODE_THEMES = Path("/usr/share/code/resources/app/extensions/theme-defaults/themes")
VSCODE_MANIFEST = """<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
 <Metadata>
  <Identity Language="en-US" Id="theme" Version="1.0.0" Publisher="driftless"/>
  <DisplayName>driftless</DisplayName>
  <Description xml:space="preserve">2026 Dark or Light with the wallpaper accents (theme/apply.py)</Description>
  <Categories>Themes</Categories>
  <Properties><Property Id="Microsoft.VisualStudio.Code.Engine" Value="^1.80.0"/></Properties>
 </Metadata>
 <Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation>
 <Dependencies/>
 <Assets><Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/></Assets>
</PackageManifest>
"""
VSCODE_TYPES = """<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
 <Default Extension=".json" ContentType="application/json"/>
 <Default Extension=".vsixmanifest" ContentType="text/xml"/>
</Types>
"""


def vscode_theme(rgb_colors, name):
    """VS Code theme "driftless": packed as a .vsix next to VS Code's own theme files (it includes
    2026 Dark) and installed in the background; VS Code only picks up registered extensions.
    Open windows show the new colours after a reload. Skipped without VS Code."""
    import shutil
    import zipfile

    code = shutil.which("code")
    if not code or not VSCODE_THEMES.is_dir():
        return
    package = {
        "name": "theme",
        "publisher": "driftless",
        "displayName": "driftless",
        "version": "1.0.0",
        "engines": {"vscode": "^1.80.0"},
        "categories": ["Themes"],
        "contributes": {
            "themes": [
                {
                    "id": "driftless",
                    "label": "driftless",
                    "uiTheme": "vs" if name == "light" else "vs-dark",
                    "path": "./themes/driftless.json",
                }
            ]
        },
    }
    vsix = HOME / ".cache" / "theme" / "driftless-vscode.vsix"
    vsix.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(vsix.with_name(vsix.name + ".tmp"), "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("[Content_Types].xml", VSCODE_TYPES)
        archive.writestr("extension.vsixmanifest", VSCODE_MANIFEST)
        archive.writestr("extension/package.json", json.dumps(package, indent=1))
        for base in VSCODE_THEMES.glob("*.json"):
            archive.write(base, "extension/themes/" + base.name)
        theme = render((TEMPLATES / "vscode-theme.json").read_text(), rgb_colors, name)
        archive.writestr("extension/themes/driftless.json", theme)
    os.replace(vsix.with_name(vsix.name + ".tmp"), vsix)
    subprocess.Popen(
        [code, "--install-extension", str(vsix), "--force"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def write(dest, text):
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_name(dest.name + ".tmp")
    tmp.write_text(text)
    if dest.exists():
        os.chmod(tmp, dest.stat().st_mode & 0o777)
    os.replace(tmp, dest)


def ensure_wall():
    """~/.config/wall.png; a fresh machine starts with the kit's default wallpaper."""
    wall = CONFIG / "wall.png"
    if not wall.exists():
        from PIL import Image

        Image.open(THEME / "default-wallpaper.jpg").convert("RGB").save(wall, "PNG")
    return wall


def palette_of(image):
    return json.loads(subprocess.check_output([sys.executable, str(HERE / "palette.py"), str(image)]))


def stored_palette():
    """The accents as palette.py made them (for the dark base): colors.json keeps them under
    "accents"; older files had only primary and secondary."""
    current = THEME / "colors.json"
    if not current.exists():
        return palette_of(ensure_wall())
    stored = json.loads(current.read_text())
    return (stored.get("accents") or stored) | {"source": stored.get("source", "default")}


def gtk_look(name):
    """GTK 3 by its theme, GTK 4, libadwaita, Electron and the portal by the colour scheme."""
    wanted = {
        "color-scheme": "prefer-light" if name == "light" else "prefer-dark",
        "gtk-theme": STRINGS[name]["gtk_theme"],
    }
    for key, value in wanted.items():
        subprocess.run(
            ["gsettings", "set", "org.gnome.desktop.interface", key, value],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )


def reload_programs():
    """What does not follow the files by itself: Hyprland's borders and shadow, the terminals."""
    for command in (["hyprctl", "reload"], ["pkill", "-USR2", "-x", "ghostty"]):
        subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)


def render_all(palette, name, login=True):
    """Render every target in the look `name`; `login`: the login screen's image as well."""
    accents = {key: palette[key] for key in ("primary", "secondary")}
    rgb_colors = scheme.scheme(name, accents)
    night_colors = scheme.scheme("dark", accents)
    write(
        THEME / "colors.json",
        json.dumps(
            {
                "primary": scheme.to_hex(rgb_colors["primary"]),
                "secondary": scheme.to_hex(rgb_colors["secondary"]),
                "source": palette.get("source", "default"),
                "appearance": appearance(),
                "scheme": name,
                "accents": accents,
                "colors": scheme.describe(rgb_colors),
                # both looks in brief, for the previews in the settings
                "looks": {
                    look_name: {key: scheme.to_hex(colors[key]) for key in PREVIEW}
                    for look_name, colors in (("dark", night_colors), ("light", scheme.scheme("light", accents)))
                },
            },
            indent=1,
        )
        + "\n",
    )
    for template, dest in TARGETS.items():
        night = template in NIGHT
        text = (TEMPLATES / template).read_text()
        write(CONFIG / dest, render(text, night_colors if night else rgb_colors, "dark" if night else name))
    gtk_look(name)
    btop_use_theme()
    vscode_theme(rgb_colors, name)
    make_avatar(rgb_colors)
    # login screen (root-owned): rendered here, installed by set-wallpaper.sh; always the dark look
    cache = HOME / ".cache" / "theme"
    cache.mkdir(parents=True, exist_ok=True)
    write(cache / "colors.json", json.dumps(accents | {"source": palette.get("source", "default")}, indent=1) + "\n")
    write(cache / "regreet.css", render((TEMPLATES / "regreet.css").read_text(), night_colors))
    if login:
        make_login_image(ensure_wall())
    print(f"primary {accents['primary']}  secondary {accents['secondary']}  ({palette.get('source')}, {name})")


def current_scheme():
    try:
        return json.loads((THEME / "colors.json").read_text()).get("scheme", "dark")
    except (OSError, ValueError):
        return "dark"


def main(argv):
    if argv and argv[0] == "--appearance":
        if len(argv) < 2 or argv[1] not in ("dark", "light", "auto"):
            sys.exit("usage: apply.py --appearance dark|light|auto")
        STATE.mkdir(parents=True, exist_ok=True)
        write(APPEARANCE, argv[1] + "\n")
        render_all(stored_palette(), look(argv[1]), login=False)
        reload_programs()
        return
    if argv and argv[0] == "--follow-sun":
        if appearance() == "auto" and look() != current_scheme():
            render_all(stored_palette(), look(), login=False)
            reload_programs()
        return
    if argv and argv[0] == "--default":
        palette = dict(DEFAULT)
    elif argv and argv[0] == "--current":
        palette = stored_palette()
    elif argv:
        palette = palette_of(argv[0])
    else:
        sys.exit(__doc__)
    render_all(palette, look())


if __name__ == "__main__":
    main(sys.argv[1:])
