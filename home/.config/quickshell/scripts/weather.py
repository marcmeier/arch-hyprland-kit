#!/usr/bin/env python3
"""The bar: weather from wttr.in as one JSON object (current conditions, the next hours, three days).
Location: WTTR_LOCATION from the personal layer, else wttr.in guesses it from your IP. Prints {} when
wttr.in does not answer, and the pill hides itself. Notes today's sunrise and sunset in
~/.cache/theme/sun.json for the automatic light and dark look."""

import datetime as dt
import json
import os
import subprocess
import urllib.parse
import urllib.request

G = chr
SUN, MOON = G(0xF0599), G(0xF0594)
PARTLY, PARTLY_NIGHT = G(0xF0595), G(0xF0F31)
CLOUD, FOG = G(0xF0590), G(0xF0591)
RAIN, POUR = G(0xF0597), G(0xF0596)
SLEET, SNOW, BLIZZARD = G(0xF067F), G(0xF0598), G(0xF0F36)
THUNDER = G(0xF067E)
# wttr.in's (WWO) weather codes
CODES = {
    113: "clear", 116: "partly", 119: "cloud", 122: "cloud",
    143: "fog", 248: "fog", 260: "fog",
    176: "rain", 263: "rain", 266: "rain", 293: "rain", 296: "rain", 353: "rain",
    299: "pour", 302: "pour", 305: "pour", 308: "pour", 356: "pour", 359: "pour",
    179: "sleet", 182: "sleet", 185: "sleet", 281: "sleet", 284: "sleet", 311: "sleet", 314: "sleet",
    317: "sleet", 350: "sleet", 362: "sleet", 365: "sleet", 374: "sleet", 377: "sleet",
    227: "blizzard", 230: "blizzard",
    323: "snow", 326: "snow", 329: "snow", 332: "snow", 335: "snow", 338: "snow", 368: "snow",
    371: "snow", 392: "snow", 395: "snow",
    200: "thunder", 386: "thunder", 389: "thunder",
}  # fmt: skip
GLYPHS = {
    "clear": (SUN, MOON), "partly": (PARTLY, PARTLY_NIGHT), "cloud": (CLOUD, CLOUD), "fog": (FOG, FOG),
    "rain": (RAIN, RAIN), "pour": (POUR, POUR), "sleet": (SLEET, SLEET), "blizzard": (BLIZZARD, BLIZZARD),
    "snow": (SNOW, SNOW), "thunder": (THUNDER, THUNDER),
}  # fmt: skip


def location():
    """WTTR_LOCATION from personal/config (a shell file), else the environment."""
    path = os.path.expanduser("~/.config/driftless/personal/config")
    if os.path.isfile(path):
        out = subprocess.run(
            ["bash", "-c", 'source "$1" >/dev/null 2>&1; printf %s "$WTTR_LOCATION"', "_", path],
            capture_output=True,
            text=True,
            check=False,
        ).stdout.strip()
        if out:
            return out
    return os.environ.get("WTTR_LOCATION", "")


def glyph(code, night=False):
    return GLYPHS.get(CODES.get(int(code), "cloud"), (CLOUD, CLOUD))[1 if night else 0]


def clock(text):
    """wttr's "07:24 AM" as a time."""
    return dt.datetime.strptime(text.strip(), "%I:%M %p").time()


def note_sun(sunrise, sunset):
    """Today's sunrise and sunset for the automatic look (theme/apply.py --follow-sun)."""
    path = os.path.expanduser("~/.cache/theme/sun.json")
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path + ".tmp", "w") as out:
            json.dump({"sunrise": f"{sunrise:%H:%M}", "sunset": f"{sunset:%H:%M}"}, out)
        os.replace(path + ".tmp", path)
    except OSError:
        pass


def main():
    url = "https://wttr.in/" + urllib.parse.quote(location().replace(" ", "+"), safe="+,") + "?format=j1"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "curl/8"})
        data = json.load(urllib.request.urlopen(req, timeout=10))
        now_c = data["current_condition"][0]
        days = data["weather"]
    except Exception:
        print("{}")
        return
    now = dt.datetime.now()
    try:
        astro = days[0]["astronomy"][0]
        sunrise, sunset = clock(astro["sunrise"]), clock(astro["sunset"])
        night = not (sunrise <= now.time() <= sunset)
        note_sun(sunrise, sunset)
    except (KeyError, ValueError, IndexError):
        night = not 7 <= now.hour < 19
    area = (data.get("nearest_area") or [{}])[0].get("areaName", [{}])[0].get("value", "")

    hours = []
    for day in days[:2]:
        date = dt.date.fromisoformat(day["date"])
        for h in day["hourly"]:
            at = dt.datetime.combine(date, dt.time(int(h["time"]) // 100))
            if at > now and len(hours) < 6:
                hours.append(
                    {
                        "time": f"{at:%H:%M}",
                        "icon": glyph(h["weatherCode"], not 7 <= at.hour < 19),
                        "temp": int(h["tempC"]),
                        "rain": int(h.get("chanceofrain", 0)),
                    }
                )
    labels = ["Today", "Tomorrow"]
    out_days = []
    for i, day in enumerate(days[:3]):
        date = dt.date.fromisoformat(day["date"])
        midday = next((h for h in day["hourly"] if h["time"] == "1200"), day["hourly"][len(day["hourly"]) // 2])
        out_days.append(
            {
                "label": labels[i] if i < len(labels) else f"{date:%A}",
                "icon": glyph(midday["weatherCode"]),
                "max": int(day["maxtempC"]),
                "min": int(day["mintempC"]),
                "rain": max(int(h.get("chanceofrain", 0)) for h in day["hourly"]),
            }
        )
    print(
        json.dumps(
            {
                "icon": glyph(now_c["weatherCode"], night),
                "temp": int(now_c["temp_C"]),
                "feels": int(now_c["FeelsLikeC"]),
                "desc": now_c["weatherDesc"][0]["value"].strip(),
                "humidity": int(now_c["humidity"]),
                "wind": f"{now_c['windspeedKmph']} km/h {now_c['winddir16Point']}",
                "place": area,
                "hours": hours,
                "days": out_days,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
