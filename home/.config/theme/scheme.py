"""The two looks of the desktop: dark and light, as named colours for the templates and the shell.

Dark is the kit's fixed palette (unchanged since the first version). Light is drawn here: paper
instead of white, slate instead of black, and every grey carries a trace of the wallpaper's primary
hue, so the light surfaces belong to the image the way the dark ones do. Its accents keep the hue of
the wallpaper's but are deeper, so they stand on paper as the vivid ones stand on the dark base
(contrast checked). Colours are worked out in OKLCH: steps in lightness look even, and a hue keeps
its character when it gets darker.

Names (every template can use them, see apply.py):
  bg          window and terminal background      bg_alt     raised: popovers, cards, menus
  bg_high     buttons, wells                       bg_sunken  deepest shade (dark) / bevel (light)
  line        borders, separators                  line_strong a border that shows
  faint       barely there (disabled, captions)    muted      hints, comments
  dim         secondary text                       fg         text
  fg_strong   the brightest text (headlines)       ink        text on an accent
  overlay     what translucent overlays are made of (white on dark, slate on light)
  shadow      drop shadows
  red orange yellow green blue purple cyan (+ _bright): status colours and the terminal's palette
  bevel_light bevel_midlight bevel_mid bevel_dark: Qt's 3D roles
  field       where you type and lists             window     behind them
  selection   selected text                        glass      translucent surfaces (with alpha)
  primary secondary (+ _dim: a quiet tint of it over bg, + on_dim: text on that tint)
"""

import math

# ---- colour science: sRGB <-> OKLab / OKLCH (Björn Ottosson) ----


def _linear(channel):
    channel /= 255
    return channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4


def _gamma(channel):
    channel = channel * 12.92 if channel <= 0.0031308 else 1.055 * channel ** (1 / 2.4) - 0.055
    return channel * 255


def to_oklch(rgb):
    r, g, b = (_linear(c) for c in rgb)
    l_ = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m_ = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s_ = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    lightness = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
    a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
    b_ = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    return lightness, math.hypot(a, b_), math.degrees(math.atan2(b_, a)) % 360


