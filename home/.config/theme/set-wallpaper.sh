#!/usr/bin/env bash
# set-wallpaper.sh <image>|--random|--current|--default
# Sets ~/.config/wall.png, derives accent colours from it, renders all themed configs and reloads
# the running programs. --random picks another image from the wallpaper folder (WALLPAPER_DIR in
# the personal layer, default ~/Pictures/Wallpapers; the daily driftless-wallpaper-rotate.timer).
# The login screen follows through pkexec, without a password (polkit allows it for the session).
# Wallpaper and colours are per machine: none of it is in the repository.
set -euo pipefail
THEME_DIR="$HOME/.config/theme"
arg="${1:-}"
[[ -n $arg ]] || {
  echo "usage: set-wallpaper.sh <image>|--random|--current|--default" >&2
  exit 1
}

if [[ $arg == --random ]]; then
  # shellcheck source=/dev/null
  [[ -r ~/.config/driftless/personal/config ]] && source ~/.config/driftless/personal/config
  walls=$(readlink -f "${WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}")
  # not the image that is up now (wall.source: the file the last one came from)
  current=$(cat "$HOME/.cache/theme/wall.source" 2> /dev/null || true)
  arg=$(find -H "$walls" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) |
    grep -vxF -- "${current:-/nonexistent}" | shuf -n 1) || true
  [[ -n $arg ]] || {
    echo "no other image in $walls" >&2
    exit 0
  }
fi

if [[ $arg == --current || $arg == --default ]]; then
  python3 "$THEME_DIR/apply.py" "$arg"
else
  [[ -f $arg ]] || {
    echo "not a file: $arg" >&2
    exit 1
  }
  # validate before touching anything
  python3 -c 'import sys; from PIL import Image; Image.open(sys.argv[1]).verify()' "$arg"
  mkdir -p "$HOME/.cache/theme"
  [[ -f $HOME/.config/wall.png ]] && cp -f "$HOME/.config/wall.png" "$HOME/.cache/theme/wall.prev.png"
  # always store as PNG (hyprlock/greeter read it by path)
  python3 -c 'import sys; from PIL import Image; Image.open(sys.argv[1]).convert("RGB").save(sys.argv[2], "PNG")' "$arg" "$HOME/.config/wall.png.new"
  mv -f "$HOME/.config/wall.png.new" "$HOME/.config/wall.png"
  readlink -f "$arg" > "$HOME/.cache/theme/wall.source"
  python3 "$THEME_DIR/apply.py" "$HOME/.config/wall.png"
fi

# new image: grows as a circle from the mouse pointer (awww), the colours change with it.
# The position is relative to the focused monitor, y counted from the top (--invert-y); the frame
# rate follows its refresh rate.
show_wallpaper() {
  local pos fps
  read -r pos fps < <(hyprctl -j monitors 2> /dev/null | python3 -c '
import json, subprocess, sys
cursor = json.loads(subprocess.check_output(["hyprctl", "-j", "cursorpos"]))
for m in json.load(sys.stdin):
    if m["focused"]:
        w, h = m["width"] / m["scale"], m["height"] / m["scale"]
        x = min(max((cursor["x"] - m["x"]) / w, 0), 1)
        y = min(max((cursor["y"] - m["y"]) / h, 0), 1)
        fps = round(m["refreshRate"])
        print(f"{x:.3f},{y:.3f} {fps}")
' 2> /dev/null) || true
  awww img "$HOME/.config/wall.png" --transition-type grow --transition-pos "${pos:-center}" --invert-y \
    --transition-duration 1.4 --transition-fps "${fps:-60}"
}

# reload running programs (each step optional)
if [[ $arg == --current || $arg == --default ]]; then
  :
elif awww query > /dev/null 2>&1; then
  show_wallpaper || systemctl --user restart driftless-wallpaper.service 2> /dev/null || true
else
  systemctl --user restart driftless-wallpaper.service 2> /dev/null || true
fi
systemctl --user restart waybar.service 2> /dev/null || true
# thumbnails for the wallpaper menu in walker, made ahead so the menu opens at once
if [[ -z ${walls:-} ]]; then
  # shellcheck source=/dev/null
  [[ -r ~/.config/driftless/personal/config ]] && source ~/.config/driftless/personal/config
  walls=${WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}
fi
if [[ -d $walls ]]; then
  setsid -f "$THEME_DIR/thumbs.py" "$walls" > /dev/null 2>&1
fi
makoctl reload 2> /dev/null || true
hyprctl reload > /dev/null 2>&1 || true
pkill -USR2 -x ghostty 2> /dev/null || true

# login screen: blurred wallpaper, colours and avatar go to /var/lib/driftless/greeter (root, from the
# driftless-system package; polkit lets the active session run it without a password)
update=/usr/lib/driftless/greeter-update
if [[ ! -x $update ]]; then
  echo "Login screen NOT updated: driftless-system is not installed (driftless system)" >&2
else
  pkexec "$update" "$HOME/.cache/theme" && echo "login screen updated" || echo "login screen NOT updated" >&2
fi
