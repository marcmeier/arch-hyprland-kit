#!/usr/bin/env python3
"""Waybar feeds: one process (driftless-bar.service) for the workspace buttons, the active window
and the media pill, instead of one Python process per button.

It follows Hyprland's event socket and playerctl, writes each module's JSON line to
$XDG_RUNTIME_DIR/driftless-bar/<name>.json and signals waybar, whose custom modules just "cat" their
file ("interval": "once" plus a signal). Signals: 12 workspaces and window, 13 media buttons,
14 the media title (it scrolls while playing, so it has its own signal).

Why custom workspace buttons at all: Waybar 0.15's hyprland/workspaces module clicks with
"dispatch workspace N", which Hyprland 0.56 (Lua config) rejects. The buttons click with
hl.dsp.focus instead (config.jsonc)."""

import html
import json
import os
import re
import signal
import socket
import subprocess
import threading
import time

LAST = 5  # buttons 1..LAST; the "more" pill covers the rest
SIG_HYPR, SIG_MEDIA, SIG_TITLE = 12, 13, 14
HYPR_EVENTS = {
    "workspacev2", "workspace", "focusedmon", "activewindowv2", "openwindow", "closewindow",
    "movewindowv2", "createworkspacev2", "destroyworkspacev2", "windowtitlev2", "urgent",
}  # fmt: skip

# ---------------------------------------------------------------- workspaces


def workspace_feeds(active, windows, clients, urgent):
    """{name: module JSON} for ws1..wsLAST and wsmore.
    active: focused workspace id · windows: {workspace id: window count} ·
    clients: {window address: workspace id} · urgent: addresses that asked for attention"""
    urgent_ws = {clients.get(a) for a in urgent}
    out = {}
    for n in range(1, LAST + 1):
        cls = ["ws"]
        if active == n:
            cls.append("active")
        if n in urgent_ws:
            cls.append("urgent")
        if not windows.get(n):
            cls.append("empty")
        out[f"ws{n}"] = {"text": str(n), "class": cls, "tooltip": ""}  # False would show as "false"
    extra = sorted(i for i, count in windows.items() if i > LAST and count)
    if active and active > LAST and active not in extra:
        extra = sorted([*extra, active])
    if not extra:
        out["wsmore"] = {"text": ""}
    else:
        cls = ["ws", "more"]
        if active and active > LAST:
            cls.append("active")
        if any(ws and ws > LAST for ws in urgent_ws):
            cls.append("urgent")
        text = f"…{active}" if active and active > LAST else "…"
        out["wsmore"] = {"text": text, "class": cls, "tooltip": "Workspaces: " + ", ".join(map(str, extra))}
    return out


# ---------------------------------------------------------------- active window

G = chr
# (regex on the window class, glyph, display name); first match wins
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
DEFAULT_GLYPH = G(0xF05B2)
TITLE_SUFFIX = re.compile(r"\s+[-—–]\s+(Brave( Origin)?|Mozilla Firefox|Discord|Visual Studio Code)$")


def cut(text, limit):
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


def app(cls):
    for rx, glyph, name in APPS:
        if re.search(rx, cls, re.I):
            return glyph, name
    name = re.split(r"[.]", cls)[-1].replace("-", " ").replace("_", " ").strip().title()
    return DEFAULT_GLYPH, name or "Window"


def window_feeds(window):
    """{"window": ..., "window-compact": ...}: glyph + title (compact: glyph + app name)."""
    if not window or not window.get("class"):
        empty = {"text": "", "class": "none"}
        return {"window": empty, "window-compact": empty}
    glyph, name = app(window["class"])
    title = TITLE_SUFFIX.sub("", window.get("title", "")).strip()
    tip = html.escape("\n".join(x for x in (window.get("title", ""), window["class"]) if x))
    full = f"{glyph}  " + html.escape(cut(title, 40) if title and title.lower() != name.lower() else name)
    return {
        "window": {"text": full, "class": "active", "tooltip": tip},
        "window-compact": {"text": f"{glyph}  {html.escape(name)}", "class": "active", "tooltip": tip},
    }


# ---------------------------------------------------------------- media

PLAY, PAUSE = "\U000f040a", "\U000f03e4"  # 󰐊 󰏤 (the icon shows the current state)
PREV, NEXT = "\U000f04ae", "\U000f04ad"  # 󰒮 󰒭
GAP = "   •   "
WIDTH = {"media": 30, "media-compact": 22}  # visible title characters
HOLD = 7  # ticks the title rests at its start


def media_button_feeds(status):
    """prev/play/next: hidden (empty) while nothing plays."""
    if status not in ("Playing", "Paused"):
        return {k: {"text": "", "class": "none"} for k in ("media-prev", "media-play", "media-next")}
    cls = status.lower()
    return {
        "media-prev": {"text": f"<span size='small'>{PREV}</span>", "class": cls, "tooltip": "Previous"},
        "media-play": {
            "text": f"<span size='large'>{PLAY if status == 'Playing' else PAUSE}</span>",
            "class": cls,
            "tooltip": "Pause" if status == "Playing" else "Play",
        },
        "media-next": {"text": f"<span size='small'>{NEXT}</span>", "class": cls, "tooltip": "Next"},
    }


