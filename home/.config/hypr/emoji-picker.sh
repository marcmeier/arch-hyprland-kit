#!/bin/bash
# Emoji picker: walker --dmenu picks, the emoji is pasted into the active window.
# Chromium/Electron (Brave, WhatsApp Web, Discord) mangle emoji typed via wtype's
# keysym trick (shows up as tofu, even for the recipient), so we paste via the
# clipboard instead. Terminals don't paste on Ctrl+V, there wtype works fine.
list=~/.config/emoji/list.txt
[ -s "$list" ] || python3 ~/.config/emoji/gen-list.py
sel=$(walker --dmenu < "$list") || exit 0
emoji=${sel%% *}
[ -n "$emoji" ] || exit 0
sleep 0.15 # focus has to return to the previous window first
class=$(hyprctl activewindow | sed -n 's/^\s*class: //p')
case "$class" in
  com.mitchellh.ghostty | *kitty* | *foot* | *Alacritty*)
    wtype "$emoji"
    ;;
  *)
    printf '%s' "$emoji" | wl-copy
    sleep 0.05
    wtype -M ctrl v -m ctrl
    ;;
esac
