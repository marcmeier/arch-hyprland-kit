#!/usr/bin/env python3
"""Waybar: cycle the default audio output through the real sinks (skips the MiniFuse loopback)
and move running streams along. Announces the new output via notify-send."""
import json, subprocess, time

def pactl(*a):
    return subprocess.run(["pactl", *a], capture_output=True, text=True).stdout

sinks = [s for s in json.loads(pactl("--format=json", "list", "sinks")) if "Line2" not in s["name"]]
if len(sinks) < 2:
    raise SystemExit
cur = pactl("get-default-sink").strip()
names = [s["name"] for s in sinks]
nxt = sinks[(names.index(cur) + 1) % len(sinks)] if cur in names else sinks[0]
pactl("set-default-sink", nxt["name"])
for line in pactl("list", "short", "sink-inputs").splitlines():
    pactl("move-sink-input", line.split()[0], nxt["name"])
subprocess.run(["notify-send", "-a", "audio", "-t", "2000",
                "-h", "string:x-canonical-private-synchronous:audio-out",
                "Audio output", f"{nxt['description']}\n<small>{time.strftime('%H:%M')}</small>"])
