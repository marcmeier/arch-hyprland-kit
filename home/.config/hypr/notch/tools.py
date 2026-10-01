#!/usr/bin/env python3
"""The tools Claude may use from the bubble (notch.py): one command, so the permission is one rule and
nothing else runs. Every subcommand prints a short result for Claude to word the answer from.

Usage: tools.py timer DURATION LABEL      ring after 10m, 1h30m, 90s ...
       tools.py remind TIME LABEL         ring at HH:MM (today, or tomorrow if past) or YYYY-MM-DD HH:MM
       tools.py timers                    running timers and reminders
       tools.py timer-cancel ID|all
       tools.py weather [PLACE]           now and the next three days (wttr.in; default: WTTR_LOCATION)
       tools.py media [status|play|pause|toggle|next|previous]
       tools.py volume [N|+N|-N|mute|unmute]       percent
       tools.py brightness [N|+N|-N]               percent
       tools.py system                    battery, disk, memory, uptime, network
       tools.py updates                   pending package updates
       tools.py bluetooth [list|connect NAME|disconnect NAME]
       tools.py dnd [on|off]              notifications: do not disturb
       tools.py lock | suspend
       tools.py wallpaper                 a random one from the wallpaper folder
       tools.py screen                    screenshot of the focused monitor; prints the path to Read
       tools.py clipboard [get|set TEXT]
       tools.py paste TEXT                type TEXT into the active window (through the clipboard)
       tools.py note TEXT | notes [N]     add a note / the last N notes (NOTCH_NOTES)
       tools.py files WORD                files in the home whose name contains WORD
       tools.py open URL|PATH
       tools.py app list [WORD] | app open ID
       tools.py calendar list [khal list args] | calendar add START [END|DURATION] TITLE"""

import configparser
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timedelta
from pathlib import Path

HERE = Path(__file__).resolve().parent
RUN = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "claude-notch"
TIMERS = RUN / "timers.json"  # id -> label and time; transient timers end with the session anyway
SOUND = Path("/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga")


