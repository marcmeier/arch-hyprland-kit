#!/usr/bin/env python3
"""Waybar custom module: one workspace button. Usage: ws.py N
Streams a JSON line whenever Hyprland reports a change (socket2 events)."""

import json
import os
import socket
import subprocess
import sys

MORE = sys.argv[1] == "more"  # overflow pill for workspaces > LAST
N = 0 if MORE else int(sys.argv[1])
LAST = 5


def hc(*a):
    return json.loads(subprocess.run(["hyprctl", "-j", *a], capture_output=True, text=True).stdout or "null")


urgent = set()  # addresses (without 0x) of windows that asked for attention


def emit():
    try:
        active = (hc("activeworkspace") or {}).get("id")
        wins = {w["id"]: w["windows"] for w in (hc("workspaces") or [])}
        clients = {c["address"][2:]: c["workspace"]["id"] for c in (hc("clients") or [])}
    except Exception:
        return
    # focused workspace or closed window clears the urgent state
    for a in list(urgent):
        if clients.get(a) in (None, active):
            urgent.discard(a)
    if MORE:
        extra = sorted(i for i, n in wins.items() if i > LAST and n)
        if active and active > LAST and active not in extra:
            extra.append(active)
        extra.sort()
        if not extra:
            print(json.dumps({"text": ""}), flush=True)
            return
        cls = ["ws", "more"]
        if active and active > LAST:
            cls.append("active")
        if any(clients.get(a, 0) > LAST for a in urgent):
            cls.append("urgent")
        text = f"\u2026{active}" if active and active > LAST else "\u2026"
        tip = "Workspaces: " + ", ".join(str(i) for i in extra)
        print(json.dumps({"text": text, "class": cls, "tooltip": tip}), flush=True)
        return
    cls = ["ws"]
    if active == N:
        cls.append("active")
    if any(clients.get(a) == N for a in urgent):
        cls.append("urgent")
    if not wins.get(N):
        cls.append("empty")
    print(json.dumps({"text": str(N), "class": cls, "tooltip": ""}), flush=True)  # False is shown as the text "false"


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
    dirty = False
    for raw in lines:
        ev, _, arg = raw.decode(errors="replace").partition(">>")
        if ev == "urgent":
            urgent.add(arg.strip().removeprefix("0x"))
            dirty = True
        elif ev in (
            "workspacev2",
            "workspace",
            "focusedmon",
            "activewindowv2",
            "openwindow",
            "closewindow",
            "movewindowv2",
            "createworkspacev2",
            "destroyworkspacev2",
        ):
            dirty = True
    if dirty:
        emit()
