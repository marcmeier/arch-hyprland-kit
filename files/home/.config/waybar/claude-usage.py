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


def fmt_count(count):
    if count >= 1e6:
        return f"{count / 1e6:.1f}M"
    if count >= 1e3:
        return f"{count / 1e3:.0f}k"
    return str(count)


def fmt_delta(seconds):
    seconds = max(int(seconds), 0)
    days, rest = divmod(seconds, 86400)
    hours, rest = divmod(rest, 3600)
    minutes = rest // 60
    if days:
        return f"{days}d {hours}h"
    if hours:
        return f"{hours}h {minutes:02d}m"
    return f"{minutes}m"


def parse_time(stamp):
    return dt.datetime.fromisoformat(stamp.replace("Z", "+00:00"))


def api():
    """Current limits from the usage endpoint, as (data, stale). Falls back to the cache for 6 hours."""
    try:
        token = json.load(open(HOME + "/.claude/.credentials.json"))["claudeAiOauth"]["accessToken"]
        request = urllib.request.Request(
            "https://api.anthropic.com/api/oauth/usage",
            headers={
                "Authorization": "Bearer " + token,
                "anthropic-beta": "oauth-2025-04-20",
                "User-Agent": "claude-code/2",
            },
        )
        answer = json.load(urllib.request.urlopen(request, timeout=8))
        data = {"time": time.time(), "session": answer["five_hour"], "week": answer["seven_day"]}
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        with open(os.open(CACHE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as cache_file:
            json.dump(data, cache_file)
        return data, False
    except Exception:
        try:
            cached = json.load(open(CACHE))
            return (cached, True) if time.time() - cached["time"] < 6 * 3600 else (None, True)
        except Exception:
            return None, True


def local():
    """Tokens per local day + start of the current 5h window, from the Claude Code logs (deduplicated per message)."""
    cutoff = time.time() - (DAYS + 1) * 86400
    messages = {}
    for log in glob.glob(HOME + "/.claude/projects/**/*.jsonl", recursive=True):
        if os.path.getmtime(log) < cutoff:
            continue
        for line in open(log, errors="replace"):
            if '"usage"' not in line:
                continue
            try:
                entry = json.loads(line)
            except Exception:
                continue
            message = entry.get("message")
            if (
                not isinstance(message, dict)
                or not isinstance(message.get("usage"), dict)
                or not entry.get("timestamp")
            ):
                continue
            usage = message["usage"]
            key = (message.get("id"), entry.get("requestId"), entry["timestamp"] if not message.get("id") else "")
            messages[key] = (
                parse_time(entry["timestamp"]),
                usage.get("input_tokens", 0) or 0,
                usage.get("output_tokens", 0) or 0,
                usage.get("cache_creation_input_tokens", 0) or 0,
                usage.get("cache_read_input_tokens", 0) or 0,
            )
    days, stamps = {}, []
    for stamp, tokens_in, tokens_out, cache_write, cache_read in messages.values():
        stamps.append(stamp)
        totals = days.setdefault(stamp.astimezone().date(), [0, 0, 0, 0])
        totals[0] += tokens_in
        totals[1] += tokens_out
        totals[2] += cache_write
        totals[3] += cache_read
    # current 5h window: starts at the first message after a gap of >= 5h (approximation of Anthropic's rule)
    window_start = None
    for stamp in sorted(stamps):
        if window_start is None or stamp >= window_start + dt.timedelta(hours=5):
            window_start = stamp
    return days, window_start


def level(percent):
    return "crit" if percent >= 90 else "warn" if percent >= 70 else "ok"


DIM, WARN, CRIT = "#6b7280", "#ffb454", "#ff5f6d"
try:
    ACCENT = json.load(open(os.path.expanduser("~/.config/theme/colors.json")))["primary"]
except (OSError, ValueError, KeyError):
    ACCENT = "#33ccff"


def dim(text):
    return f"<span color='{DIM}'>{html.escape(text)}</span>"


def bar(percent, width=14):
    filled = round(width * min(percent, 100) / 100)
    color = CRIT if percent >= 90 else WARN if percent >= 70 else ACCENT
    return f"<span color='{color}'>{'█' * filled}</span><span color='{DIM}'>{'░' * (width - filled)}</span>"


def limit_block(name, limit, percent, now):
    resets = parse_time(limit["resets_at"]) if limit.get("resets_at") else None
    if not resets:
        when = "no active window"
    elif resets > now:
        when = f"resets {resets.astimezone():%a %H:%M}  ·  in {fmt_delta((resets - now).total_seconds())}"
    else:
        when = "reset due"
    return [f"<b>{name:<8}</b>{bar(percent)}  <b>{percent:>3}%</b>", "        " + dim(when)]


def token_table(days, today):
    rows = [(day, counts) for day, counts in sorted(days.items(), reverse=True) if (today - day).days < DAYS]
    if not rows:
        return [dim("no local data")]
    table = [dim(f"{'':<11}{'in':>7}{'out':>7}{'cache w':>9}{'cache r':>9}")]
    for day, counts in rows:
        label = "Today" if day == today else "Yesterday" if (today - day).days == 1 else f"{day:%a %d %b}"
        columns = zip(counts, (7, 7, 9, 9), strict=False)
        table.append(f"{label:<11}" + "".join(f"{fmt_count(count):>{width}}" for count, width in columns))
    return table


def main():
    days, window_start = local()
    data, stale = api()
    today = dt.date.today()
    now = dt.datetime.now(dt.UTC)
    head = "<b>Claude Code usage</b>"
    lines = []
    if data:
        session, week = data["session"], data["week"]
        session_pct, week_pct = round(session["utilization"]), round(week["utilization"])
        small = "<span size='small' alpha='60%'>"
        text = f"{ICON}  {small}5h</span> {session_pct}%  {small}7d</span> {week_pct}%"
        if "compact" in sys.argv[1:]:
            text = f"{ICON}  {max(session_pct, week_pct)}%"
        state = "stale" if stale else level(max(session_pct, week_pct))
        lines += limit_block("Session", session, session_pct, now) + [""] + limit_block("Week", week, week_pct, now)
        if stale:
            lines += ["", dim(f"API unreachable, values from {fmt_delta(time.time() - data['time'])} ago")]
    else:
        today_counts = days.get(today, [0, 0, 0, 0])
        text = f"{ICON}  {fmt_count(sum(today_counts[:3]))} <span size='small' alpha='60%'>today</span>"
        state = "stale"
        if window_start and window_start + dt.timedelta(hours=5) > now:
            end = window_start + dt.timedelta(hours=5)
            lines.append(
                f"<b>Session</b>  ends about {end.astimezone():%H:%M}  ·  in {fmt_delta((end - now).total_seconds())}"
            )
        lines.append(dim("Usage API unavailable (login expired? start Claude Code once)"))
    lines += (
        ["", "<b>Tokens on this PC</b>"] + token_table(days, today) + ["", dim("Click: open usage page on claude.ai")]
    )
    print(json.dumps({"text": text, "class": state, "tooltip": "\n".join([head, ""] + lines)}, ensure_ascii=False))


main()
