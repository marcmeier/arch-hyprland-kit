#!/usr/bin/env bash
# Opens ikhal (floating window via class rule). After closing it, local changes are pushed to Nextcloud immediately.
exec ghostty --class=com.mitchellh.ghostty.calendar \
  --window-padding-x=22 --window-padding-y=18 --background-opacity=1 --palette=0=#14161c -e bash -c '
  ikhal
  setsid -f ~/.config/waybar/calendar-sync.sh >/dev/null 2>&1
'
