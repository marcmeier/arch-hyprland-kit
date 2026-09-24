#!/usr/bin/env python3
"""Waybar: Claude Code usage pill.
Bar text: session (5h) and weekly utilisation from Anthropic's OAuth usage endpoint (needs the Claude Code login
in ~/.claude/.credentials.json; the token is only read, never printed or refreshed). Tooltip: reset times and
token counts per day from the local Claude Code logs (~/.claude/projects). Without a working API answer it falls
back to the last cached values (marked stale) or to a purely local estimate.
"compact": only the limit that is closer to running out."""

import datetime as dt
import glob
import html
import json
import os
import sys
import time
import urllib.request

HOME = os.path.expanduser("~")
CACHE = HOME + "/.cache/claude-usage.json"
DAYS = 7
ICON = "\U000f06a9"  # 󰚩


def fmt_n(n):
    return f"{n / 1e6:.1f}M" if n >= 1e6 else f"{n / 1e3:.0f}k" if n >= 1e3 else str(n)


def fmt_delta(sec):
    sec = max(int(sec), 0)
    d, r = divmod(sec, 86400)
    h, r = divmod(r, 3600)
    m = r // 60
    return f"{d}d {h}h" if d else f"{h}h {m:02d}m" if h else f"{m}m"


def parse(ts):
    return dt.datetime.fromisoformat(ts.replace("Z", "+00:00"))


def api():
    try:
        tok = json.load(open(HOME + "/.claude/.credentials.json"))["claudeAiOauth"]["accessToken"]
        req = urllib.request.Request(
            "https://api.anthropic.com/api/oauth/usage",
            headers={
                "Authorization": "Bearer " + tok,
                "anthropic-beta": "oauth-2025-04-20",
                "User-Agent": "claude-code/2",
            },
        )
        d = json.load(urllib.request.urlopen(req, timeout=8))
        out = {"time": time.time(), "session": d["five_hour"], "week": d["seven_day"]}
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        with open(os.open(CACHE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
            json.dump(out, f)
        return out, False
    except Exception:
        try:
            c = json.load(open(CACHE))
            return (c, True) if time.time() - c["time"] < 6 * 3600 else (None, True)
        except Exception:
            return None, True


def local():
    """Tokens per local day + start of the current 5h window, from the Claude Code logs (deduplicated per message)."""
    cutoff = time.time() - (DAYS + 1) * 86400
    seen = {}
    for f in glob.glob(HOME + "/.claude/projects/**/*.jsonl", recursive=True):
        if os.path.getmtime(f) < cutoff:
            continue
        for line in open(f, errors="replace"):
            if '"usage"' not in line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            m = d.get("message")
            if not isinstance(m, dict) or not isinstance(m.get("usage"), dict) or not d.get("timestamp"):
                continue
            u = m["usage"]
            seen[(m.get("id"), d.get("requestId"), d["timestamp"] if not m.get("id") else "")] = (
                parse(d["timestamp"]),
                u.get("input_tokens", 0) or 0,
                u.get("output_tokens", 0) or 0,
                u.get("cache_creation_input_tokens", 0) or 0,
                u.get("cache_read_input_tokens", 0) or 0,
            )
    days, stamps = {}, []
    for t, i, o, cc, cr in seen.values():
        stamps.append(t)
        k = t.astimezone().date()
        a = days.setdefault(k, [0, 0, 0, 0])
        a[0] += i
        a[1] += o
        a[2] += cc
        a[3] += cr
    # current 5h window: starts at the first message after a gap of >= 5h (approximation of Anthropic's rule)
    win = None
    for t in sorted(stamps):
        if win is None or t >= win + dt.timedelta(hours=5):
            win = t
    return days, win


def cls_for(p):
    return "crit" if p >= 90 else "warn" if p >= 70 else "ok"


DIM, WARN, CRIT = "#6b7280", "#ffb454", "#ff5f6d"
try:
    ACC = json.load(open(os.path.expanduser("~/.config/theme/colors.json")))["primary"]
except (OSError, ValueError, KeyError):
    ACC = "#33ccff"


def dim(t):
    return f"<span color='{DIM}'>{html.escape(t)}</span>"


def bar(p, width=14):
    filled = round(width * min(p, 100) / 100)
    col = CRIT if p >= 90 else WARN if p >= 70 else ACC
    return f"<span color='{col}'>{'█' * filled}</span><span color='{DIM}'>{'░' * (width - filled)}</span>"


def limit_block(name, x, p, now):
    r = parse(x["resets_at"]) if x.get("resets_at") else None
    when = (
        f"resets {r.astimezone():%a %H:%M}  ·  in {fmt_delta((r - now).total_seconds())}"
        if r and r > now
        else "no active window"
        if not r
        else "reset due"
    )
    return [f"<b>{name:<8}</b>{bar(p)}  <b>{p:>3}%</b>", "        " + dim(when)]


def token_table(days, today):
    rows = [(d, v) for d, v in sorted(days.items(), reverse=True) if (today - d).days < DAYS]
    if not rows:
        return [dim("no local data")]
    out = [dim(f"{'':<11}{'in':>7}{'out':>7}{'cache w':>9}{'cache r':>9}")]
    for d, v in rows:
        lab = "Today" if d == today else "Yesterday" if (today - d).days == 1 else f"{d:%a %d %b}"
        out.append(f"{lab:<11}" + "".join(f"{fmt_n(x):>{w}}" for x, w in zip(v, (7, 7, 9, 9), strict=False)))
    return out


def main():
    days, win = local()
    data, stale = api()
    today = dt.date.today()
    now = dt.datetime.now(dt.UTC)
    head = "<b>Claude Code usage</b>"
    lines = []
    if data:
        s, w = data["session"], data["week"]
        sp, wp = round(s["utilization"]), round(w["utilization"])
        text = f"{ICON}  <span size='small' alpha='60%'>5h</span> {sp}%  <span size='small' alpha='60%'>7d</span> {wp}%"
        if "compact" in sys.argv[1:]:
            text = f"{ICON}  {max(sp, wp)}%"
        cls = "stale" if stale else cls_for(max(sp, wp))
        lines += limit_block("Session", s, sp, now) + [""] + limit_block("Week", w, wp, now)
        if stale:
            lines += ["", dim(f"API unreachable, values from {fmt_delta(time.time() - data['time'])} ago")]
    else:
        t = days.get(today, [0, 0, 0, 0])
        text = f"{ICON}  {fmt_n(t[0] + t[1] + t[2])} <span size='small' alpha='60%'>today</span>"
        cls = "stale"
        if win and win + dt.timedelta(hours=5) > now:
            end = win + dt.timedelta(hours=5)
            lines.append(
                f"<b>Session</b>  ends about {end.astimezone():%H:%M}  ·  in {fmt_delta((end - now).total_seconds())}"
            )
        lines.append(dim("Usage API unavailable (login expired? start Claude Code once)"))
    lines += (
        ["", "<b>Tokens on this PC</b>"] + token_table(days, today) + ["", dim("Click: open usage page on claude.ai")]
    )
    print(json.dumps({"text": text, "class": cls, "tooltip": "\n".join([head, ""] + lines)}, ensure_ascii=False))


main()
