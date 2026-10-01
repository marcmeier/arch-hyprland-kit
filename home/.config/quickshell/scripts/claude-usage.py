#!/usr/bin/env python3
"""The bar: Claude Code usage as one JSON object.
Session (5h) and weekly utilisation with their reset times from Anthropic's OAuth usage endpoint (needs the
Claude Code login in ~/.claude/.credentials.json; the token is only read, never printed or refreshed), and
token counts per day from the local Claude Code logs (~/.claude/projects). Without a working API answer it
falls back to the last cached values (marked stale) or to a purely local estimate."""

import datetime as dt
import glob
import json
import os
import time
import urllib.request

HOME = os.path.expanduser("~")
CACHE = HOME + "/.cache/claude-usage.json"
DAYS = 7


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


def limit(data, now):
    """{"pct": ..., "resets": ISO time or None, "in": seconds until the reset or None}"""
    resets = parse_time(data["resets_at"]) if data.get("resets_at") else None
    return {
        "pct": round(data["utilization"]),
        "resets": resets.astimezone().isoformat() if resets else None,
        "in": max(int((resets - now).total_seconds()), 0) if resets else None,
    }


def token_rows(days, today):
    rows = []
    for day, counts in sorted(days.items(), reverse=True):
        if (today - day).days >= DAYS:
            continue
        label = "Today" if day == today else "Yesterday" if (today - day).days == 1 else f"{day:%a %d %b}"
        tokens_in, tokens_out, cache_write, cache_read = counts
        rows.append(
            {"label": label, "in": tokens_in, "out": tokens_out, "cacheWrite": cache_write, "cacheRead": cache_read}
        )
    return rows


def main():
    days, window_start = local()
    data, stale = api()
    today = dt.date.today()
    now = dt.datetime.now(dt.UTC)
    out = {"days": token_rows(days, today), "stale": stale}
    if data:
        out["session"] = limit(data["session"], now)
        out["week"] = limit(data["week"], now)
        out["level"] = "stale" if stale else level(max(out["session"]["pct"], out["week"]["pct"]))
        out["age"] = int(time.time() - data["time"])
    else:
        # no answer from the API and nothing cached: tokens of today and the 5h window, estimated locally
        counts = days.get(today, [0, 0, 0, 0])
        out["today"] = sum(counts[:3])
        out["level"] = "stale"
        if window_start and window_start + dt.timedelta(hours=5) > now:
            end = window_start + dt.timedelta(hours=5)
            out["windowEnd"] = end.astimezone().isoformat()
            out["windowIn"] = int((end - now).total_seconds())
    print(json.dumps(out, ensure_ascii=False))


main()
