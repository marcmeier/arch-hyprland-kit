#!/usr/bin/env python3
"""The bar's widget layout, for widgets.py (the widget manager) and the settings menu; the shell reads the
same files with the same rules (services/BarLayout.qml) and follows every change at once.

layout.json holds what the widget manager changed. It lives in ~/.local/state/driftless-shell, per machine
and outside the repository, so every machine keeps its own bar.
  {"hidden": ["custom/weather", ...],                      hidden everywhere, also inside groups
   "order": {"spacious": {"modules-left": [...], ...},     widget order per bar variant
             "compact":  {...}},
   "mode": "auto"}                                         bar size: "auto" (compact on narrow outputs),
                                                           "spacious" or "compact" on every output
bar.jsonc is the source of every widget: a widget missing from the saved order (new in bar.jsonc) goes in
right after the widget before it there (first in its section when there is none), a saved one gone from
bar.jsonc is ignored.
Usage: bar_layout.py --get-mode | --mode auto|spacious|compact   (the bar size of this machine)"""

import json
import os
import re
import subprocess
import sys

SHELL_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
STATE_DIR = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
LAYOUT = f"{STATE_DIR}/driftless-shell/layout.json"
LEGACY = f"{STATE_DIR}/waybar/layout.json"  # the Waybar days; moved over on the first read
HOST_CONFIG = os.path.expanduser("~/.config/driftless/host/bar.json")
DEFAULT_COMPACT = ["eDP-1", "eDP-2"]
SECTIONS = ("modules-left", "modules-center", "modules-right")
MODES = ("auto", "spacious", "compact")

COMMENT = re.compile(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/', re.S)
TRAILING = re.compile(r'"(?:\\.|[^"\\])*"|,(?=\s*[}\]])')


def keep_str(m):
    return m.group(0) if m.group(0).startswith('"') else ""


def load_jsonc(path):
    return json.loads(TRAILING.sub(keep_str, COMMENT.sub(keep_str, open(path).read())))


def variant_config(variant, path=None):
    """The bar of a variant ("spacious" or "compact") before the layout is applied:
    {section: [widget, ...], "group/...": {"modules": [member, ...]}}"""
    src = load_jsonc(path or f"{SHELL_DIR}/bar.jsonc")
    cfg = {s: list(src.get(s, [])) for s in SECTIONS}
    compact = src.get("compact", {}) if variant == "compact" else {}
    for group, members in src.get("groups", {}).items():
        cfg[group] = {"modules": list(compact.get(group, members))}
    return cfg


def compact_outputs(path=HOST_CONFIG):
    """Outputs (connector names or descriptions) that get the compact bar."""
    for candidate in (path, os.path.expanduser("~/.config/driftless/host/waybar.json")):
        try:
            return list(json.load(open(candidate))["compact"])
        except (OSError, ValueError, KeyError, TypeError):
            continue
    return list(DEFAULT_COMPACT)


def bar_mode(layout):
    """The saved bar size: "auto", "spacious" or "compact" (anything else counts as "auto")."""
    mode = layout.get("mode")
    return mode if mode in MODES else "auto"


def variant_for(monitor, layout, narrow):
    """The bar variant on a monitor (hyprctl's name and description) under the saved bar size."""
    mode = bar_mode(layout)
    if mode != "auto":
        return mode
    return "compact" if monitor.get("name") in narrow or monitor.get("description") in narrow else "spacious"


def load_layout(path=LAYOUT):
    if path == LAYOUT and not os.path.exists(LAYOUT) and os.path.exists(LEGACY):
        os.makedirs(os.path.dirname(LAYOUT), exist_ok=True)
        os.replace(LEGACY, LAYOUT)
    try:
        layout = json.load(open(path))
    except (OSError, ValueError):
        return {"hidden": [], "order": {}}
    layout.setdefault("hidden", [])
    layout.setdefault("order", {})
    return layout


def save_layout(layout, path=LAYOUT):
    """Write the layout and tell the shell (it reads it again at once)."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w") as f:
        json.dump(layout, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)
    if path == LAYOUT:
        subprocess.run([f"{SHELL_DIR}/scripts/poke", "layout"], check=False)


def ordered(cfg, variant, layout):
    """{section: [widget, ...]} of the variant in the saved order, hidden widgets included."""
    current = {s: list(cfg.get(s, [])) for s in SECTIONS}
    known = {m for s in SECTIONS for m in current[s]}
    saved = layout.get("order", {}).get(variant, {})
    result = {s: [m for m in saved.get(s, []) if m in known] for s in SECTIONS}
    placed = {m for s in SECTIONS for m in result[s]}
    for s in SECTIONS:
        for i, m in enumerate(current[s]):
            if m in placed:
                continue
            # next to its neighbour in the config, wherever the layout moved that one
            before = next((p for p in reversed(current[s][:i]) if p in placed), None)
            where = next((sec for sec in SECTIONS if before in result[sec]), s) if before else s
            result[where].insert(result[where].index(before) + 1 if before else 0, m)
            placed.add(m)
    return result


if __name__ == "__main__":
    if sys.argv[1:2] == ["--get-mode"]:
        print(bar_mode(load_layout()))
    elif sys.argv[1:2] == ["--mode"] and sys.argv[2:3] and sys.argv[2] in MODES:
        current = load_layout()
        current["mode"] = sys.argv[2]
        save_layout(current)
    else:
        sys.exit(f"usage: {sys.argv[0]} --get-mode | --mode {'|'.join(MODES)}")
