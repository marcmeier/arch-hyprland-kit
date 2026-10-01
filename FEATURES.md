# Features

Everything driftless sets up, in one page. `SUPER + SHIFT + K` lists every key on the running desktop,
searchable as you type.

## Keys you'll use every day

| Keys | What |
|---|---|
| `SUPER + SPACE` | App launcher: apps, calculator, web search |
| `SUPER + RETURN` / `SUPER + SHIFT + RETURN` | Terminal / browser |
| `SUPER + D` | Dictation into the active window (tap: start/stop, hold: push-to-talk) |
| `SUPER + A` | Ask Claude by voice: the answer appears at the top and is spoken (tap or hold, like dictation) |
| `SUPER + C` | Clipboard history |
| `SUPER + .` | Emoji picker |
| `SUPER + SHIFT + S` · `SUPER + SHIFT + A` | Screenshot of an area · the same, to annotate |
| `SUPER + K` | Colour picker (hex code to the clipboard) |
| `SUPER + SHIFT + P` | Display mode: extend, mirror, one screen (like Win + P) |
| `SUPER + SHIFT + M` | Lock, log out, suspend, reboot, shut down |
| `SUPER + SHIFT + K` | Every keybinding, searchable |

<table>
<tr>
<td width="50%"><img src="docs/img/keybinds.jpg" alt="walker listing every keybinding with its description"><br><sub><code>SUPER + SHIFT + K</code>: every key of the running desktop.</sub></td>
<td width="50%"><img src="docs/img/keybinds-search.jpg" alt="the keybinding list filtered by typing screen"><br><sub>Type to filter: <code>screen</code> leaves the screenshot, display and fullscreen keys.</sub></td>
</tr>
</table>

## Dictation

Speak, and the text lands in whatever window is active, terminals included. All of it runs locally on
the GPU (Vulkan: AMD, Intel and NVIDIA):

- **whisper.cpp** (large-v3-turbo) transcribes, a voice detector keeps it from inventing text in silence
- **a small LLM** (`gemma3:4b` via Ollama) tidies up: fillers out, punctuation in, "Tuesday, no, I
  mean Wednesday" becomes "Wednesday". Spoken "comma", "new line", "new paragraph" work too
- about 1-2 seconds from letting go to the text; `SUPER + SHIFT + D` skips the LLM
- the model leaves VRAM after 5 minutes, so games get it back
- language, models and names Whisper should know: `DICTATE_*` in `personal/config`

<img src="docs/img/dictation-pill.png" alt="The dictation pill next to the microphone: ready, recording, transcribing" width="600"><br>
<sub>The pill next to the microphone: ready, recording, transcribing. Click: start/stop, right click: without the LLM, middle: cancel.</sub>

## Asking Claude

`SUPER + A`, a question, and the answer appears in a bubble at the top of the screen while a voice
reads it out. Like Siri or Alexa, for the quick things, without opening a window:

<table>
<tr>
<td width="50%"><img src="docs/img/notch-listening.png" alt="The bubble listening, with level bars"><br><sub>Listening: the orb and the bars follow your voice.</sub></td>
<td width="50%"><img src="docs/img/notch-thinking.png" alt="The bubble showing the question while Claude thinks"><br><sub>Your question while Claude works on it.</sub></td>
</tr>
<tr>
<td width="50%"><img src="docs/img/notch-answer.png" alt="The bubble opened up with the answer"><br><sub>The answer, typed in as it arrives and read out at the same time.</sub></td>
<td width="50%"><img src="docs/img/notch-timer.png" alt="A timer ringing in the bubble"><br><sub>A timer rings until you stop it.</sub></td>
</tr>
</table>

| Say | What happens |
|---|---|
| "Set a timer for 10 minutes for the pasta", "Remind me at 3 to call Anna" | a gentle marimba alarm that swells until a click or `SUPER + A` stops it, and the voice says what it was for; "Which timers are running?", "Cancel the timer" |
| "Do I have anything on this afternoon?", "Put the dentist in for Tuesday at 3" | reads and adds calendar events (khal, synced right away) |
| "What will the weather be like tomorrow?" | now and three days, for your `WTTR_LOCATION` or any place |
| "What's on my screen?", "Summarise this article", "What does this error mean?" | Claude looks at a screenshot of your monitor |
| "Translate what I copied", "Write a polite reply that I'm ill and paste it" | reads the clipboard, types text into the active window |
| "Note: buy milk", "What did I note?" | a notes file (`NOTCH_NOTES`, default `~/Documents/notes.md`) |
| "Pause the music", "Next song", "Volume to 30", "Brighter" | media, volume, screen brightness |
| "How full is the battery?", "Are there updates?", "Connect my headphones" | battery, disk, memory, network, pending updates, Bluetooth |
| "Do not disturb", "Lock the screen", "New wallpaper", "Suspend" | |
| "Open Firefox", "Find my tax return", "Open the Arch Wiki on PipeWire" | starts apps, finds files by name, opens files and pages |
| "What's 18 % of 240?", "How do you say thank you in Japanese?", news, facts | answered directly or from a web search |

A question within two minutes continues the conversation ("And on Friday?"). A click on the bubble or
a new question stops everything.

Whisper transcribes locally (the dictation setup), Claude Code answers (`claude -p`, Haiku by default)
and may use only `notch/tools.py` (the actions above), the screenshot and web search, without asking
and without your Claude Code settings. Piper speaks the answer sentence by sentence as it arrives,
locally too (installed into a venv on first use). The bubble is part of the desktop shell, in the colours
of your wallpaper (it follows a new one at once): listening with level bars, thinking, then it opens up
for the answer. Model, language, voice and notes file:
`NOTCH_*` in `personal/config`.

