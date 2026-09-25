#!/usr/bin/env python3
"""Waybar: next calendar event (khal). Icon only when nothing is coming up in 2 days.
"compact": always icon only (class "next" still marks an upcoming event), agenda in the tooltip."""
import html, json, os, re, subprocess, sys, datetime

def khal(*a):
    try:
        return subprocess.run(["khal", *a], capture_output=True, text=True, timeout=15).stdout
    except Exception:
        return ""

ansi = re.compile(r"\x1b\[[0-9;]*m")
today = datetime.date.today().strftime("%d.%m.%Y")
tomorrow = (datetime.date.today() + datetime.timedelta(days=1)).strftime("%d.%m.%Y")
out = khal("list", "--notstarted", "--once", "--day-format", "",
           "--format", "{start-date}|{start-time}|{title}", "now", "2d")
first = next((l for l in ansi.sub("", out).splitlines() if l.count("|") >= 2), None)
ICON = "<span size='large'>󰃭</span>"
text, cls = ICON, "none"
if first:
    d, t, title = first.split("|", 2)
    t = t.strip()
    day = "" if d == today else ("tmrw" if d == tomorrow else
          datetime.datetime.strptime(d, "%d.%m.%Y").strftime("%a"))
    # slim label: drop trailing "(...)" and shorten long titles
    title = re.sub(r"\s*\(.*?\)\s*$", "", title).strip() or title.strip()
    if len(title) > 22: title = title[:21].rstrip() + "…"
    label = " ".join(x for x in (day, t, title) if x)
    text, cls = f"{ICON}  {html.escape(label)}", "next"
if "compact" in sys.argv[1:]:
    text = ICON
state = os.path.expanduser("~/.cache/calendar-sync-failed")
failed = os.path.exists(state)
if failed:
    reason = open(state).read().strip()
    text, cls = f"⚠ {text}", "error"
agenda = ansi.sub("", khal("list", "now", "3d")).strip() or "No events in the next 3 days"
agenda = "\n".join(l if len(l) <= 60 else l[:59] + "…" for l in agenda.splitlines())
if failed: agenda = f"⚠ Sync failed: {reason}\n\n{agenda}"
print(json.dumps({"text": text, "class": cls, "tooltip": html.escape(agenda)}))
