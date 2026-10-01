#!/usr/bin/env python3
"""Ask Claude by voice: a bubble at the top of the screen listens, shows the answer and speaks it.

One key does both (hyprland.lua, SUPER + A): tap it to start and tap again to stop, or hold it and
let go to stop (push-to-talk). whisper.cpp transcribes the recording (dictate.py's setup next door),
`claude -p` answers with tools.py (timers, calendar, weather, media, volume, the screen, the
clipboard, notes, apps, ...) and web search as the only things it may use, and the answer streams
into the bubble of the desktop shell (~/.config/quickshell/notch/Notch.qml). Piper speaks it sentence
by sentence while it arrives (speak.py); a new question or a click on the bubble stops it. A question
within FOLLOW_UP seconds of the last answer continues that conversation.

Usage: notch.py down|up       key pressed / released (the Hyprland binds)
       notch.py toggle        start or stop
       notch.py cancel        stop recording, answering and speaking, hide the bubble
       notch.py ask "<text>"  skip the microphone (for testing)
       notch.py alert LABEL   a timer rings (run by the systemd timers of tools.py)

Settings (optional, personal/config or the environment): NOTCH_MODEL (Claude model, default haiku),
NOTCH_LANG (Whisper language, default DICTATE_LANG, else auto), NOTCH_VOICE (Piper voice, "name" or
"name:speaker", default de_DE-thorsten-high for German, en_US-lessac-high otherwise; "off": silent).
Piper is installed into its own venv (~/.local/share/claude-notch/venv) and the voice into
~/.local/share/piper on first use; until then the answers are shown without a voice."""

import array
import fcntl
import importlib.util
import json
import math
import os
import re
import shutil
import signal
import struct
import subprocess
import sys
import time
import wave
from pathlib import Path

HERE = Path(__file__).resolve().parent
SHELL = Path.home() / ".config/quickshell"  # the desktop shell (driftless-shell.service) draws the bubble
RUN = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "claude-notch"
STATE = RUN / "state.json"
LAST = RUN / "last.json"  # session of the last answer, for follow-up questions
AUDIO = RUN / "audio.wav"
SPEAKER = RUN / "speaker.pid"
DATA = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
VENV = DATA / "claude-notch/venv"  # Piper (piper-tts from PyPI)
VOICES = DATA / "piper"
# claude's working directory: keeps these sessions apart from your projects
WORKSPACE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "claude-notch"
HOLD = 0.5  # held longer than this (seconds): push-to-talk, shorter: toggle
FOLLOW_UP = 120
SENTENCE = re.compile(r"(.+?[.!?:])(?:\s+|$)", re.S)  # a finished sentence at the start of the text


def settings():
    """NOTCH_* and DICTATE_LANG from the environment, personal/config winning (as for dictate.py)."""

    def wanted(key):
        return key.startswith("NOTCH_") or key == "DICTATE_LANG"

    cfg = {k: v for k, v in os.environ.items() if wanted(k)}
    path = Path.home() / ".config/driftless/personal/config"
    if path.is_file():
        out = subprocess.run(
            ["bash", "-c", 'set -a; source "$1" >/dev/null 2>&1; env -0', "_", str(path)],
            capture_output=True,
            text=True,
            check=False,
        ).stdout
        cfg.update(kv.split("=", 1) for kv in out.split("\0") if wanted(kv.partition("=")[0]))
    return cfg


CFG = settings()
MODEL = CFG.get("NOTCH_MODEL") or "haiku"
LANG = CFG.get("NOTCH_LANG") or CFG.get("DICTATE_LANG") or "auto"
VOICE = CFG.get("NOTCH_VOICE") or ("de_DE-thorsten-high" if LANG == "de" else "en_US-lessac-high")


