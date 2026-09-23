#!/usr/bin/env python3
"""Waybar: state of the rebuild kit sync (auto-snapshot.sh), next to the package updates.
Bar text: icon, plus what waits (incoming GitHub commits, unpushed local ones). Tooltip: mode, last run,
who wrote to GitHub last, what the incoming commits would change (files, new packages) and the last
change seen from every machine. Only local reads (git refs, ~/.local/state/rebuild); the network is
touched by the sync run or by "Check GitHub" in sync-menu.sh. Refreshed by signal 11."""
import fcntl, html, json, os, re, subprocess, sys, time

HOME = os.path.expanduser("~")
REPO = HOME + "/rebuild"
STATE = os.environ.get("XDG_STATE_HOME", HOME + "/.local/state") + "/rebuild"
# GitHub logo, so it never reads as the "recheck updates" arrows next to it; the state shows as
# colour plus a small mark behind it (pause while off, alert after a failed run)
ICON = "\U000f02a4"  # 󰊤
MARK = {"off": " \U000f03e4", "error": " \U000f0026"}  # 󰏤 󰀦
MODE_NAME = {"auto": "automatic", "review": "review first", "off": "off"}
RESULT_NAME = {"ok": "ok", "offline": "GitHub not reachable", "held": "held back for review",
               "paused": "switched off", "conflict": "merge conflict, fix by hand",
               "push failed": "push failed", "failed": "failed, see the log"}

def git(*args):
    r = subprocess.run(["git", "-C", REPO, *args], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""

def read(name, default=""):
    try: return open(f"{STATE}/{name}").read().strip() or default
    except OSError: return default

def ago(ts):
    s = max(int(time.time() - ts), 0)
    return "just now" if s < 60 else f"{s // 60}m ago" if s < 3600 else f"{s // 3600}h ago" if s < 86400 else f"{s // 86400}d ago"

def running():
    try:
        with open(STATE + "/lock") as f:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return False
    except BlockingIOError: return True
    except OSError: return False

def who(subject, author):
    m = re.match(r"Automatic snapshot (?!\d{4}-)(\S+) ", subject)
    return m.group(1) if m else f"{author} (by hand)"

def main():
    if not os.path.isdir(REPO + "/.git"):
        print('{"text":"","class":"none","tooltip":false}'); return
    mode = read("mode", "auto"); installs = read("installs", "on")
    status = dict(l.split("=", 1) for l in read("status").splitlines() if "=" in l)
    has_origin = bool(git("rev-parse", "-q", "--verify", "origin/main"))
    incoming = int(git("rev-list", "--count", "HEAD..origin/main") or 0) if has_origin else 0
    outgoing = int(git("rev-list", "--count", "origin/main..HEAD") or 0) if has_origin else 0
    result, busy = status.get("result", ""), running()

    # bar text + class
    badge = "".join([f" ↓{incoming}" if incoming else "", f" ↑{outgoing}" if outgoing and mode != "auto" else ""])
    if busy: cls = "running"
    elif result in ("conflict", "failed", "push failed"): cls = "error"
    elif mode == "off": cls = "off"
    elif incoming and mode == "review": cls = "pending"
    else: cls = "ok"
    icon = ICON + MARK.get(cls, "")

    # tooltip
    e = html.escape
    t = [f"<b>Kit sync</b>  ·  {MODE_NAME.get(mode, mode)}" + ("" if installs == "on" else "  ·  installs off")]
    if busy: t.append("Running right now …")
    if "time" in status:
        t.append(f"Last run {ago(int(status['time']))}: {RESULT_NAME.get(result, result)}"
                 + (f", {status['applied']} change(s) taken over" if status.get("applied", "0") != "0" else ""))
    last = git("log", "-1", "--format=%an%x1f%ct%x1f%s", "origin/main").split("\x1f") if has_origin else []
    if len(last) == 3:
        t.append(f"GitHub last written by <b>{e(who(last[2], last[0]))}</b>, {ago(int(last[1]))}")
    if incoming:
        t += ["", f"<b>↓ {incoming} incoming</b> (not applied yet)" if mode != "auto" else f"<b>↓ {incoming} incoming</b>"]
        for line in git("log", "-6", "--format=%ct%x1f%an%x1f%s", "HEAD..origin/main").splitlines():
            ct, an, s = line.split("\x1f")
            short = re.sub(r"^Automatic snapshot (\S+ )?\S+$", "snapshot", s)
            t.append(f"  {e(who(s, an))}  ·  {ago(int(ct))}  ·  {e(short[:60])}")
        if incoming > 6: t.append(f"  … {incoming - 6} more")
        files = git("diff", "--name-only", "HEAD...origin/main", "--", "files").splitlines()
        if files:
            tops = sorted({re.sub(r"^files/(home/\.config/|home/)?", "", f).split("/")[0] for f in files})
            t.append(f"  {len(files)} file(s): {e(', '.join(tops[:8]))}" + (" …" if len(tops) > 8 else ""))
        diff = git("diff", "--no-color", "-U0", "HEAD...origin/main", "--", "packages/pacman.txt", "packages/aur.txt")
        new = [l[1:] for l in diff.splitlines() if l.startswith("+") and not l.startswith("+++")]
        if new:
            t.append(f"  <span color='#ffb454'>new packages: {e(', '.join(new[:10]))}" + (" …" if len(new) > 10 else "") + "</span>")
    if outgoing:
        t.append(f"↑ {outgoing} local commit(s) not on GitHub yet")

    seen = {}
    for line in git("log", "-300", "--format=%ct%x1f%s", "origin/main" if has_origin else "HEAD").splitlines():
        ct, s = line.split("\x1f", 1)
        m = re.match(r"Automatic snapshot (?!\d{4}-)(\S+) ", s)
        if m and m.group(1) not in seen: seen[m.group(1)] = int(ct)
    if seen:
        t += ["", "Last change per machine:"] + [f"  {e(h)}: {ago(ts)}" for h, ts in sorted(seen.items(), key=lambda x: -x[1])]
    t += ["", "Click: menu  ·  Right: sync now  ·  Middle: pause / resume"]

    print(json.dumps({"text": icon + badge, "class": cls, "tooltip": "\n".join(t)}))

if __name__ == "__main__":
    main()
