#!/usr/bin/env python3
"""Waybar: state of the rebuild kit sync (auto-snapshot.sh), next to the package updates.
Bar text: icon, plus what waits (incoming GitHub commits, unpushed local ones). Tooltip: mode, last run,
who wrote to GitHub last, what the incoming commits would change (files, new packages) and the last
change seen from every machine. Only local reads (git refs, ~/.local/state/rebuild); the network is
touched by the sync run or by "Check GitHub" in sync-menu.sh. Refreshed by signal 11."""

import fcntl
import json
import os
import re
import subprocess
import time
from html import escape

HOME = os.path.expanduser("~")
REPO = HOME + "/rebuild"
STATE = os.environ.get("XDG_STATE_HOME", HOME + "/.local/state") + "/rebuild"
# GitHub logo, so it never reads as the "recheck updates" arrows next to it; the state shows as
# colour plus a small mark behind it (pause while off, alert after a failed run)
ICON = "\U000f02a4"  # 󰊤
MARK = {"off": " \U000f03e4", "error": " \U000f0026"}  # 󰏤 󰀦
MODE_NAME = {"auto": "automatic", "review": "review first", "off": "off"}
RESULT_NAME = {
    "ok": "ok",
    "offline": "GitHub not reachable",
    "held": "held back for review",
    "paused": "switched off",
    "conflict": "merge conflict, fix by hand",
    "push failed": "push failed",
    "failed": "failed, see the log",
    "joining": "a new machine waits for your trust",
    "untrusted": "GitHub has commits none of your machines signed",
}


def git(*args):
    proc = subprocess.run(["git", "-C", REPO, *args], capture_output=True, text=True)
    return proc.stdout.strip() if proc.returncode == 0 else ""


def read(name, default=""):
    try:
        return open(f"{STATE}/{name}").read().strip() or default
    except OSError:
        return default


def ago(timestamp):
    secs = max(int(time.time() - timestamp), 0)
    if secs < 60:
        return "just now"
    if secs < 3600:
        return f"{secs // 60}m ago"
    if secs < 86400:
        return f"{secs // 3600}h ago"
    return f"{secs // 86400}d ago"


def running():
    try:
        with open(STATE + "/lock") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return False
    except BlockingIOError:
        return True
    except OSError:
        return False


def snapshot_host(subject):
    """The machine an automatic snapshot commit came from, or None for a commit made by hand."""
    match = re.match(r"Automatic snapshot (?!\d{4}-)(\S+) ", subject)
    return match.group(1) if match else None


def who(subject, author):
    return snapshot_host(subject) or f"{author} (by hand)"


def incoming_lines(incoming, mode):
    """Tooltip lines about the commits on GitHub this machine has not taken over yet."""
    lines = [
        "",
        f"<b>↓ {incoming} incoming</b> (not applied yet)" if mode != "auto" else f"<b>↓ {incoming} incoming</b>",
    ]
    for entry in git("log", "-6", "--format=%ct%x1f%an%x1f%s", "HEAD..origin/main").splitlines():
        timestamp, author, subject = entry.split("\x1f")
        short = re.sub(r"^Automatic snapshot (\S+ )?\S+$", "snapshot", subject)
        lines.append(f"  {escape(who(subject, author))}  ·  {ago(int(timestamp))}  ·  {escape(short[:60])}")
    if incoming > 6:
        lines.append(f"  … {incoming - 6} more")
    files = git("diff", "--name-only", "HEAD...origin/main", "--", "files").splitlines()
    if files:
        areas = sorted({re.sub(r"^files/(home/\.config/|home/)?", "", path).split("/")[0] for path in files})
        lines.append(f"  {len(files)} file(s): {escape(', '.join(areas[:8]))}" + (" …" if len(areas) > 8 else ""))
    diff = git("diff", "--no-color", "-U0", "HEAD...origin/main", "--", "packages/pacman.txt", "packages/aur.txt")
    new_packages = [row[1:] for row in diff.splitlines() if row.startswith("+") and not row.startswith("+++")]
    if new_packages:
        lines.append(
            f"  <span color='#ffb454'>new packages: {escape(', '.join(new_packages[:10]))}"
            + (" …" if len(new_packages) > 10 else "")
            + "</span>"
        )
    return lines


