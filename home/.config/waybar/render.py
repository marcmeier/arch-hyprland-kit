#!/usr/bin/env python3
"""Waybar config for this machine, rendered to ~/.cache/waybar/config.jsonc before waybar starts
(ExecStartPre of waybar.service, see ~/.config/systemd/user/waybar.service.d/driftless.conf).

Two bars, and waybar itself puts them on the right monitors, also when one is plugged in later:
  compact   on the narrow outputs: config-compact.jsonc merged over config.jsonc
  spacious  on every other output: config.jsonc as written
The narrow outputs are ["eDP-1", "eDP-2"] (notebook panels) unless ~/.config/driftless/host/waybar.json
names others by connector or description: {"compact": ["eDP-1", "Vendor Model Serial"]}.
The bar's name ("compact"/"spacious") is its CSS class, which style-compact.css keys on.
The bar size in the settings menu overrides this per machine: "spacious" or "compact" puts that one bar
on every output ("mode" in layout.json; set with render.py --mode, read with render.py --get-mode).
Last, this machine's widget layout (~/.local/state/waybar/layout.json, widgets.py) is applied."""

import json
import os
import sys

from bar_layout import MODES, OUT, apply, bar_mode, compact_outputs, load_layout, save_layout, variant_config


def bar(variant, layout, output):
    cfg = apply(variant_config(variant), variant, layout)
    cfg.update(name=variant, output=output)
    return cfg


def render():
    layout = load_layout()
    mode = bar_mode(layout)
    if mode == "auto":
        narrow = compact_outputs()
        bars = [bar("compact", layout, narrow), bar("spacious", layout, [f"!{o}" for o in narrow] + ["*"])]
    else:
        bars = [bar(mode, layout, ["*"])]
    text = json.dumps(bars, indent=2, ensure_ascii=False)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT + ".tmp", "w") as f:
        f.write(text)
    os.replace(OUT + ".tmp", OUT)


if __name__ == "__main__":
    if sys.argv[1:2] == ["--get-mode"]:
        print(bar_mode(load_layout()))
    elif sys.argv[1:2] == ["--mode"] and sys.argv[2:3] and sys.argv[2] in MODES:
        layout = load_layout()
        layout["mode"] = sys.argv[2]
        save_layout(layout)
    elif sys.argv[1:]:
        sys.exit(f"usage: {sys.argv[0]} [--get-mode | --mode {'|'.join(MODES)}]")
    else:
        render()
