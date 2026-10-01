#!/usr/bin/env python3
"""Every keybinding of the running Hyprland in walker, searchable as you type (the settings on the
avatar, or SUPER + SHIFT + K). Read from `hyprctl binds`, so it lists what is bound right now, the host
and personal layers included; the text is each bind's description in hyprland.lua.
Binds with the same description share one line ("SUPER + 1 … 0  →  Go to workspace 1-10").
Usage: keybinds.py [--print]  (--print: the lines on stdout instead of walker)"""

import json
import subprocess
import sys

# modmask bits, in the order they are written
MODS = [(64, "SUPER"), (4, "CTRL"), (8, "ALT"), (1, "SHIFT")]
KEYS = {
    "RETURN": "Enter",
    "SPACE": "Space",
    "PRINT": "Print",
    "period": ".",
    "comma": ",",
    "slash": "/",
    "left": "←",
    "right": "→",
    "up": "↑",
    "down": "↓",
    "mouse_down": "Scroll down",
    "mouse_up": "Scroll up",
    "mouse:272": "Left mouse",
    "mouse:273": "Right mouse",
    "mouse:274": "Middle mouse",
    "XF86AudioRaiseVolume": "Volume up key",
    "XF86AudioLowerVolume": "Volume down key",
    "XF86AudioMute": "Mute key",
    "XF86AudioMicMute": "Mic mute key",
    "XF86MonBrightnessUp": "Brightness up key",
    "XF86MonBrightnessDown": "Brightness down key",
    "XF86AudioNext": "Next key",
    "XF86AudioPrev": "Previous key",
    "XF86AudioPlay": "Play key",
    "XF86AudioPause": "Pause key",
    "XF86Display": "Display key",
}


def mods(mask):
    return [name for bit, name in MODS if mask & bit]


def key_name(key):
    return KEYS.get(key, key.upper() if len(key) == 1 else key)


def keys_text(keys):
    """Several keys with the same modifiers: 1 … 0 for the workspace row, else a / b / c."""
    if len(keys) > 4 and all(k.isdigit() for k in keys):
        return f"{keys[0]} … {keys[-1]}"
    return " / ".join(keys)


def lines(binds):
    groups = {}  # description -> {modifiers -> [keys]}, in the order of hyprland.lua
    for b in binds:
        desc = b.get("description") or ""
        if not desc and b.get("release"):
            continue  # the release half of a press/release pair (dictation)
        desc = desc or "(no description)"
        combo = groups.setdefault(desc, {}).setdefault(tuple(mods(b.get("modmask", 0))), [])
        name = key_name(b.get("key") or str(b.get("keycode")))
        if name not in combo:
            combo.append(name)
    out = []
    for desc, combos in groups.items():
        shown = [" + ".join([*m, keys_text(k)]) for m, k in combos.items()]
        out.append(f"{'  or  '.join(shown)}  →  {desc}")
    return out


def main():
    r = subprocess.run(["hyprctl", "-j", "binds"], capture_output=True, text=True, check=False)
    try:
        binds = json.loads(r.stdout)
    except ValueError:
        sys.exit("keybinds.py: hyprctl binds gave no JSON (is Hyprland running?)")
    text = "\n".join(lines(binds))
    if "--print" in sys.argv[1:]:
        print(text)
        return
    # only to look up: the chosen line does nothing
    subprocess.run(["walker", "--dmenu", "-p", "Keybindings"], input=text, text=True, capture_output=True, check=False)


if __name__ == "__main__":
    main()