def untrusted_lines(untrusted):
    """Tooltip lines about incoming commits no trusted machine signed (lib/signing.sh check)."""
    # each entry: commit, signature status (%G?), key fingerprint, host from signers/ ("-" if none)
    joining = sorted({host for _, status, _, host in untrusted if status == "U" and host != "-"})
    foreign = [entry for entry in untrusted if entry[1] != "U" or entry[3] == "-"]
    lines = [""]
    if joining:
        lines.append(
            f"<span color='#ffb454'><b>New machine: {escape(', '.join(joining))}</b></span> (menu: Trust new machine)"
        )
    if foreign:
        lines.append(
            f"<span color='#ff6b6b'><b>{len(foreign)} commit(s) on GitHub not signed by your machines</b></span>"
            ", nothing taken over"
        )
    return lines


def last_change_per_machine(has_origin):
    """Tooltip lines: when each machine last sent an automatic snapshot."""
    last_seen = {}
    for entry in git("log", "-300", "--format=%ct%x1f%s", "origin/main" if has_origin else "HEAD").splitlines():
        timestamp, subject = entry.split("\x1f", 1)
        host = snapshot_host(subject)
        if host and host not in last_seen:
            last_seen[host] = int(timestamp)
    if not last_seen:
        return []
    newest_first = sorted(last_seen.items(), key=lambda item: -item[1])
    return ["", "Last change per machine:"] + [f"  {escape(host)}: {ago(ts)}" for host, ts in newest_first]


def main():
    if not os.path.isdir(REPO + "/.git"):
        print('{"text":"","class":"none","tooltip":false}')
        return
    mode = read("mode", "review")
    installs = read("installs", "on")
    status = dict(line.split("=", 1) for line in read("status").splitlines() if "=" in line)
    has_origin = bool(git("rev-parse", "-q", "--verify", "origin/main"))
    incoming = int(git("rev-list", "--count", "HEAD..origin/main") or 0) if has_origin else 0
    outgoing = int(git("rev-list", "--count", "origin/main..HEAD") or 0) if has_origin else 0
    result, busy = status.get("result", ""), running()
    waiting = [row.split()[1] for row in read("install-pending").splitlines() if len(row.split()) == 2]
    untrusted = [row.split() for row in read("untrusted").splitlines() if len(row.split()) == 4]
    conflict = read("conflict").split() if result == "conflict" else []
    signing = os.path.exists(STATE + "/allowed_signers")

    # bar text + class
    badge = "".join([f" ↓{incoming}" if incoming else "", f" ↑{outgoing}" if outgoing and mode != "auto" else ""])
    if busy:
        state = "running"
    elif result in ("conflict", "failed", "push failed", "untrusted"):
        state = "error"
    elif mode == "off":
        state = "off"
    elif (incoming and mode == "review") or waiting or result == "joining":
        state = "pending"
    else:
        state = "ok"
    icon = ICON + MARK.get(state, "")

    tooltip = [f"<b>Kit sync</b>  ·  {MODE_NAME.get(mode, mode)}" + ("" if installs == "on" else "  ·  installs off")]
    if busy:
        tooltip.append("Running right now …")
    if "time" in status:
        tooltip.append(
            f"Last run {ago(int(status['time']))}: {RESULT_NAME.get(result, result)}"
            + (f", {status['applied']} change(s) taken over" if status.get("applied", "0") != "0" else "")
        )
    last = git("log", "-1", "--format=%an%x1f%ct%x1f%s", "origin/main").split("\x1f") if has_origin else []
    if len(last) == 3:
        author, timestamp, subject = last
        tooltip.append(f"GitHub last written by <b>{escape(who(subject, author))}</b>, {ago(int(timestamp))}")
    if incoming:
        tooltip += incoming_lines(incoming, mode)
    if outgoing:
        tooltip.append(f"↑ {outgoing} local commit(s) not on GitHub yet")
    if conflict:
        tooltip += [
            "",
            f"<span color='#ff6b6b'><b>Changed here and on GitHub:</b></span> {escape(', '.join(conflict))}",
            f"  nothing taken over; merge by hand: cd {escape(REPO)} &amp;&amp; git merge origin/main",
        ]
    if untrusted:
        tooltip += untrusted_lines(untrusted)
    elif not signing:
        tooltip.append("Commit signatures not checked here (lib/signing.sh setup)")
    if waiting:
        tooltip += [
            "",
            f"<span color='#ffb454'><b>{len(waiting)} listed package(s) wait for install</b></span>"
            " (menu: Install missing packages)",
            f"  {escape(', '.join(waiting[:10]))}" + (" …" if len(waiting) > 10 else ""),
        ]
    tooltip += last_change_per_machine(has_origin)
    tooltip += ["", "Click: menu  ·  Right: sync now  ·  Middle: pause / resume"]

    print(json.dumps({"text": icon + badge, "class": state, "tooltip": "\n".join(tooltip)}))


if __name__ == "__main__":
    main()
