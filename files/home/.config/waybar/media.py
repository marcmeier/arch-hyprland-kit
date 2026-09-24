#!/usr/bin/env python3
"""Waybar: now-playing pill, one process per segment. Usage: media.py prev|play|next|info
prev/next/play are the transport buttons (play is larger, prev/next smaller), info is title
(scrolls when longer than WIDTH) + dimmed artist. All segments print empty text (hidden) when
nothing plays. "compact" (2nd arg): shorter title, artist only in the tooltip."""

import html
import json
import subprocess
import sys
import threading
import time

MODE = sys.argv[1] if len(sys.argv) > 1 else "info"
COMPACT = "compact" in sys.argv[2:]
WIDTH, TICK, HOLD = (22 if COMPACT else 30), 0.3, 7  # visible title chars, seconds per step, ticks to rest at the start
GAP = "   \u2022   "
FMT = "{{status}}\t{{artist}}\t{{title}}\t{{album}}"
PLAY, PAUSE = "\U000f040a", "\U000f03e4"  # 󰐊 󰏤 (icon shows the current state)
PREV, NEXT = "\U000f04ae", "\U000f04ad"  # 󰒮 󰒭


def cut(text, limit):
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


def emit(data):
    print(json.dumps(data, ensure_ascii=False), flush=True)


player = subprocess.Popen(
    ["playerctl", "--follow", "metadata", "--format", FMT], stdout=subprocess.PIPE, text=True, stderr=subprocess.DEVNULL
)


def run_info():
    """Title scrolls through the whole text in a WIDTH-char window while playing."""
    cur = {"line": None}

    def reader():
        for raw in player.stdout:
            cur["line"] = raw

    threading.Thread(target=reader, daemon=True).start()
    last_line, offset, hold, last_out = None, 0, HOLD, None
    while player.poll() is None:
        line = cur["line"]
        if line is not last_line:
            last_line, offset, hold = line, 0, HOLD
        parts = (line or "").rstrip("\n").split("\t")
        if len(parts) < 4 or parts[0] not in ("Playing", "Paused") or not parts[2]:
            out = {"text": "", "class": "none"}
        else:
            status, artist, title, album = parts[:4]
            if len(title) <= WIDTH:
                shown = title
            else:
                loop_s = title + GAP
                shown = (loop_s * 2)[offset : offset + WIDTH]
                if status == "Playing":
                    if offset == 0 and hold > 0:
                        hold -= 1
                    else:
                        offset = (offset + 1) % len(loop_s)
                        hold = HOLD if offset == 0 else 0
            text = html.escape(shown)
            if artist and not COMPACT:
                text += f"  <span size='small' alpha='60%'>{html.escape(cut(artist, 18))}</span>"
            tip = "\n".join(x for x in (f"{artist} \u2013 {title}" if artist else title, album) if x)
            out = {"text": text, "class": status.lower(), "tooltip": html.escape(tip)}
        if out != last_out:
            emit(out)
            last_out = out
        time.sleep(TICK)


if MODE == "info":
    run_info()
    sys.exit(0)

for line in player.stdout:
    parts = line.rstrip("\n").split("\t")
    if len(parts) < 4 or parts[0] not in ("Playing", "Paused") or not parts[2]:
        emit({"text": "", "class": "none"})
        continue
    status, artist, title, album = parts[:4]
    cls = status.lower()
    if MODE == "play":
        emit(
            {
                "text": f"<span size='large'>{PLAY if status == 'Playing' else PAUSE}</span>",
                "class": cls,
                "tooltip": "Pause" if status == "Playing" else "Play",
            }
        )
    elif MODE == "prev":
        emit({"text": f"<span size='small'>{PREV}</span>", "class": cls, "tooltip": "Previous"})
    elif MODE == "next":
        emit({"text": f"<span size='small'>{NEXT}</span>", "class": cls, "tooltip": "Next"})
    else:
        text = html.escape(cut(title, 30))
        if artist:
            text += f"  <span size='small' alpha='60%'>{html.escape(cut(artist, 18))}</span>"
        tip = "\n".join(x for x in (f"{artist} – {title}" if artist else title, album) if x)
        emit({"text": text, "class": cls, "tooltip": html.escape(tip)})
