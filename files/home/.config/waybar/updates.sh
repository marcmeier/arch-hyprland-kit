#!/usr/bin/env bash
# Waybar: pending pacman + AUR updates. Hidden (empty text) when up to date.
repo=$(checkupdates 2>/dev/null | wc -l)
aur=$(yay -Qua 2>/dev/null | wc -l)
n=$((repo + aur))
if (( n == 0 )); then
  echo '{"text":"","class":"none","tooltip":false}'
else
  cls=updates; (( n >= 30 )) && cls=many
  printf '{"text":"󰏔 %d","class":"%s","tooltip":"%d official, %d AUR\\nClick: update  ·  Right-click: refresh"}\n' "$n" "$cls" "$repo" "$aur"
fi
