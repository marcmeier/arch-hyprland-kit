#!/usr/bin/env python3
"""Erzeugt list.txt: '<emoji> <name>' pro Zeile, durchsuchbar (Name plus Aliase)."""
import os, emoji
out = os.path.expanduser("~/.config/emoji/list.txt")
with open(out, "w") as f:
    for ch, d in emoji.EMOJI_DATA.items():
        if d["status"] > emoji.STATUS["fully_qualified"]:
            continue
        names = [d["en"]] + d.get("alias", [])
        names = [n.strip(":").replace("_", " ") for n in names]
        f.write(ch + " " + " | ".join(dict.fromkeys(names)) + "\n")
