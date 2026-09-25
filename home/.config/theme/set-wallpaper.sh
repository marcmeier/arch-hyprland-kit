#!/usr/bin/env bash
# set-wallpaper.sh <image>|--current|--default
# Sets ~/.config/wall.png, derives accent colours from it, renders all themed configs and reloads
# the running programs. The login screen needs root (one sudo prompt at the end).
# Wallpaper and colours are per machine: none of it is in the repository.
set -euo pipefail
THEME_DIR="$HOME/.config/theme"
arg="${1:-}"
[[ -n $arg ]] || {
  echo "usage: set-wallpaper.sh <image>|--current|--default" >&2
  exit 1
}

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
  python3 "$THEME_DIR/apply.py" "$HOME/.config/wall.png"
fi

# reload running programs (each step optional)
systemctl --user restart driftless-wallpaper.service waybar.service 2> /dev/null || true
makoctl reload 2> /dev/null || true
hyprctl reload > /dev/null 2>&1 || true
pkill -USR2 -x ghostty 2> /dev/null || true

# login screen: blurred wallpaper, colours and avatar go to /var/lib/driftless/greeter (root, from the
# driftless-system package): sudo in a terminal, else a password dialog
update=/usr/lib/driftless/greeter-update
if [[ ! -x $update ]]; then
  echo "Login screen NOT updated: driftless-system is not installed (driftless system)" >&2
elif [[ -t 0 ]]; then
  sudo "$update" "$HOME/.cache/theme" && echo "login screen updated"
else
  pkexec "$update" "$HOME/.cache/theme" && echo "login screen updated" || echo "login screen NOT updated (dialog cancelled?)" >&2
fi