def run(*cmd, timeout=10):
    """A command's output (stdout, else stderr), stripped; never raises."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as e:
        return f"failed: {e}"
    return (r.stdout or r.stderr).strip()


def personal(name, default=""):
    """A value from ~/.config/driftless/personal/config (or the environment)."""
    path = Path.home() / ".config/driftless/personal/config"
    if path.is_file():
        out = run("bash", "-c", f'set -a; source "$1" >/dev/null 2>&1; printf %s "${{{name}:-}}"', "_", str(path))
        if out:
            return out
    return os.environ.get(name, default)


# ---- timers and reminders: transient systemd timers that run `notch.py alert` ----


def load_timers():
    try:
        timers = json.loads(TIMERS.read_text())
    except (OSError, ValueError):
        return {}
    return {k: v for k, v in timers.items() if v["at"] > time.time()}


def duration(text):
    """10m, 1h30m, 90s, 1:30 (h:m), 25 (minutes) -> seconds."""
    text = text.strip().lower()
    if m := re.fullmatch(r"(\d+):(\d{2})", text):
        return int(m[1]) * 3600 + int(m[2]) * 60
    if text.isdigit():
        return int(text) * 60
    parts = re.findall(r"(\d+(?:\.\d+)?)\s*(h|std|m|min|s|sek|sec)", text)
    if not parts or "".join(f"{n}{u}" for n, u in parts) != re.sub(r"\s", "", text):
        raise ValueError(f"not a duration: {text}")
    unit = {"h": 3600, "std": 3600, "m": 60, "min": 60, "s": 1, "sek": 1, "sec": 1}
    return int(sum(float(n) * unit[u] for n, u in parts))


def moment(text):
    """HH:MM (today, tomorrow if past) or YYYY-MM-DD HH:MM -> datetime."""
    text = text.strip()
    now = datetime.now()
    for fmt in ("%Y-%m-%d %H:%M", "%Y-%m-%dT%H:%M"):
        try:
            return datetime.strptime(text, fmt)
        except ValueError:
            pass
    if m := re.fullmatch(r"(\d{1,2})[:.](\d{2})", text):
        at = now.replace(hour=int(m[1]), minute=int(m[2]), second=0, microsecond=0)
        return at if at > now else at + timedelta(days=1)
    raise ValueError(f"not a time: {text} (HH:MM or YYYY-MM-DD HH:MM)")


def add_timer(at, label):
    tid = str(int(time.time() * 1000) % 10**8)
    unit = f"notch-alarm-{tid}"
    when = (
        [f"--on-active={max(1, int(at - time.time()))}s"]
        if at - time.time() < 86400
        else [f"--on-calendar={datetime.fromtimestamp(at):%Y-%m-%d %H:%M:%S}"]
    )
    out = subprocess.run(
        ["systemd-run", "--user", f"--unit={unit}", *when, "--timer-property=AccuracySec=1s",
         f"--description=Claude: {label}", "--", str(HERE / "notch.py"), "alert", label],
        capture_output=True, text=True,
    )  # fmt: skip
    if out.returncode:
        return f"failed: {out.stderr.strip()}"
    timers = load_timers()
    timers[tid] = {"label": label, "at": at}
    RUN.mkdir(parents=True, exist_ok=True)
    TIMERS.write_text(json.dumps(timers))
    return f"set (id {tid}): '{label}' rings {datetime.fromtimestamp(at):%A %Y-%m-%d %H:%M:%S}"


def cmd_timer(args):
    return add_timer(time.time() + duration(args[0]), " ".join(args[1:]) or "Timer")


def cmd_remind(args):
    # the time may be two words (date and clock)
    if len(args) > 2 and re.fullmatch(r"\d{4}-\d{2}-\d{2}", args[0]):
        args = [f"{args[0]} {args[1]}", *args[2:]]
    return add_timer(moment(args[0]).timestamp(), " ".join(args[1:]) or "Reminder")


def cmd_timers(_):
    timers = load_timers()
    if not timers:
        return "no timers or reminders"
    lines = []
    for tid, t in sorted(timers.items(), key=lambda kv: kv[1]["at"]):
        left = int(t["at"] - time.time())
        lines.append(
            f"{tid}: '{t['label']}' at {datetime.fromtimestamp(t['at']):%a %H:%M:%S}"
            f" (in {left // 60} min {left % 60} s)"
        )
    return "\n".join(lines)


def cmd_timer_cancel(args):
    timers = load_timers()
    ids = list(timers) if args[:1] == ["all"] else args
    done = []
    for tid in ids:
        run("systemctl", "--user", "stop", f"notch-alarm-{tid}.timer")
        if tid in timers:
            done.append(timers.pop(tid)["label"])
    if TIMERS.exists():
        TIMERS.write_text(json.dumps(timers))
    return f"cancelled: {', '.join(done)}" if done else "no such timer"


# ---- weather ----


def cmd_weather(args):
    place = " ".join(args) or personal("WTTR_LOCATION")
    lang = personal("NOTCH_LANG") or personal("DICTATE_LANG")
    lang = "en" if lang in ("", "auto") else lang
    url = f"https://wttr.in/{urllib.parse.quote(place)}?format=j1&lang={lang}"
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "curl"}), timeout=10) as r:
            w = json.load(r)
    except Exception as e:
        return f"failed: {e}"

    def desc(d):
        return (d.get(f"lang_{lang}") or d.get("weatherDesc") or [{"value": "?"}])[0]["value"]

    cur = w["current_condition"][0]
    area = w.get("nearest_area", [{}])[0]
    where = ", ".join(x[0]["value"] for x in (area.get("areaName"), area.get("country")) if x)
    lines = [
        f"{where} now: {desc(cur)}, {cur['temp_C']} °C (feels {cur['FeelsLikeC']} °C), "
        f"wind {cur['windspeedKmph']} km/h, humidity {cur['humidity']} %"
    ]
    for day in w["weather"]:
        hours = day["hourly"]
        rain = max(int(h.get("chanceofrain", 0)) for h in hours)
        noon = hours[len(hours) // 2]
        lines.append(
            f"{day['date']}: {desc(noon)}, {day['mintempC']} to {day['maxtempC']} °C, rain up to {rain} %, "
            f"sunrise {day['astronomy'][0]['sunrise']}, sunset {day['astronomy'][0]['sunset']}"
        )
    return "\n".join(lines)


# ---- media, sound, light ----


def cmd_media(args):
    action = (args or ["status"])[0]
    if action != "status":
        if action not in ("play", "pause", "toggle", "next", "previous"):
            return f"unknown: {action}"
        run("playerctl", "play-pause" if action == "toggle" else action)
        time.sleep(0.3)
    out = run("playerctl", "metadata", "--format", "{{status}}: {{artist}} - {{title}} ({{playerName}})")
    return out if "No player" not in out else "no media player running"


def cmd_volume(args):
    sink = "@DEFAULT_AUDIO_SINK@"
    if args:
        a = args[0].rstrip("%")
        if a in ("mute", "unmute"):
            run("wpctl", "set-mute", sink, "1" if a == "mute" else "0")
        elif re.fullmatch(r"[+-]?\d+", a):
            value = f"{a[1:]}%{a[0]}" if a[0] in "+-" else f"{a}%"
            run("wpctl", "set-volume", "-l", "1", sink, value)
        else:
            return f"unknown: {a}"
    out = run("wpctl", "get-volume", sink)  # "Volume: 0.60 [MUTED]"
    m = re.search(r"([\d.]+)", out)
    return f"volume {round(float(m[1]) * 100)} %" + (" (muted)" if "MUTED" in out else "") if m else out


def cmd_brightness(args):
    if not shutil.which("brightnessctl") or not run("brightnessctl", "-l", "-c", "backlight").count("backlight"):
        return "no adjustable screen here (external monitors: use their buttons)"
    if args:
        a = args[0].rstrip("%")
        if not re.fullmatch(r"[+-]?\d+", a):
            return f"unknown: {a}"
        value = f"{a[1:]}%{a[0]}" if a[0] in "+-" else f"{a}%"
        run("brightnessctl", "-e4", "-n2", "set", value)
    out = run("brightnessctl", "-m", "-c", "backlight")  # name,class,value,percent,max
    return f"brightness {out.split(',')[3]}" if out.count(",") >= 4 else out


# ---- the system ----


def cmd_system(_):
    lines = []
    for bat in sorted(Path("/sys/class/power_supply").glob("BAT*")):
        cap = (bat / "capacity").read_text().strip()
        lines.append(f"battery {cap} % ({(bat / 'status').read_text().strip().lower()})")
    du = shutil.disk_usage(Path.home())
    lines.append(f"disk: {du.free / 1e9:.0f} GB free of {du.total / 1e9:.0f} GB")
    mem = dict(line.split(":", 1) for line in Path("/proc/meminfo").read_text().splitlines())
    total, avail = (int(mem[k].split()[0]) / 1e6 for k in ("MemTotal", "MemAvailable"))
    lines.append(f"memory: {total - avail:.1f} GB used of {total:.1f} GB")
    up = int(float(Path("/proc/uptime").read_text().split()[0]))
    lines.append(f"up {up // 86400} d {up % 86400 // 3600} h {up % 3600 // 60} min, load {os.getloadavg()[0]:.1f}")
    wifi = [line.split(":", 1)[1] for line in run("nmcli", "-t", "-f", "ACTIVE,SSID", "dev", "wifi").splitlines()
            if line.startswith("yes:")]  # fmt: skip
    ip = re.findall(r"inet (\S+)/", run("ip", "-4", "-o", "addr", "show", "scope", "global"))
    lines.append(f"network: {'wifi ' + wifi[0] if wifi else 'wired or offline'}, IP {', '.join(ip) or 'none'}")
    return "\n".join(lines)


def cmd_updates(_):
    out = run("checkupdates", timeout=40)
    pkgs = [line for line in out.splitlines() if " -> " in line]
    if not pkgs:
        return "the system is up to date (official repositories)"
    return f"{len(pkgs)} updates: " + ", ".join(p.split()[0] for p in pkgs[:15]) + (" ..." if len(pkgs) > 15 else "")


def cmd_bluetooth(args):
    devices = re.findall(r"Device (\S+) (.+)", run("bluetoothctl", "devices", "Paired"))
    action = (args or ["list"])[0]
    if action == "list":
        if not devices:
            return "no paired devices"
        return "\n".join(
            f"{name}: {'connected' if 'Connected: yes' in run('bluetoothctl', 'info', mac) else 'not connected'}"
            for mac, name in devices
        )
    if action not in ("connect", "disconnect") or len(args) < 2:
        return "usage: bluetooth list | connect NAME | disconnect NAME"
    want = " ".join(args[1:]).lower()
    match = [(mac, name) for mac, name in devices if want in name.lower()]
    if not match:
        return f"no paired device matches '{want}': " + ", ".join(n for _, n in devices)
    mac, name = match[0]
    if action == "connect":
        run("bluetoothctl", "power", "on")
    out = run("bluetoothctl", action, mac, timeout=15)
    ok = "Successful" in out or "successful" in out
    return f"{name}: {action}ed" if ok else f"{name}: {action} failed ({out.splitlines()[-1] if out else '?'})"


def shell(*args):
    """A call to the desktop shell (quickshell/shell.qml and its parts) over its IPC."""
    return run("quickshell", "ipc", "-p", str(Path.home() / ".config/quickshell"), "call", *args)


def cmd_dnd(args):
    mode = args[0] if args[:1] in (["on"], ["off"]) else "state"
    if mode == "state":
        state = shell("notifications", "state")
        return "do not disturb " + ("on" if state.endswith("on") else "off")
    return "do not disturb " + shell("notifications", "dnd", mode)


def cmd_lock(_):
    # detached: the fallback (hyprlock) runs until you unlock
    subprocess.Popen(
        [str(Path.home() / ".config/quickshell/scripts/lock")],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    return "locked"


def cmd_suspend(_):
    subprocess.Popen(["bash", "-c", "sleep 4; systemctl suspend"], start_new_session=True)
    return "suspending in a few seconds"


def cmd_wallpaper(_):
    tool = Path.home() / ".local/bin/set-wallpaper"
    if not tool.exists():
        return "set-wallpaper is not installed"
    subprocess.Popen(
        [str(tool), "--random"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True
    )
    return "a new wallpaper is coming in"


# ---- screen, clipboard, typing ----


def cmd_screen(_):
    monitors = json.loads(run("hyprctl", "-j", "monitors") or "[]")
    focused = next((m["name"] for m in monitors if m.get("focused")), None)
    RUN.mkdir(parents=True, exist_ok=True)
    path = RUN / "screen.png"
    # scaled down: enough to read text, far fewer tokens
    out = run("grim", *(["-o", focused] if focused else []), "-s", "0.6", str(path))
    return f"screenshot: {path} (Read it)" if path.exists() and not out else f"failed: {out}"


def cmd_clipboard(args):
    if args[:1] == ["set"]:
        subprocess.run(["wl-copy", "--", " ".join(args[1:])], check=False)
        return "copied to the clipboard"
    out = run("wl-paste", "-n", "-t", "text")
    return out[:4000] if out and "No selection" not in out else "the clipboard holds no text"


def cmd_paste(args):
    spec = importlib.util.spec_from_file_location("dictate", HERE.parent / "dictate.py")
    d = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(d)
    d.paste(" ".join(args))  # through the clipboard, Ctrl+Shift+V in terminals
    return "typed into the active window"


# ---- notes, files, apps, calendar ----


def notes_file():
    configured = personal("NOTCH_NOTES")
    if configured:
        return Path(os.path.expanduser(configured))
    docs = run("xdg-user-dir", "DOCUMENTS") or str(Path.home() / "Documents")
    return Path(docs) / "notes.md"


def cmd_note(args):
    path = notes_file()
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as f:
        f.write(f"- {datetime.now():%Y-%m-%d %H:%M} {' '.join(args)}\n")
    return f"noted in {path}"


def cmd_notes(args):
    path = notes_file()
    if not path.is_file():
        return "no notes yet"
    lines = [line for line in path.read_text().splitlines() if line.strip()]
    return "\n".join(lines[-int(args[0] if args else 10) :])


def cmd_files(args):
    word = " ".join(args)
    if not word:
        return "usage: files WORD"
    if shutil.which("fd"):
        out = run("fd", "-i", "-F", "--max-results", "15", word, str(Path.home()), timeout=8)
    else:
        out = run("find", str(Path.home()), "-not", "-path", "*/.*", "-iname", f"*{word}*", timeout=8)
        out = "\n".join(out.splitlines()[:15])
    return out or f"nothing in the home matches '{word}'"


def cmd_open(args):
    target = " ".join(args)
    subprocess.Popen(["xdg-open", target], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    return f"opened {target}"


def desktop_apps():
    """id -> (name, generic name, keywords); earlier directories win, like the launchers do."""
    dirs = [Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "applications"]
    dirs += [
        Path(d) / "applications" for d in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":")
    ]
    found = {}
    for d in dirs:
        for f in sorted(d.glob("*.desktop")) if d.is_dir() else []:
            if f.stem in found:
                continue
            cp = configparser.RawConfigParser(strict=False, interpolation=None)
            try:
                cp.read(f, encoding="utf-8")
                e = cp["Desktop Entry"]
            except Exception:
                continue
            if e.get("Type") != "Application" or e.get("NoDisplay") == "true" or e.get("Hidden") == "true":
                found[f.stem] = None  # hidden here hides it everywhere
                continue
            found[f.stem] = (e.get("Name", f.stem), e.get("GenericName", ""), e.get("Keywords", ""))
    return {k: v for k, v in found.items() if v}


def cmd_app(args):
    apps = desktop_apps()
    if args[:1] == ["open"] and len(args) == 2:
        if args[1] not in apps:
            return f"unknown app id: {args[1]} (see: app list)"
        subprocess.Popen(
            ["uwsm", "app", "--", f"{args[1]}.desktop"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        return f"started {apps[args[1]][0]}"
    q = " ".join(args[1:]).lower()
    lines = [
        f"{app_id}  {name}" + (f" ({generic})" if generic else "")
        for app_id, (name, generic, keywords) in sorted(apps.items(), key=lambda kv: kv[1][0].lower())
        if not q or q in f"{app_id} {name} {generic} {keywords}".lower()
    ]
    return "\n".join(lines) or f"no app matches '{q}'"


def cmd_calendar(args):
    if not shutil.which("khal"):
        return "no calendar here (khal is not installed)"
    if args[:1] == ["add"] and len(args) >= 3:
        out = run("khal", "new", *args[1:])
        if shutil.which("vdirsyncer"):  # to the server now, not at the next timer
            subprocess.Popen(["systemctl", "--user", "start", "--no-block", "vdirsyncer.service"])
        return out or "added"
    return run("khal", "list", *(args[1:] if args[:1] == ["list"] else args or ["today", "1d"])) or "nothing"


COMMANDS = {
    "timer": cmd_timer,
    "remind": cmd_remind,
    "timers": cmd_timers,
    "timer-cancel": cmd_timer_cancel,
    "weather": cmd_weather,
    "media": cmd_media,
    "volume": cmd_volume,
    "brightness": cmd_brightness,
    "system": cmd_system,
    "updates": cmd_updates,
    "bluetooth": cmd_bluetooth,
    "dnd": cmd_dnd,
    "lock": cmd_lock,
    "suspend": cmd_suspend,
    "wallpaper": cmd_wallpaper,
    "screen": cmd_screen,
    "clipboard": cmd_clipboard,
    "paste": cmd_paste,
    "note": cmd_note,
    "notes": cmd_notes,
    "files": cmd_files,
    "open": cmd_open,
    "app": cmd_app,
    "calendar": cmd_calendar,
}


def main():
    args = sys.argv[1:]
    if not args or args[0] not in COMMANDS:
        sys.exit(__doc__)
    try:
        print(COMMANDS[args[0]](args[1:]))
    except (ValueError, IndexError, OSError) as e:
        print(f"failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
