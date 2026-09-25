#!/usr/bin/env python3
"""Waybar config for this machine, rendered to ~/.cache/waybar/config.jsonc before waybar starts
(ExecStartPre of waybar.service, see ~/.config/systemd/user/waybar.service.d/driftless.conf).

Two bars, and waybar itself puts them on the right monitors, also when one is plugged in later:
  compact   on the narrow outputs: config-compact.jsonc merged over config.jsonc
  spacious  on every other output: config.jsonc as written
The narrow outputs are ["eDP-1", "eDP-2"] (notebook panels) unless ~/.config/driftless/host/waybar.json
names others by connector or description: {"compact": ["eDP-1", "Vendor Model Serial"]}.
The bar's name ("compact"/"spacious") is its CSS class, which style-compact.css keys on.
Last, this machine's widget layout (~/.local/state/waybar/layout.json, widgets.py) is applied."""

import json
import os

from bar_layout import OUT, apply, compact_outputs, load_layout, variant_config


def render():
    layout = load_layout()
    narrow = compact_outputs()
    spacious = apply(variant_config("spacious"), "spacious", layout)
    spacious.update(name="spacious", output=[f"!{o}" for o in narrow] + ["*"])
    compact = apply(variant_config("compact"), "compact", layout)
    compact.update(name="compact", output=narrow)
    text = json.dumps([compact, spacious], indent=2, ensure_ascii=False)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT + ".tmp", "w") as f:
        f.write(text)
    os.replace(OUT + ".tmp", OUT)


if __name__ == "__main__":
    render()