def _oklch_raw(lightness, chroma, hue):
    a, b = chroma * math.cos(math.radians(hue)), chroma * math.sin(math.radians(hue))
    l_ = (lightness + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m_ = (lightness - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s_ = (lightness - 0.0894841775 * a - 1.2914855480 * b) ** 3
    return (
        4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_,
        -1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_,
        -0.0041960863 * l_ - 0.7034186147 * m_ + 1.7076147010 * s_,
    )


def oklch(lightness, chroma, hue):
    """8-bit sRGB of an OKLCH colour; chroma is reduced until it fits into sRGB (the hue stays)."""
    for _ in range(40):
        linear = _oklch_raw(lightness, chroma, hue)
        if all(-0.0005 <= c <= 1.0005 for c in linear):
            break
        chroma *= 0.93
    return tuple(round(min(255, max(0, _gamma(min(1, max(0, c)))))) for c in linear)


def luminance(rgb):
    """Relative luminance (WCAG)."""
    r, g, b = (_linear(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    lum_a, lum_b = luminance(a), luminance(b)
    return (max(lum_a, lum_b) + 0.05) / (min(lum_a, lum_b) + 0.05)


def mix(a, b, f):
    """f of b over a."""
    return tuple(round(x + (y - x) * f) for x, y in zip(a, b, strict=True))


def rgb(hex_color):
    digits = hex_color.lstrip("#")
    return tuple(int(digits[i : i + 2], 16) for i in (0, 2, 4))


def to_hex(color):
    return "#{:02x}{:02x}{:02x}".format(*color)


# ---- dark: the kit's palette ----

DARK = {
    "bg": "#14161c",
    "bg_alt": "#1a1d24",
    "bg_high": "#22262f",
    "bg_sunken": "#0f1116",
    "line": "#2a2e38",
    "line_strong": "#3a3f4b",
    "faint": "#4b5263",
    "muted": "#6b7280",
    "dim": "#8b93a1",
    "fg": "#d7dce2",
    "fg_strong": "#ffffff",
    "ink": "#0b0d10",
    "overlay": "#ffffff",
    "shadow": "#000000",
    "black": "#1c1f26",
    "white": "#d7dce2",
    "bright_black": "#4b5263",
    "bright_white": "#ffffff",
    "red": "#ff5f6d",
    "red_bright": "#ff7a85",
    "orange": "#ffb454",
    "yellow": "#ffb454",
    "yellow_bright": "#ffcc80",
    "green": "#3ddc97",
    "blue": "#5aa9ff",
    "blue_bright": "#7fc4ff",
    "purple": "#c792ea",
    "purple_bright": "#d7a8ff",
    "cyan": "#7fdbca",
    "cyan_bright": "#7fdbca",
    "bevel_light": "#3a3f4b",
    "bevel_midlight": "#2c303a",
    "bevel_mid": "#2a2e38",
    "bevel_dark": "#0f1116",
    "field": "#14161c",
    "window": "#1a1d24",
    "selection": "#2a3a48",
    "glass": "#14161c",
}

# the vivid accents are made for this base (palette.py: contrast >= 7 against it)
DARK_BASE = rgb(DARK["bg"])


# ---- light: paper, slate, and the wallpaper's hue in every grey ----

# (lightness, chroma) of the greys; the hue is the primary accent's
LIGHT_GREYS = {
    "bg": (0.966, 0.007),
    "bg_alt": (0.988, 0.004),
    "bg_high": (0.932, 0.010),
    "bg_sunken": (0.905, 0.012),
    "line": (0.885, 0.013),
    "line_strong": (0.80, 0.016),
    "faint": (0.70, 0.018),
    "muted": (0.585, 0.022),
    "dim": (0.505, 0.024),
    "fg": (0.305, 0.026),
    "fg_strong": (0.205, 0.030),
    "overlay": (0.255, 0.030),
    "shadow": (0.22, 0.035),
    "black": (0.305, 0.026),
    "white": (0.585, 0.022),
    "bright_black": (0.505, 0.024),
    "bright_white": (0.70, 0.018),
    "bevel_light": (1.0, 0.0),
    "bevel_midlight": (0.955, 0.008),
    "bevel_mid": (0.80, 0.016),
    "bevel_dark": (0.66, 0.020),
}

# status colours on paper: (lightness, chroma, hue), deep enough to read, never neon
LIGHT_HUES = {
    "red": (0.565, 0.185, 20),
    "red_bright": (0.62, 0.180, 20),
    "orange": (0.600, 0.150, 55),
    "yellow": (0.620, 0.130, 80),
    "yellow_bright": (0.680, 0.135, 82),
    "green": (0.560, 0.135, 155),
    "blue": (0.545, 0.165, 258),
    "blue_bright": (0.610, 0.160, 258),
    "purple": (0.540, 0.180, 305),
    "purple_bright": (0.600, 0.170, 305),
    "cyan": (0.575, 0.100, 200),
    "cyan_bright": (0.640, 0.100, 200),
}

LIGHT_ACCENT_CONTRAST = 4.2  # against bg_alt: small text in an accent stays readable


def light_accent(color, paper):
    """The light scheme's version of a (vivid) accent: same hue, as much colour as it keeps, dark
    enough to stand on paper."""
    _, chroma, hue = to_oklch(color)
    if chroma < 0.03:  # a grey accent stays grey
        chroma = 0.0
    chroma = min(max(chroma * 0.95, 0.11 if chroma else 0.0), 0.20)
    lightness = 0.74
    result = oklch(lightness, chroma, hue)
    while contrast(result, paper) < LIGHT_ACCENT_CONTRAST and lightness > 0.3:
        lightness -= 0.005
        result = oklch(lightness, chroma, hue)
    return result


def light_scheme(primary):
    """The named colours of the light look, tinted with the hue of `primary` (the dark accent)."""
    _, chroma, hue = to_oklch(primary)
    tint = 1.0 if chroma >= 0.03 else 0.0  # a grey wallpaper: neutral greys
    colors = {name: oklch(lightness, c * tint, hue) for name, (lightness, c) in LIGHT_GREYS.items()}
    colors |= {name: oklch(*lch) for name, lch in LIGHT_HUES.items()}
    colors["ink"] = (255, 255, 255)
    # on paper the fields are the brightest thing (in the dark look they are the deepest)
    colors["field"], colors["window"] = colors["bg_alt"], colors["bg"]
    colors["glass"] = colors["bg_alt"]
    return colors


# ---- both ----


def scheme(name, palette):
    """RGB tuples for every name of the look `name` ("dark" or "light") with the wallpaper's
    accents (`palette`: primary and secondary as made for the dark base, from palette.py)."""
    primary, secondary = rgb(palette["primary"]), rgb(palette["secondary"])
    if name == "light":
        colors = light_scheme(primary)
        colors["primary"] = light_accent(primary, colors["bg_alt"])
        colors["secondary"] = light_accent(secondary, colors["bg_alt"])
        dim_share, colors["on_dim"] = 0.20, colors["fg_strong"]
        colors["selection"] = mix(colors["bg"], colors["primary"], 0.22)
    else:
        colors = {key: rgb(value) for key, value in DARK.items()}
        colors["primary"], colors["secondary"] = primary, secondary
        dim_share, colors["on_dim"] = 0.33, colors["fg_strong"]
    for accent in ("primary", "secondary"):
        colors[accent + "_dim"] = mix(colors["bg"], colors[accent], dim_share)
    return colors


def describe(colors):
    """Hex strings, for colors.json."""
    return {key: to_hex(value) for key, value in colors.items()}
