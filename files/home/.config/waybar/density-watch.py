#!/usr/bin/env python3
"""Waybar: one bar per monitor, spacious on wide monitors and compact on narrow ones (logical px).
Renders ~/.cache/waybar/{config.jsonc,style.css} from config.jsonc + style.css; bars on narrow
monitors get config-compact.jsonc merged in and are named "compact", which style-compact.css
(scoped to window#waybar.compact) keys on. Re-renders on Hyprland monitor
events (socket2, like window.py) and when a source file is edited; a new style is picked up by
waybar itself (reload_style_on_change), a new config restarts waybar via launch.sh (SIGUSR2
reload is unreliable). SIGUSR1 forces a re-render (hypr/display-mode.sh). --once renders and
exits (launch.sh runs it before starting waybar). ~/.local/state/waybar/layout.json (widget manager,
widgets.py, per machine) is applied last: widget order and hidden widgets."""

import json
import os
import re
import select
import signal
import socket
import subprocess
import sys
import time

from bar_layout import LAYOUT, apply, load_jsonc, load_layout, merge, prune

SRC_DIR = os.path.expanduser("~/.config/waybar")
OUT_DIR = os.path.expanduser("~/.cache/waybar")
SOURCES = ["config.jsonc", "style.css", "config-compact.jsonc", "style-compact.css"]
THRESHOLD = 2560
EVENTS = ("monitoradded", "monitoraddedv2", "monitorremoved", "monitorremovedv2", "configreloaded")

# the effective style.css lives in ~/.cache, so relative url()s must point back to ~/.config/waybar
REL_URL = re.compile(r'url\("(?![a-z]+:|/)([^"]+)"\)')


def monitors():
    """(name, logical width) of every monitor that shows its own content; None if hyprctl fails."""
    try:
        mons = json.loads(subprocess.run(["hyprctl", "-j", "monitors"], capture_output=True, text=True).stdout or "[]")
    except Exception:
        return None
    return [
        (m["name"], (m["height"] if m.get("transform", 0) % 2 else m["width"]) / (m.get("scale") or 1))
        for m in mons
        if not m.get("disabled") and m.get("mirrorOf", "none") == "none"
    ]


SELECTOR = re.compile(r"([^{};]+)\{")


def scope(css, cls):
    """Prefix every rule of css with window#waybar.<cls>, so it only applies to bars with that name."""
    css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)

    def fix(m):
        if m.group(1).strip().startswith("@"):
            return m.group(0)
        lead = m.group(1)[: len(m.group(1)) - len(m.group(1).lstrip())]
        sels = [s.strip() for s in m.group(1).split(",")]
        return (
            lead
            + ", ".join(
                s.replace("window#waybar", f"window#waybar.{cls}", 1)
                if s.startswith("window#waybar")
                else f"window#waybar.{cls} {s}"
                for s in sels
            )
            + " {"
        )

    return SELECTOR.sub(fix, css)


def write(path, text):
    try:
        if open(path).read() == text:
            return False
    except OSError:
        pass
    os.makedirs(OUT_DIR, exist_ok=True)
    tmp = f"{path}.{os.getpid()}.tmp"
    open(tmp, "w").write(text)
    os.replace(tmp, path)
    return True


def render():
    base = load_jsonc(f"{SRC_DIR}/config.jsonc")
    compact = load_jsonc(f"{SRC_DIR}/config-compact.jsonc")
    layout = load_layout()  # widget manager: order and hidden widgets (widgets.py)
    mons = monitors()
    if not mons:  # unknown layout: one plain bar on every output
        bars = apply(base, "spacious", layout)
    else:
        bars = []
        for name, width in mons:
            bar = json.loads(json.dumps(base))
            if width < THRESHOLD:
                bar = prune(merge(bar, json.loads(json.dumps(compact))))
            variant = "compact" if width < THRESHOLD else "spacious"
            bar = apply(bar, variant, layout)
            bar.update(output=name, name=variant)
            bars.append(bar)
    css = open(f"{SRC_DIR}/style.css").read() + "\n" + scope(open(f"{SRC_DIR}/style-compact.css").read(), "compact")
    css = REL_URL.sub(lambda m: f'url("file://{SRC_DIR}/{m.group(1)}")', css)
    write(f"{OUT_DIR}/style.css", css)
    return write(f"{OUT_DIR}/config.jsonc", json.dumps(bars, indent=2))


if "--once" in sys.argv:
    render()
    sys.exit(0)


def safe_render():
    try:
        return render()
    except Exception as e:  # e.g. a half-edited config.jsonc: keep the last good bar
        print(f"density-watch: {e}", file=sys.stderr, flush=True)
        return False


def mtimes():
    paths = [f"{SRC_DIR}/{f}" for f in SOURCES] + [LAYOUT]
    return [os.path.getmtime(p) if os.path.exists(p) else 0 for p in paths]


poked = False


def poke(*_):
    global poked
    poked = True


signal.signal(signal.SIGUSR1, poke)
os.makedirs(OUT_DIR, exist_ok=True)
open(f"{OUT_DIR}/density-watch.pid", "w").write(str(os.getpid()))

safe_render()
seen = mtimes()
sock = socket.socket(socket.AF_UNIX)
sock.connect(f"{os.environ['XDG_RUNTIME_DIR']}/hypr/{os.environ['HYPRLAND_INSTANCE_SIGNATURE']}/.socket2.sock")
buf = b""
while True:
    ready, _, _ = select.select([sock], [], [], 2)
    changed = False
    if ready:
        chunk = sock.recv(4096)
        if not chunk:
            break
        buf += chunk
        *lines, buf = buf.split(b"\n")
        if any(raw.decode(errors="replace").partition(">>")[0] in EVENTS for raw in lines):
            time.sleep(0.5)  # let Hyprland settle mode/scale of the new monitor
            changed = True
    if poked:
        poked, changed = False, True
    now = mtimes()
    if now != seen:
        seen, changed = now, True
    if changed and safe_render() and subprocess.run(["pgrep", "-x", "waybar"], capture_output=True).returncode == 0:
        subprocess.run(["pkill", "-x", "waybar"])
        time.sleep(0.3)
        subprocess.Popen(
            [f"{SRC_DIR}/launch.sh"], start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
