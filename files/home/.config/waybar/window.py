#!/usr/bin/env python3
"""Waybar: active window pill. Monochrome app glyph + title, app name small and dimmed.
Streams a JSON line on Hyprland events (socket2); empty text (hidden) when no window is focused.
"compact": glyph + app name only, the title stays in the tooltip."""

import html
import json
import os
import re
import socket
import subprocess
import sys

COMPACT = "compact" in sys.argv[1:]

G = chr
# (regex on window class, glyph, display name); first match wins
APPS = [
    (r"ghostty", G(0xF018D), "Ghostty"),
    (r"brave", G(0xF059F), "Brave"),
    (r"steam", G(0xF04D3), "Steam"),
    (r"discord", G(0xF066F), "Discord"),
    (r"^(code|code-oss|vscodium)", G(0xF0A1E), "VS Code"),
    (r"lutris", G(0xF0297), "Lutris"),
    (r"battle\.net|diablo", G(0xF0297), "Battle.net"),
    (r"pwvucontrol|pavucontrol", G(0xF057E), "Volume"),
    (r"spotify", G(0xF04C7), "Spotify"),
    (r"firefox", G(0xF0239), "Firefox"),
    (r"thunar|nautilus|dolphin|pcmanfm", G(0xF024B), "Files"),
]
DEFAULT = G(0xF05B2)
TITLE_SUFFIX = re.compile(r"\s+[-—–]\s+(Brave( Origin)?|Mozilla Firefox|Discord|Visual Studio Code)$")


def app(cls):
    for rx, glyph, name in APPS:
        if re.search(rx, cls, re.I):
            return glyph, name
    name = re.split(r"[.]", cls)[-1].replace("-", " ").replace("_", " ").strip().title()
    return DEFAULT, name or "Window"


def cut(s, n):
    return s if len(s) <= n else s[: n - 1].rstrip() + "…"


def emit():
    try:
        w = json.loads(subprocess.run(["hyprctl", "-j", "activewindow"], capture_output=True, text=True).stdout or "{}")
    except Exception:
        return
    if not w or not w.get("class"):
        print(json.dumps({"text": "", "class": "none"}), flush=True)
        return
    glyph, name = app(w["class"])
    title = TITLE_SUFFIX.sub("", w.get("title", "")).strip()
    text = f"{glyph}  "
    if title and title.lower() != name.lower() and not COMPACT:
        text += html.escape(cut(title, 40))
    else:
        text += html.escape(name)
    tip = "\n".join(x for x in (w.get("title", ""), w["class"]) if x)
    print(json.dumps({"text": text, "class": "active", "tooltip": html.escape(tip)}, ensure_ascii=False), flush=True)


sock_path = (
    os.environ.get("WS_SOCKET")
    or f"{os.environ['XDG_RUNTIME_DIR']}/hypr/{os.environ['HYPRLAND_INSTANCE_SIGNATURE']}/.socket2.sock"
)
emit()
s = socket.socket(socket.AF_UNIX)
s.connect(sock_path)
buf = b""
while True:
    d = s.recv(4096)
    if not d:
        break
    buf += d
    *lines, buf = buf.split(b"\n")
    if any(
        raw.decode(errors="replace").partition(">>")[0]
        in ("activewindowv2", "windowtitlev2", "closewindow", "openwindow", "workspacev2", "movewindowv2")
        for raw in lines
    ):
        emit()
