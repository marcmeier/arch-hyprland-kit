#!/usr/bin/env bash
# Start (or restart) waybar with the layout matching the current monitor (see density-watch.py).
# Falls back to the plain config if rendering fails, so there is always a bar.
# Output goes to ~/.local/state/waybar/waybar.log; the previous session's log is kept as waybar.log.old.
log_dir=~/.local/state/waybar
mkdir -p "$log_dir"
pkill -x waybar && while pgrep -x waybar > /dev/null; do sleep 0.1; done
[ -f "$log_dir/waybar.log" ] && mv -f "$log_dir/waybar.log" "$log_dir/waybar.log.old"
args=()
~/.config/waybar/density-watch.py --once && args=(-c ~/.cache/waybar/config.jsonc -s ~/.cache/waybar/style.css)
setsid waybar "${args[@]}" > "$log_dir/waybar.log" 2>&1 < /dev/null &