def title_feed(meta, offset, width, compact):
    """The title pill: a WIDTH character window into the title, starting at offset."""
    status, artist, title, album = meta
    if status not in ("Playing", "Paused") or not title:
        return {"text": "", "class": "none"}
    if len(title) <= width:
        shown = title
    else:
        loop = title + GAP
        shown = (loop * 2)[offset : offset + width]
    text = html.escape(shown)
    if artist and not compact:
        text += f"  <span size='small' alpha='60%'>{html.escape(cut(artist, 18))}</span>"
    tip = "\n".join(x for x in (f"{artist} – {title}" if artist else title, album) if x)
    return {"text": text, "class": status.lower(), "tooltip": html.escape(tip)}


# ---------------------------------------------------------------- output


class Feeds:
    def __init__(self, directory):
        self.dir = directory
        os.makedirs(directory, exist_ok=True)
        self.last = {}
        self.lock = threading.Lock()

    def write(self, items, sig):
        """Write the changed items; one signal to waybar if anything changed."""
        changed = False
        with self.lock:
            for name, data in items.items():
                line = json.dumps(data, ensure_ascii=False)
                if self.last.get(name) == line:
                    continue
                tmp = f"{self.dir}/.{name}.tmp"
                with open(tmp, "w") as f:
                    f.write(line + "\n")
                os.replace(tmp, f"{self.dir}/{name}.json")
                self.last[name] = line
                changed = True
        if changed:
            signal_waybar(sig)


def signal_waybar(sig):
    for pid in subprocess.run(["pgrep", "-x", "waybar"], capture_output=True, text=True).stdout.split():
        try:
            os.kill(int(pid), signal.SIGRTMIN + sig)
        except (ProcessLookupError, ValueError):
            pass


def hypr_socket(name):
    return f"{os.environ['XDG_RUNTIME_DIR']}/hypr/{os.environ['HYPRLAND_INSTANCE_SIGNATURE']}/{name}"


def hyprctl(request):
    """A JSON request over Hyprland's command socket (what "hyprctl -j" does, without a process)."""
    with socket.socket(socket.AF_UNIX) as s:
        s.connect(hypr_socket(".socket.sock"))
        s.sendall(f"j/{request}".encode())
        data = b""
        while chunk := s.recv(65536):
            data += chunk
    return json.loads(data or b"null")


def follow_hyprland(feeds):
    urgent = set()

    def update():
        try:
            active = (hyprctl("activeworkspace") or {}).get("id")
            windows = {w["id"]: w["windows"] for w in hyprctl("workspaces") or []}
            clients = {c["address"].removeprefix("0x"): c["workspace"]["id"] for c in hyprctl("clients") or []}
            window = hyprctl("activewindow")
        except (OSError, ValueError, KeyError):
            return
        for address in list(urgent):  # a focused workspace or a closed window clears it
            if clients.get(address) in (None, active):
                urgent.discard(address)
        feeds.write(workspace_feeds(active, windows, clients, urgent) | window_feeds(window), SIG_HYPR)

    update()
    with socket.socket(socket.AF_UNIX) as sock:
        sock.connect(hypr_socket(".socket2.sock"))
        buf = b""
        while chunk := sock.recv(4096):
            buf += chunk
            *lines, buf = buf.split(b"\n")
            dirty = False
            for raw in lines:
                event, _, arg = raw.decode(errors="replace").partition(">>")
                if event == "urgent":
                    urgent.add(arg.strip().removeprefix("0x"))
                dirty |= event in HYPR_EVENTS
            if dirty:
                update()


def follow_media(feeds):
    """playerctl --follow for the state, a 0.3 s tick to scroll long titles while playing."""
    state = {"meta": ("", "", "", ""), "seen": 0}
    fmt = "{{status}}\t{{artist}}\t{{title}}\t{{album}}"

    def reader():
        while True:
            proc = subprocess.Popen(
                ["playerctl", "--follow", "metadata", "--format", fmt],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
            )
            for raw in proc.stdout:
                parts = (raw.rstrip("\n").split("\t") + ["", "", "", ""])[:4]
                state["meta"] = tuple(parts)
                state["seen"] += 1
                feeds.write(media_button_feeds(parts[0]), SIG_MEDIA)
            time.sleep(5)  # playerctl missing or gone: try again later

    threading.Thread(target=reader, daemon=True).start()
    seen, offset, hold = -1, 0, HOLD
    while True:
        meta = state["meta"]
        if state["seen"] != seen:
            seen, offset, hold = state["seen"], 0, HOLD
        feeds.write(
            {name: title_feed(meta, offset, width, name.endswith("compact")) for name, width in WIDTH.items()},
            SIG_TITLE,
        )
        if meta[0] == "Playing" and len(meta[2]) > min(WIDTH.values()):
            if offset == 0 and hold > 0:
                hold -= 1
            else:
                offset = (offset + 1) % len(meta[2] + GAP)
                hold = HOLD if offset == 0 else 0
        time.sleep(0.3)


def main():
    feeds = Feeds(f"{os.environ['XDG_RUNTIME_DIR']}/driftless-bar")
    threading.Thread(target=follow_media, args=(feeds,), daemon=True).start()
    # Hyprland restarts or is not up yet: reconnect
    while True:
        try:
            follow_hyprland(feeds)
        except (OSError, KeyError):
            pass
        time.sleep(2)


if __name__ == "__main__":
    main()
