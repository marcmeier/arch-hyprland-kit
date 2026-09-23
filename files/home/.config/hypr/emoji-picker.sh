#!/bin/bash
# Emoji picker: walker --dmenu picks, wtype types the emoji straight into the active window.
list=~/.config/emoji/list.txt
[ -s "$list" ] || python3 ~/.config/emoji/gen-list.py
sel=$(walker --dmenu < "$list") || exit 0
emoji=${sel%% *}
[ -n "$emoji" ] || exit 0
sleep 0.15   # focus has to return to the previous window first
wtype "$emoji"
