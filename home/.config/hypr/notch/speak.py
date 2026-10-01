"""Speaker for notch.py: reads sentences from stdin, one per line, and speaks them with Piper.
Started by notch.py as soon as a question is asked, so the voice loads while Claude thinks.

The playback is paced to real time, so the level sent to the bubble (the orb pulses with it) matches
what is heard. SIGTERM stops at once.

Usage: <venv>/bin/python speak.py <voice>[:<speaker>]
    e.g. de_DE-thorsten-high, de_DE-thorsten_emotional-medium:amused (in ~/.local/share/piper; the
    speaker by name or number). Runs with notch.py's venv (~/.local/share/claude-notch/venv), which
    has piper-tts; try a voice: echo "Hello there." | ~/.local/share/claude-notch/venv/bin/python speak.py NAME"""

import array
import math
import os
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
VOICES = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "piper"
LEAD = 0.15  # seconds of audio handed to pw-play ahead of what is heard
# a bit livelier than the voices' defaults (some ship a flat 0.333): more varied melody and rhythm,
# slightly faster
LIVELY = {"length_scale": 0.92, "noise_scale": 0.667, "noise_w_scale": 0.8}


def bubble(*args):
    subprocess.Popen(
        ["quickshell", "ipc", "-p", str(HERE), "call", "notch", *map(str, args)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


# what Piper would read out wrongly
SPOKEN = [
    (r"\b(\d{1,2}):00\s*Uhr", r"\1 Uhr"),
    (r"\b(\d{1,2}):(\d{2})\s*Uhr", r"\1 Uhr \2"),
    (r"\b(\d{1,2}):(\d{2})\b", r"\1 Uhr \2"),
    (r"\s*[–—]\s*", ", "),
    (r"&", " und "),
    (r"\bz\.\s?B\.", "zum Beispiel"),
    (r"\bca\.", "circa"),
    (r"\bbzw\.", "beziehungsweise"),
    (r"https?://\S+", "der Link"),
]


def spoken(text):
    for pattern, repl in SPOKEN:
        text = re.sub(pattern, repl, text)
    return text.strip()


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    from piper import PiperVoice, SynthesisConfig  # slow import: after the arguments are checked

    name, _, speaker = sys.argv[1].partition(":")
    voice = PiperVoice.load(str(VOICES / f"{name}.onnx"))
    ids = voice.config.speaker_id_map or {}
    sid = ids.get(speaker, int(speaker) if speaker.isdigit() else None) if speaker else None
    style = SynthesisConfig(speaker_id=sid, **LIVELY)
    rate = voice.config.sample_rate
    player = None
    talking = False

    def stop(*_):
        if player:
            player.kill()
        bubble("speaking", "false")
        sys.exit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    sent = 0.0
    start, written = 0.0, 0.0  # wall clock when playback began, seconds of audio handed over
    for line in sys.stdin:
        text = spoken(line)
        if not text:
            continue
        for chunk in voice.synthesize(text, syn_config=style):
            pcm = chunk.audio_int16_bytes
            if player is None:
                player = subprocess.Popen(
                    ["pw-play", "--rate", str(rate), "--channels", "1", "--format", "s16", "--raw", "-"],
                    stdin=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                )
            if not talking:
                talking = True
                bubble("speaking", "true")
            step = rate // 20 * 2  # 50 ms
            for i in range(0, len(pcm), step):
                piece = pcm[i : i + step]
                now = time.monotonic()
                if written == 0.0 or now - start > written:  # fell behind (or first piece): restart the clock
                    start, written = now, 0.0
                ahead = written - (now - start) - LEAD
                if ahead > 0:
                    time.sleep(ahead)
                player.stdin.write(piece)
                player.stdin.flush()
                written += len(piece) / 2 / rate
                if now - sent < 0.08:
                    continue
                sent = now
                samples = array.array("h", piece)
                rms = math.sqrt(sum(s * s for s in samples) / max(len(samples), 1)) / 32768
                level = max(0.0, min(1.0, (20 * math.log10(max(rms, 1e-6)) + 45) / 30))
                bubble("setLevel", f"{level:.2f}")
    if player:
        player.stdin.close()
        player.wait()
    bubble("speaking", "false")


if __name__ == "__main__":
    main()
