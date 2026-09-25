"""Waybar layout shared by render.py and widgets.py (the widget manager).

layout.json holds what the widget manager changed. It lives in ~/.local/state/waybar, per machine and
outside the repository, so every machine keeps its own bar.
  {"hidden": ["custom/weather", ...],                      hidden everywhere, also inside groups
   "order": {"spacious": {"modules-left": [...], ...},     widget order per bar variant
             "compact":  {...}}}
config.jsonc stays the source of every widget: a widget missing from the saved order (new in the
config) keeps its place at the end of its section, a saved one gone from the config is ignored."""

import copy
import json
import os
import re

SRC_DIR = os.path.expanduser("~/.config/waybar")
STATE_DIR = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
LAYOUT = f"{STATE_DIR}/waybar/layout.json"
OUT = os.path.expanduser("~/.cache/waybar/config.jsonc")
HOST_CONFIG = os.path.expanduser("~/.config/driftless/host/waybar.json")
DEFAULT_COMPACT = ["eDP-1", "eDP-2"]
SECTIONS = ("modules-left", "modules-center", "modules-right")

COMMENT = re.compile(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/', re.S)
TRAILING = re.compile(r'"(?:\\.|[^"\\])*"|,(?=\s*[}\]])')


def keep_str(m):
    return m.group(0) if m.group(0).startswith('"') else ""


def load_jsonc(path):
    return json.loads(TRAILING.sub(keep_str, COMMENT.sub(keep_str, open(path).read())))


def merge(base, overlay):
    for key, value in overlay.items():
        base[key] = merge(base[key], value) if isinstance(value, dict) and isinstance(base.get(key), dict) else value
    return base


def prune(cfg):
    for k, v in cfg.items():
        if k in SECTIONS:
            cfg[k] = [m for m in v if m in cfg]
        elif k.startswith("group/"):
            v["modules"] = [m for m in v.get("modules", []) if m in cfg]
    return cfg


def variant_config(variant, src_dir=SRC_DIR):
    """The bar config of a variant ("spacious" or "compact") before the layout is applied."""
    cfg = load_jsonc(f"{src_dir}/config.jsonc")
    if variant == "compact":
        cfg = prune(merge(cfg, load_jsonc(f"{src_dir}/config-compact.jsonc")))
    return cfg


def compact_outputs(path=HOST_CONFIG):
    """Outputs (names or "desc:..." descriptions) that get the compact bar."""
    try:
        return list(json.load(open(path))["compact"])
    except (OSError, ValueError, KeyError, TypeError):
        return list(DEFAULT_COMPACT)


def load_layout(path=LAYOUT):
    try:
        layout = json.load(open(path))
    except (OSError, ValueError):
        return {"hidden": [], "order": {}}
    layout.setdefault("hidden", [])
    layout.setdefault("order", {})
    return layout


def save_layout(layout, path=LAYOUT):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w") as f:
        json.dump(layout, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)


def ordered(cfg, variant, layout):
    """{section: [widget, ...]} of the variant in the saved order, hidden widgets included."""
    current = {s: list(cfg.get(s, [])) for s in SECTIONS}
    known = {m for s in SECTIONS for m in current[s]}
    saved = layout.get("order", {}).get(variant, {})
    result = {s: [m for m in saved.get(s, []) if m in known] for s in SECTIONS}
    placed = {m for s in SECTIONS for m in result[s]}
    for s in SECTIONS:
        result[s] += [m for m in current[s] if m not in placed]
    return result


def apply(cfg, variant, layout):
    """cfg with the saved order and without hidden widgets (in sections and inside groups)."""
    cfg = copy.deepcopy(cfg)
    hidden = set(layout.get("hidden", []))
    for s, mods in ordered(cfg, variant, layout).items():
        cfg[s] = [m for m in mods if m not in hidden]
    for k, v in cfg.items():
        if k.startswith("group/") and isinstance(v, dict):
            v["modules"] = [m for m in v.get("modules", []) if m not in hidden]
    return cfg
