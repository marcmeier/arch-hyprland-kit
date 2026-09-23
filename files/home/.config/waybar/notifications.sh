#!/usr/bin/env bash
# Waybar: mako state. Bell + count of waiting notifications; crossed-out bell in do-not-disturb mode.
n=$(makoctl list 2>/dev/null | grep -c '^Notification')
if makoctl mode 2>/dev/null | grep -qx dnd; then
  icon=$'\U000f009b'; cls=dnd; tip="Do not disturb (notifications are held)"
elif (( n > 0 )); then
  icon=$'\U000f009e'; cls=active; tip="$n notification(s)"
else
  icon=$'\U000f009a'; cls=none; tip="No notifications"
fi
text="$icon"; (( n > 0 )) && text="$icon $n"
printf '{"text":"%s","class":"%s","tooltip":"%s\\nClick: do not disturb  ·  Right: bring back last  ·  Middle: clear all"}\n' "$text" "$cls" "$tip"
