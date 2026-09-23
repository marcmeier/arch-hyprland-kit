#!/bin/sh
# Switch between internal / external / extended / mirrored display, like Win+P.
# Usage: display-mode.sh [extend|mirror|internal|external]  (no argument: pick in walker)
# Changes last until the next config reload; the waybar layout follows via density-watch.py.

INTERNAL=eDP-1
EXTERNAL=$(hyprctl -j monitors all | python3 -c '
import json, sys
print(next((m["name"] for m in json.load(sys.stdin) if m["name"] != "'"$INTERNAL"'"), ""))')

mode=$1
if [ -z "$mode" ]; then
    [ -n "$EXTERNAL" ] || { notify-send "Display" "No external monitor connected"; exit 1; }
    choice=$(printf '%s\n' "󰍺  Extend" "󰍹  Mirror" "󰌢  Laptop only" "󰍹  External only" |
        walker --dmenu -p "Display mode") || exit 0
    case $choice in
        *Extend) mode=extend ;;
        *Mirror) mode=mirror ;;
        *"Laptop only") mode=internal ;;
        *"External only") mode=external ;;
        *) exit 0 ;;
    esac
fi

mon() { printf 'hl.monitor({ output = "%s", %s }) ' "$1" "$2"; }
on='mode = "preferred", scale = 1, disabled = false'
solo="$on, mirror = \"\""

case $mode in
    extend)   lua="$(mon $INTERNAL "$solo, position = \"0x0\"")$(mon "$EXTERNAL" "$solo, position = \"auto-right\"")" ;;
    mirror)   lua="$(mon $INTERNAL "$solo, position = \"0x0\"")$(mon "$EXTERNAL" "$on, position = \"auto-right\", mirror = \"$INTERNAL\"")" ;;
    internal) lua="$(mon $INTERNAL "$solo, position = \"0x0\"")$(mon "$EXTERNAL" "disabled = true")" ;;
    external) lua="$(mon "$EXTERNAL" "$solo, position = \"0x0\"")$(mon $INTERNAL "disabled = true")" ;;
    *) echo "usage: $0 [extend|mirror|internal|external]" >&2; exit 2 ;;
esac

[ -n "$EXTERNAL" ] || [ "$mode" = internal ] || { notify-send "Display" "No external monitor connected"; exit 1; }
[ -n "$EXTERNAL" ] || lua=$(mon $INTERNAL "$solo, position = \"0x0\"")
hyprctl eval "$lua"
# mirroring fires no monitor event, so tell density-watch.py to re-render the bars
kill -USR1 "$(cat ~/.cache/waybar/density-watch.pid 2>/dev/null)" 2>/dev/null
