#!/usr/bin/env python3
"""The bar: calendar data from khal (synced from Nextcloud by calendar-sync.sh) as one JSON object.
  agenda.py                  the next event within 2 days, the agenda of the next 7 days, a failed sync
  agenda.py month YYYY-MM    the days of that month with events (the dots of the month view)
  agenda.py day YYYY-MM-DD   the events of one day
Dates come in khal's own format (dateformat in ~/.config/khal/config), read with that format."""

import configparser
import datetime as dt
import json
import os
import re
import subprocess
import sys

ANSI = re.compile(r"\x1b\[[0-9;]*m")
FIELDS = "{start-date}\x1f{start-time}\x1f{end-time}\x1f{title}\x1f{calendar}\x1f{all-day}\x1f{location}"


def khal(*args):
    try:
        out = subprocess.run(["khal", *args], capture_output=True, text=True, timeout=15).stdout
    except Exception:
        return ""
    return ANSI.sub("", out)


def date_format():
    cfg = configparser.ConfigParser(interpolation=None, strict=False)
    try:
        cfg.read(os.path.expanduser("~/.config/khal/config"))
        return cfg.get("locale", "dateformat", fallback="%d.%m.%Y")
    except configparser.Error:
        return "%d.%m.%Y"


FMT = date_format()


def parse_date(text):
    try:
        return dt.datetime.strptime(text.strip(), FMT).date()
    except ValueError:
        return None


def listing(start, span):
    """[(day, event)] from khal list, an event on every day it covers (headers mark the days)."""
    out = khal("list", "--format", "E\x1f" + FIELDS, "--day-format", "D\x1f{date}", start.strftime(FMT), span)
    day, rows = None, []
    for line in out.splitlines():
        kind, _, rest = line.partition("\x1f")
        if kind == "D":
            day = parse_date(rest)
        elif kind == "E" and day:
            start_date, start_time, end_time, title, calendar, all_day, where = (rest.split("\x1f") + [""] * 7)[:7]
            rows.append(
                (
                    day,
                    {
                        "start": start_time.strip(),
                        "end": end_time.strip(),
                        "title": title.strip(),
                        "calendar": calendar.strip(),
                        "allDay": all_day.strip() == "True",
                        "location": where.strip(),
                        # a multi-day event on a later day: it began before this day
                        "continued": parse_date(start_date) not in (None, day),
                    },
                )
            )
    return rows


def label(day, today):
    if day == today:
        return "Today"
    if day == today + dt.timedelta(days=1):
        return "Tomorrow"
    return f"{day:%A}"


def summary():
    today = dt.date.today()
    nxt = None
    out = khal(
        "list", "--notstarted", "--once", "--day-format", "", "--format",
        "{start-date}\x1f{start-time}\x1f{title}", "now", "2d",
    )  # fmt: skip
    for line in out.splitlines():
        parts = line.split("\x1f")
        if len(parts) >= 3 and parse_date(parts[0]):
            day = parse_date(parts[0])
            title = re.sub(r"\s*\(.*?\)\s*$", "", parts[2]).strip() or parts[2].strip()
            when = "" if day == today else "tmrw" if day == today + dt.timedelta(days=1) else f"{day:%a}"
            nxt = {"when": " ".join(x for x in (when, parts[1].strip()) if x), "title": title}
            break
    agenda = {}
    for day, event in listing(today, "7d"):
        agenda.setdefault(day, []).append(event)
    state = os.path.expanduser("~/.cache/calendar-sync-failed")
    error = None
    if os.path.exists(state):
        error = open(state).read().strip() or "calendar sync failed"
    return {
        "next": nxt,
        "agenda": [
            {"date": day.isoformat(), "label": label(day, today), "sub": f"{day:%d %b}", "events": events}
            for day, events in sorted(agenda.items())
        ],
        "error": error,
    }


def month(spec):
    try:
        first = dt.date.fromisoformat(spec + "-01")
    except ValueError:
        first = dt.date.today().replace(day=1)
    nxt = (first + dt.timedelta(days=32)).replace(day=1)
    days = sorted({day.day for day, _ in listing(first, f"{(nxt - first).days}d") if day.month == first.month})
    return {"month": f"{first:%Y-%m}", "days": days}


def one_day(spec):
    try:
        day = dt.date.fromisoformat(spec)
    except ValueError:
        day = dt.date.today()
    events = [event for d, event in listing(day, "1d") if d == day]
    return {"date": day.isoformat(), "label": label(day, dt.date.today()), "sub": f"{day:%d %b}", "events": events}


if __name__ == "__main__":
    if sys.argv[1:2] == ["day"]:
        print(json.dumps(one_day(sys.argv[2] if len(sys.argv) > 2 else ""), ensure_ascii=False))
    elif sys.argv[1:2] == ["month"]:
        print(json.dumps(month(sys.argv[2] if len(sys.argv) > 2 else ""), ensure_ascii=False))
    else:
        print(json.dumps(summary(), ensure_ascii=False))