## The bar

One bar per monitor, drawn by Quickshell together with its popups and the Claude bubble: compact on
notebook panels, spacious everywhere else. It follows the wallpaper's colours and your widget layout
live, without a restart. Pills from left to right:

<img src="docs/img/desktop.jpg" alt="Desktop with the spacious bar on an ultrawide monitor"><br>
<sub>The spacious bar on a 3440x1440 ultrawide.</sub>


- **You**: avatar and name; a click opens the settings menu
- **Workspaces** (the active one's gradient slides along) and the **active window**
- **Clock, weather and your next calendar event**. Click the clock: the month with a dot on every day
  that has events, click a day for its events, and what comes up; right click or a click on the event:
  ikhal. Click the weather: the next hours and three days
- **Media**: play/pause, skip, the title slides through when it is long. Click it: cover, progress (click
  to jump), shuffle and repeat, and every player that runs
- **Claude Code usage**: session and weekly limits; click: both with their resets and the tokens per day
- **Status**: network (click: Wi-Fi networks, join a known one, on/off), volume (wheel: level; click:
  outputs, microphones and a level per app that plays; right: mute), microphone, dictation, battery
  (click: time left, power draw, health, power profile)
- **System**: tray (right click: the app's menu in the same style), pending updates, the sync, keep
  awake, notifications (click: do not disturb), power

Hover anything for a tooltip; a click elsewhere or `Esc` closes a popup. Popups also open from a key
binding or a script: `quickshell ipc -p ~/.config/quickshell call bar popup calendar` (`weather`,
`media`, `claude`, `audio`, `network`, `battery`).

<img src="docs/img/bar-popups.jpg" alt="Four popups of the bar: media, sound, Claude usage, battery" width="700"><br>
<sub>Popups: what plays, sound with a level per app, Claude usage, battery and power profile.</sub>

## Settings menu

A click on the avatar, every choice per machine:

<img src="docs/img/settings.jpg" alt="The settings menu in walker" width="600"><br>
<sub>The settings menu.</sub>


- **Widgets**: show, hide and move every pill, separately for the spacious and the compact bar
- **Bar size**: automatic, always spacious, always compact
- **Wallpaper and colours**: thumbnails and a large preview (next section)
- **Monitors**: arrange them (nwg-displays), or back to the automatic layout
- **Sync**: mode, what is waiting, trust a new machine
- **Keybindings**: the searchable list

## Theme from the wallpaper

`set-wallpaper IMAGE` derives two accent colours from the image and renders them into the bar, walker,
wlogout, mako, Ghostty, hyprlock, the login screen, GTK, Qt, btop and VS Code (theme "driftless": 2026
Dark with your accents). The calendar, fastfetch, bat and fzf use the terminal's accent slots, so they
follow too.

- **The wallpaper menu** (settings menu): your wallpaper folder with thumbnails and a large preview,
  plus a random one, the previous one or any other image. The folder is `WALLPAPER_DIR` in
  `personal/config`, e.g. one your cloud client syncs, so every machine has the same choice
- **The change itself** (awww): the new image grows in as a circle from the mouse pointer while the
  colours change with it
- **A new wallpaper every day**, at random from the folder; a day the machine was off catches up after
  the next login. `set-wallpaper --random` does the same by hand
- **The login screen** (ReGreet) shows the same wallpaper, your avatar and the machine's name, and
  follows every change without a password prompt

<img src="docs/img/wallpaper-menu.jpg" alt="The wallpaper menu in walker: thumbnails on the left, a large preview on the right" width="600"><br>
<sub>The wallpaper menu: thumbnails, and the selected image large.</sub>

<table>
<tr>
<td width="50%"><img src="docs/img/theme-tiled.jpg" alt="Tiled windows: btop, Nautilus and Ghostty"><br><sub>The terminal palette follows the wallpaper.</sub></td>
<td width="50%"><img src="docs/img/theme-greeter.jpg" alt="ReGreet login screen"><br><sub>The login screen with the same wallpaper and colours.</sub></td>
</tr>
</table>

## Gaming

Steam, Proton-GE, Lutris, gamescope and gamemode, with tearing allowed for games (lower input
latency) and rules that open stubborn games fullscreen on the right monitor.

## The system underneath

- **btrfs with snapper** snapshots, optional **LUKS2** encryption (TPM unlock: [docs/encryption.md](docs/encryption.md))
- **unified kernel images**, with an LTS kernel as fallback ([docs/boot.md](docs/boot.md))
- zram, a firewall (ufw), SMART warnings as desktop notifications, locked screen after 10 minutes
- the session runs under uwsm: bar, notifications, idle, clipboard and wallpaper are systemd user units
  that restart when they crash

## Keeping your machines in step

- your home is **links into the repository**: editing `~/.config/hypr/hyprland.lua` is editing the
  repository
- an **hourly sync** commits what you changed and takes over what your other machines changed, but only
  commits one of your machines signed; it refuses anything that looks like a password
- **package lists** you write (`driftless packages add NAME GROUP`), picked per machine by its hardware
- what differs per machine goes into `hosts/<host>/`, what is yours into `personal/`
- `driftless verify` shows where a machine differs from the repository; a new machine is two scripts
  away ([README](README.md#install-a-new-machine))
