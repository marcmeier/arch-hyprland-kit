#!/usr/bin/env python3
"""Widget manager for waybar: show/hide widgets and move them along the bar, in walker menus.
Changes go to ~/.local/state/waybar/layout.json, per machine (bar_layout.py); density-watch.py sees
the file change and restarts the bar.
The spacious and compact bar keep their own order, hidden widgets are hidden on both.
Opened with SUPER + SHIFT + B or from the settings menu (click on the avatar, settings-menu.sh).
Usage: widgets.py [spacious|compact]  (default: the variant of the focused monitor)"""

import json
import subprocess
import sys

from bar_layout import SECTIONS, load_layout, ordered, save_layout, variant_config

THRESHOLD = 2560  # same as density-watch.py
SECTION_NAMES = {"modules-left": "Left", "modules-center": "Center", "modules-right": "Right"}
NAMES = {
    "group/user": "User",
    "group/workspaces": "Workspaces",
    "custom/window": "Active window",
    "group/datetime": "Clock & calendar",
    "clock": "Clock",
    "custom/calendar": "Next event",
    "custom/weather": "Weather",
    "group/media": "Media",
    "tray": "Tray",
    "group/audio": "Audio",
    "pulseaudio": "Volume",
    "pulseaudio#mic": "Microphone",
    "custom/claude": "Claude usage",
    "battery": "Battery",
    "network": "Network",
    "group/upkeep": "Updates & sync",
    "custom/updates": "Updates",
    "custom/sync": "Kit sync",
    "group/actions": "Idle & notifications",
    "idle_inhibitor": "Idle inhibitor",
    "custom/notifications": "Notifications",
    "group/status": "Status",
    "group/system": "System",
    "custom/power": "Power",
}
# group members that only make sense together with their group (drawn as one pill)
FIXED = {"custom/avatar", "custom/username", "custom/media-prev", "custom/media-play", "custom/media-next"}


def name(mod):
    return NAMES.get(mod) or mod.split("/")[-1].replace("-", " ").replace("#", " ").capitalize()


def focused_variant():
    try:
        mons = json.loads(subprocess.run(["hyprctl", "-j", "monitors"], capture_output=True, text=True).stdout)
        m = next(m for m in mons if m.get("focused"))
        width = (m["height"] if m.get("transform", 0) % 2 else m["width"]) / (m.get("scale") or 1)
        return "compact" if width < THRESHOLD else "spacious"
    except Exception:
        return "spacious"


def pick(items, prompt):
    """The chosen line, None when walker was closed."""
    r = subprocess.run(["walker", "--dmenu", "-p", prompt], input="\n".join(items), capture_output=True, text=True)
    choice = r.stdout.strip()
    return choice if r.returncode == 0 and choice else None


def move(order, mod, step):
    """One place left (-1) or right (+1); at the edge of a section it jumps into the next one."""
    i = next(k for k, s in enumerate(SECTIONS) if mod in order[s])
    mods = order[SECTIONS[i]]
    j = mods.index(mod)
    if 0 <= j + step < len(mods):
        mods[j], mods[j + step] = mods[j + step], mods[j]
    elif 0 <= i + step < len(SECTIONS):
        mods.remove(mod)
        target = order[SECTIONS[i + step]]
        target.insert(len(target) if step < 0 else 0, mod)


def widget_menu(variant, mod):
    while True:
        layout = load_layout()
        order = ordered(variant_config(variant), variant, layout)
        hidden = mod in layout["hidden"]
        section = next(s for s in SECTIONS if mod in order[s])
        actions = {
            f"{'󰈈  Show' if hidden else '󰈉  Hide'}": "toggle",
            "󰁍  Move left": "left",
            "󰁔  Move right": "right",
        }
        for s in SECTIONS:
            if s != section:
                actions[f"󰁜  To the {SECTION_NAMES[s].lower()} section"] = s
        actions["󰌍  Back"] = "back"
        pos = order[section].index(mod) + 1
        choice = pick(list(actions), f"{name(mod)} ({SECTION_NAMES[section].lower()}, place {pos})")
        action = actions.get(choice)
        if action in (None, "back"):
            return
        if action == "toggle":
            toggle(mod)
            continue
        if action in ("left", "right"):
            move(order, mod, -1 if action == "left" else 1)
        else:
            order[section].remove(mod)
            order[action].append(mod)
        layout["order"][variant] = order
        save_layout(layout)


def toggle(mod):
    layout = load_layout()
    hidden = layout["hidden"]
    if mod in hidden:
        hidden.remove(mod)
    else:
        hidden.append(mod)
    save_layout(layout)


def main():
    variant = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] in ("spacious", "compact") else focused_variant()
    other = "compact" if variant == "spacious" else "spacious"
    while True:
        cfg = variant_config(variant)
        layout = load_layout()
        hidden = set(layout["hidden"])
        order = ordered(cfg, variant, layout)
        items = {}  # menu line -> (kind, widget)
        for s in SECTIONS:
            items[f"──  {SECTION_NAMES[s]}  ──"] = ("none", None)
            for mod in order[s]:
                items[f"{'○' if mod in hidden else '●'}  {name(mod)}"] = ("widget", mod)
                # members of a group can only be switched on/off, they move with their group
                for sub in cfg.get(mod, {}).get("modules", []) if mod.startswith("group/") else []:
                    if sub not in FIXED:
                        items[f"      {'○' if sub in hidden else '●'}  {name(sub)}  ({name(mod)})"] = ("toggle", sub)
        items[f"󰕮  Edit the {other} bar instead"] = ("variant", None)
        items["󰑓  Reset: default order, show everything"] = ("reset", None)
        choice = pick(list(items), f"Waybar widgets ({variant} bar)")
        if choice is None:
            return
        kind, mod = items.get(choice, ("none", None))
        if kind == "widget":
            widget_menu(variant, mod)
        elif kind == "toggle":
            toggle(mod)
        elif kind == "variant":
            variant, other = other, variant
        elif kind == "reset":
            save_layout({"hidden": [], "order": {}})


if __name__ == "__main__":
    main()