def dictate():
    """dictate.py as a module: its Whisper settings, models and hallucination filter."""
    spec = importlib.util.spec_from_file_location("dictate", HERE.parent / "dictate.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.AUDIO = AUDIO
    return mod


def notify(text, urgency="normal"):
    subprocess.run(["notify-send", "-a", "Claude", "-u", urgency, "-t", "6000", "Claude", text], check=False)


# ---- the bubble (Quickshell IPC) ----


def ensure_shell():
    def up():
        return subprocess.run(["quickshell", "ipc", "-p", str(SHELL), "show"], capture_output=True).returncode == 0

    if up():
        return
    # normally it runs as a service; started any other way, start it like that
    if subprocess.run(["systemctl", "--user", "start", "driftless-shell.service"], capture_output=True).returncode:
        subprocess.run(["quickshell", "-p", str(SHELL), "-d"], capture_output=True)
    for _ in range(60):
        if up():
            time.sleep(0.15)  # the IpcHandler needs a moment after the config loads
            return
        time.sleep(0.05)


def bubble(*args, wait=True):
    cmd = ["quickshell", "ipc", "-p", str(SHELL), "call", "notch", *map(str, args)]
    if wait:
        subprocess.run(cmd, capture_output=True)
    else:
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


# ---- state: idle (no file) | recording | busy, changed under a lock (down and up race) ----


class Locked:
    def __enter__(self):
        RUN.mkdir(parents=True, exist_ok=True)
        self.fd = open(RUN / "lock", "w")
        fcntl.flock(self.fd, fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc):
        self.fd.close()


def alive(pid):
    return bool(pid) and Path(f"/proc/{pid}").exists()


def read_state():
    try:
        st = json.loads(STATE.read_text())
    except (OSError, ValueError):
        return {}
    return st if alive(st.get("pid")) else {}  # a crashed run must not leave the key dead


def write_state(st):
    if st:
        STATE.write_text(json.dumps(st))
    else:
        STATE.unlink(missing_ok=True)


def log(msg):
    """What happened, in RAM ($XDG_RUNTIME_DIR/claude-notch/log), the last 200 lines."""
    RUN.mkdir(parents=True, exist_ok=True)
    path = RUN / "log"
    lines = path.read_text().splitlines()[-199:] if path.is_file() else []
    lines.append(f"{time.strftime('%T')} [{os.getpid()}] {msg}")
    path.write_text("\n".join(lines) + "\n")


# ---- recording: pw-record -> WAV, the level goes to the bubble's bars ----


def start():
    silence()  # a new question interrupts the last answer
    ensure_shell()
    bubble("listening")
    rec = subprocess.Popen(
        [sys.executable, __file__, "rec"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    write_state({"state": "recording", "pid": rec.pid, "since": time.monotonic()})


def cmd_rec():
    """The recorder process: raw PCM from pw-record into the WAV file until SIGINT/SIGTERM."""
    stop = False

    def on_signal(*_):
        nonlocal stop
        stop = True

    signal.signal(signal.SIGINT, on_signal)
    signal.signal(signal.SIGTERM, on_signal)
    AUDIO.unlink(missing_ok=True)
    pw = subprocess.Popen(
        ["pw-record", "--rate", "16000", "--channels", "1", "--format", "s16", "--raw", "-"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    sent = 0.0
    with wave.open(str(AUDIO), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(16000)
        while not stop:
            chunk = pw.stdout.read(1600)  # 50 ms
            if not chunk:
                break
            wav.writeframes(chunk)
            now = time.monotonic()
            if now - sent > 0.08:
                sent = now
                n = len(chunk) // 2
                samples = struct.unpack(f"<{n}h", chunk[: n * 2])
                rms = math.sqrt(sum(s * s for s in samples) / max(n, 1)) / 32768
                db = 20 * math.log10(max(rms, 1e-6))
                bubble("setLevel", f"{max(0.0, min(1.0, (db + 52) / 36)):.2f}", wait=False)
    pw.terminate()
    pw.wait()


def stop_recorder(st):
    try:
        os.kill(st["pid"], signal.SIGTERM)
    except (KeyError, ProcessLookupError):
        return
    for _ in range(100):
        if not alive(st["pid"]):
            return
        time.sleep(0.02)


# ---- speaking (speak.py with Piper, in its own venv) ----


def voice_ready():
    """Piper and the voice are there; if not, they are installed in the background (once)."""
    if (VENV / "bin/python").exists() and (VOICES / f"{VOICE.partition(':')[0]}.onnx").exists():
        return True
    subprocess.Popen(
        [sys.executable, __file__, "setup"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    return False


def cmd_setup():
    """Install Piper into the venv and download the voice; one run at a time."""
    RUN.mkdir(parents=True, exist_ok=True)
    with open(RUN / "setup.lock", "w") as fd:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return  # already running
        name = VOICE.partition(":")[0]
        notify(f"Installing Piper and the voice {name} (once); until then the answers are not spoken")
        try:
            python = VENV / "bin/python"
            if not python.exists():
                shutil.rmtree(VENV, ignore_errors=True)
                subprocess.run([sys.executable, "-m", "venv", str(VENV)], check=True, capture_output=True)
                subprocess.run([python, "-m", "pip", "install", "-q", "piper-tts"], check=True, capture_output=True)
            if not (VOICES / f"{name}.onnx").exists():
                VOICES.mkdir(parents=True, exist_ok=True)
                subprocess.run(
                    [python, "-m", "piper.download_voices", "--download-dir", str(VOICES), name],
                    check=True,
                    capture_output=True,
                )
            notify("The voice is ready")
            log(f"setup: Piper and {name} installed")
        except subprocess.CalledProcessError as e:
            err = (e.stderr or b"").decode(errors="replace").strip()[-300:]
            log(f"setup failed: {err}")
            notify(f"Installing the voice failed: {err}", "critical")


def silence():
    """Stop an answer that is still being spoken."""
    try:
        pid = int(SPEAKER.read_text())
        if "speak.py" in Path(f"/proc/{pid}/cmdline").read_text():  # not a reused pid
            os.killpg(pid, signal.SIGTERM)
    except (OSError, ValueError):
        pass
    SPEAKER.unlink(missing_ok=True)


class Speaker:
    """Gets the answer as it streams in and hands speak.py one finished sentence at a time."""

    def __init__(self):
        self.proc, self.buf = None, ""
        if VOICE == "off" or not voice_ready():
            return
        silence()
        self.proc = subprocess.Popen(
            [str(VENV / "bin/python"), str(HERE / "speak.py"), VOICE],
            stdin=subprocess.PIPE,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            text=True,
            start_new_session=True,
        )
        SPEAKER.write_text(str(self.proc.pid))

    def say(self, line):
        if self.proc and line.strip():
            try:
                self.proc.stdin.write(" ".join(line.split()) + "\n")
                self.proc.stdin.flush()
            except OSError:  # stopped meanwhile
                self.proc = None

    def feed(self, text):
        self.buf += text
        while m := SENTENCE.match(self.buf):
            if m.end() == len(self.buf) and not self.buf[-1].isspace():
                break  # "16:" or "e.g." may go on: wait for what follows
            self.say(m.group(1))
            self.buf = self.buf[m.end() :]

    def done(self):
        """Speak the rest; speak.py ends by itself once it has said everything."""
        self.say(self.buf)
        self.buf = ""
        if self.proc:
            try:
                self.proc.stdin.close()
            except OSError:
                pass

    def stop(self):
        if self.proc:
            silence()
            self.proc = None


# ---- asking Claude ----

PROMPT = """You are Claude, a voice assistant in a small bubble at the top of the user's desktop (Arch \
Linux, Hyprland), like Siri or Alexa on a computer. The question comes from speech recognition and may \
contain recognition errors: take the obvious meaning.

Answer in the language of the question, briefly: usually one or two sentences, at most about 60 words \
(a summary of the screen or the clipboard up to 100). Plain text without Markdown (no backticks, \
asterisks, bullets, headings or URLs): it is shown as it is and read aloud. No opener like "Sure", and \
no questions back unless it cannot be done without. When you did something, confirm it in a few words \
("Timer set for 10 minutes.", "Firefox is open.").

It is now {now}.

Act with `{tools} <command>` (Bash; nothing else runs). Use it whenever it helps, without asking:
- timer DURATION LABEL (10m, 1h30m, 90s) | remind TIME LABEL (HH:MM or YYYY-MM-DD HH:MM) | timers | \
timer-cancel ID|all. Alarms, egg timers, "remind me at 3 to call Anna" (LABEL in the user's language, \
it is shown and spoken when it rings). Days ahead: better a calendar event.
- calendar list [khal list args, e.g. today 1d | tomorrow 1d | 2026-10-05 7d] | calendar add START \
[END|DURATION] TITLE (khal new syntax: "2026-10-05 15:00 16:00 Dentist", "tomorrow 9:00 1h Call"). \
All-day entries have no time. Name events with time and title.
- weather [PLACE] (default: home): now and three days
- media status|play|pause|toggle|next|previous; volume [N|+N|-N|mute|unmute]; brightness [N|+N|-N]
- system (battery, disk, memory, uptime, network) | updates | bluetooth list|connect NAME|disconnect NAME
- dnd on|off (do not disturb) | lock | suspend | wallpaper (a new random one)
- screen: a screenshot of the user's monitor; then Read the path it prints to see it ("what is on my \
screen", "summarise this article", "translate this", "what does this error mean")
- clipboard get | clipboard set TEXT; paste TEXT (types TEXT into the active window: "write a polite \
reply saying ...", "insert ..."; write the text itself, not a description)
- note TEXT | notes [N] (the user's notes file)
- files WORD (find files by name) | open URL|PATH (web pages, searches, files, folders)
- app list [WORD] | app open ID (start programs; list first to get the id)
For current facts use WebSearch or WebFetch. Arithmetic, conversions, translations and general \
knowledge: answer directly. If something cannot be done, say so in one sentence."""


def claude_cmd(question, resume):
    tools = HERE / "tools.py"
    prompt = PROMPT.format(now=time.strftime("%A, %Y-%m-%d, %H:%M"), tools=tools)
    # the screenshot is the only file Claude may read; "//" is an absolute path in permission rules
    allowed = [f"Bash({tools}:*)", f"Read(/{RUN}/**)", "WebSearch", "WebFetch"]
    cmd = ["claude", "-p", question, "--model", MODEL]
    cmd += ["--output-format", "stream-json", "--verbose", "--include-partial-messages"]
    cmd += ["--append-system-prompt", prompt, "--tools", "Bash,Read,WebSearch,WebFetch"]
    # only these run, without asking; the user's settings (and their wider allow rules) stay out
    cmd += ["--permission-mode", "dontAsk", "--setting-sources", "project", "--allowedTools", *allowed]
    if resume:
        cmd += ["--resume", resume]
    return cmd


def follow_up_session():
    try:
        last = json.loads(LAST.read_text())
    except (OSError, ValueError):
        return None
    return last.get("session") if time.time() - last.get("at", 0) < FOLLOW_UP else None


def ask(question):
    """Run claude and stream its answer into the bubble; returns when it is done."""
    bubble("think", question)
    speaker = Speaker()  # loads the voice while Claude thinks
    WORKSPACE.mkdir(parents=True, exist_ok=True)
    resume = follow_up_session()
    log(f"ask {question!r} (resume {resume})")
    proc = subprocess.Popen(
        claude_cmd(question, resume),
        cwd=WORKSPACE,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    with Locked():
        st = read_state()
        st["claude"] = proc.pid
        write_state(st)

    buf, pending, sent, answering, result = "", "", 0.0, False, None

    def flush():
        nonlocal pending, sent
        if pending:
            bubble("append", pending)
            pending, sent = "", time.monotonic()

    for line in proc.stdout:
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        if msg.get("type") == "stream_event":
            ev = msg.get("event", {})
            block = ev.get("content_block", {})
            if ev.get("type") == "content_block_start" and block.get("type") == "tool_use":
                # text before a tool call ("Let me check ...") is not the answer
                if answering:
                    bubble("think", question)
                buf, pending, answering = "", "", False
                speaker.say(speaker.buf)  # said aloud anyway: "Let me check" sounds natural
                speaker.buf = ""
                log(f"tool {block.get('name')}")
            elif ev.get("type") == "content_block_delta" and ev.get("delta", {}).get("type") == "text_delta":
                text = ev["delta"]["text"].replace("`", "").replace("*", "")  # the bubble shows plain text
                if not answering:
                    text = text.lstrip()
                    if not text:
                        continue
                    answering = True
                buf += text
                pending += text
                speaker.feed(text)
                if time.monotonic() - sent > 0.1:
                    flush()
        elif msg.get("type") == "result":
            result = msg
    flush()
    proc.wait()

    if (RUN / "cancelled").exists():
        speaker.stop()
        return
    if result and not result.get("is_error"):
        LAST.write_text(json.dumps({"session": result.get("session_id"), "at": time.time()}))
        final = (result.get("result") or "").strip()
        if not buf.strip():
            bubble("answer", final or "Done.")
            speaker.feed(final)
        speaker.done()
        log(f"answer {buf.strip()!r}")
    else:
        err = (result or {}).get("result") or proc.stderr.read().strip()[-300:] or f"claude exit {proc.returncode}"
        log(f"error {err}")
        speaker.stop()
        bubble("error", err)


def transcribe(d, cfg):
    """dictate.py's Whisper call, but with the encoder window cut to the recording: Whisper encodes
    30 s otherwise, which takes about three times as long for a short question."""
    if not AUDIO.is_file() or AUDIO.stat().st_size < 16000:  # under half a second
        return ""
    seconds = (AUDIO.stat().st_size - 44) / 32000
    ctx = min(1500, max(512, math.ceil((seconds + 1) * 50 / 64) * 64))  # 50 frames per second
    cmd = ["whisper-cli", "-nt", "-np", "-l", cfg["lang"], "-ac", str(ctx), "-f", str(AUDIO)]
    cmd += ["-m", str(d.model_file(f"ggml-{cfg['whisper']}.bin"))]
    cmd += ["--vad", "-vm", str(d.model_file(d.VAD_MODEL))]
    if cfg["prompt"]:
        cmd += ["--prompt", cfg["prompt"]]
    out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    text = " ".join(line.strip() for line in out.splitlines() if line.strip())
    if len(text) < 80 and d.HALLUCINATIONS.search(text):
        return ""
    return d.spoken_marks(text)


def finish(st):
    """Stop the recording, transcribe, ask; called with the state already set to busy."""
    stop_recorder(st)
    try:
        d = dictate()
        cfg = d.settings()
        cfg["lang"] = LANG
        bubble("think", "")
        t0 = time.monotonic()
        question = transcribe(d, cfg)
        log(f"whisper {time.monotonic() - t0:.2f}s: {question!r}")
        if (RUN / "cancelled").exists():
            return
        if not question:
            bubble("error", "I didn't catch that.")
            return
        ask(question)
    except Exception as e:  # the bubble must never stay busy
        log(f"failed: {e!r}")
        bubble("error", f"Failed: {e}")
    finally:
        AUDIO.unlink(missing_ok=True)
        write_state({})


# ---- commands ----


def to_busy(st):
    """recording -> busy (this process); returns the recording's state for finish()."""
    (RUN / "cancelled").unlink(missing_ok=True)
    write_state({"state": "busy", "pid": os.getpid()})
    return st


def cmd_down():
    if stop_alarm():  # the key silences a ringing timer, like a snooze button
        return
    with Locked():
        st = read_state()
        if st.get("state") == "busy":
            return
        if st.get("state") != "recording":
            (RUN / "cancelled").unlink(missing_ok=True)
            start()
            return
        rec = to_busy(st)  # the release that follows sees busy and does nothing
    finish(rec)


def cmd_up():
    with Locked():
        st = read_state()
        # a tap leaves the recording running (toggle); after a hold, letting go stops it
        if st.get("state") != "recording" or time.monotonic() - st["since"] < HOLD:
            return
        rec = to_busy(st)
    finish(rec)


def cmd_toggle():
    with Locked():
        if not read_state():
            (RUN / "cancelled").unlink(missing_ok=True)
            start()
            return
    cmd_down()


def cmd_cancel():
    with Locked():
        st = read_state()
        (RUN / "cancelled").touch()
        if st.get("state") == "recording":
            stop_recorder(st)
            AUDIO.unlink(missing_ok=True)
            write_state({})
        elif alive(st.get("claude")):
            os.killpg(st["claude"], signal.SIGTERM)
    silence()
    stop_alarm()
    bubble("hide")


ALARM = RUN / "alarm.pid"
RATE = 44100
RING_FOR = 120  # seconds; then it gives up, the notification stays


def ring_cycle():
    """One cycle of the alarm as floats (-1..1): a low, unhurried marimba motif, E G C' G twice, then a
    long breath. Each note is a mallet: the fundamental with a long decay, a soft 4th harmonic that dies
    at once (the strike), a 20 ms fade in and a fade out at the end of its window, so nothing clicks."""
    beat = 0.26
    motif = [329.63, 392.0, 523.25, 392.0]  # E4 G4 C5 G4
    notes = [(f, i * beat) for i, f in enumerate(motif)] + [(f, (4 + i) * beat + 0.2) for i, f in enumerate(motif)]
    ring = 1.8  # seconds each note sounds
    length = int(RATE * 4.2)
    out = [0.0] * length
    for freq, start in notes:
        first = int(start * RATE)
        w = 2 * math.pi * freq
        for i in range(min(length - first, int(RATE * ring))):
            t = i / RATE
            fade = min(1.0, t / 0.02, (ring - t) / 0.2)
            out[first + i] += fade * (
                math.exp(-t / 0.5) * math.sin(w * t) + 0.18 * math.exp(-t / 0.03) * math.sin(4 * w * t)
            )
    peak = max(abs(v) for v in out)
    return [v / peak for v in out]


def stop_alarm():
    """Silence a ringing timer; True if one was ringing."""
    try:
        pid = int(ALARM.read_text())
        if "alert" not in Path(f"/proc/{pid}/cmdline").read_text():  # not a reused pid
            raise ValueError
        os.kill(pid, signal.SIGTERM)
        return True
    except (OSError, ValueError):
        ALARM.unlink(missing_ok=True)
        return False


def cmd_alert(label):
    """A timer or reminder rings (tools.py timer/remind): the notification, the bubble, the motif, the
    label spoken once, then the motif again, getting louder, until a click on the bubble or SUPER + A
    stops it (stop_alarm), or RING_FOR seconds pass."""
    notify(f"\u23f0 {label}", "critical")
    stop_alarm()  # an earlier one still ringing
    RUN.mkdir(parents=True, exist_ok=True)
    ALARM.write_text(str(os.getpid()))
    player, speaker = None, None

    def stop(*_):
        if player:
            player.kill()
        if speaker:
            speaker.stop()
        ALARM.unlink(missing_ok=True)
        bubble("ringing", "false")
        bubble("hide")
        sys.exit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    ensure_shell()
    bubble("think", "\u23f0  click or SUPER + A to stop")
    bubble("answer", label)
    bubble("ringing", "true")
    cycle = ring_cycle()
    player = subprocess.Popen(
        ["pw-play", "--rate", str(RATE), "--channels", "1", "--format", "s16", "--raw", "-"],
        stdin=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    started = time.monotonic()
    n = 0
    while time.monotonic() - started < RING_FOR:
        gain = min(0.7, 0.3 + 0.06 * n)  # starts soft, grows over about seven rounds
        try:
            player.stdin.write(array.array("h", (int(v * gain * 32767) for v in cycle)).tobytes())
            player.stdin.flush()
        except OSError:
            break
        if n == 0:  # after the first round: what the timer was for
            time.sleep(len(cycle) / RATE)
            speaker = Speaker()
            speaker.feed(label + "\n")
            speaker.done()
            if speaker.proc:
                speaker.proc.wait()
            speaker = None
        n += 1
    stop()


def cmd_ask(question):
    ensure_shell()
    with Locked():
        if read_state():
            return
        (RUN / "cancelled").unlink(missing_ok=True)
        write_state({"state": "busy", "pid": os.getpid()})
    try:
        ask(question)
    finally:
        write_state({})


def main():
    args = sys.argv[1:]
    cmd = args[0] if args else ""
    if cmd not in ("rec", "setup"):
        log(f"{cmd}  (state: {read_state().get('state', 'idle')})")
    if cmd == "down":
        cmd_down()
    elif cmd == "up":
        cmd_up()
    elif cmd == "toggle":
        cmd_toggle()
    elif cmd == "cancel":
        cmd_cancel()
    elif cmd == "rec":
        cmd_rec()
    elif cmd == "setup":
        cmd_setup()
    elif cmd == "alert" and len(args) > 1:
        cmd_alert(" ".join(args[1:]))
    elif cmd == "ask" and len(args) > 1:
        cmd_ask(" ".join(args[1:]))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
