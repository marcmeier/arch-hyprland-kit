#!/usr/bin/env bash
# set-wallpaper.sh <image>|--current|--default
# Sets ~/.config/wall.png, derives accent colours from it, renders all themed configs and reloads
# the running programs. The login screen needs root (one sudo prompt at the end).
set -euo pipefail
TH="$HOME/.config/theme"
arg="${1:-}"
[[ -n $arg ]] || {
  echo "usage: set-wallpaper.sh <image>|--current|--default" >&2
  exit 1
}

if [[ $arg == --current || $arg == --default ]]; then
  python3 "$TH/apply.py" "$arg"
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
  python3 "$TH/apply.py" "$HOME/.config/wall.png"
fi

# reload running programs (each step optional)
pkill swaybg 2> /dev/null || true
setsid swaybg -i "$HOME/.config/wall.png" -m fill > /dev/null 2>&1 &
pkill waybar 2> /dev/null || true
sleep 0.3
setsid "$HOME/.config/waybar/launch.sh" > /dev/null 2>&1 &
makoctl reload 2> /dev/null || true
hyprctl reload > /dev/null 2>&1 || true
pkill -USR2 -x ghostty 2> /dev/null || true

# login screen: blurred wallpaper + css (root). sudo in a terminal, else a graphical polkit prompt.
# shellcheck disable=SC2016 # expanded by the root shell that runs it
install_login='install -Dm644 "$1/login.png" /usr/share/backgrounds/login.png && install -Dm644 "$1/regreet.css" /etc/greetd/regreet.css'
if [[ -t 0 ]]; then
  echo "Login screen: sudo needed"
  sudo sh -c "$install_login" _ "$HOME/.cache/theme" && echo "login screen updated" || echo "login screen NOT updated" >&2
elif command -v pkexec > /dev/null; then
  pkexec sh -c "$install_login" _ "$HOME/.cache/theme" && echo "login screen updated" || echo "login screen NOT updated (prompt cancelled?)" >&2
else
  echo "Login screen NOT updated (no terminal, no pkexec). Run:"
  echo "  sudo install -Dm644 ~/.cache/theme/login.png /usr/share/backgrounds/login.png && sudo install -Dm644 ~/.cache/theme/regreet.css /etc/greetd/regreet.css"
fi
