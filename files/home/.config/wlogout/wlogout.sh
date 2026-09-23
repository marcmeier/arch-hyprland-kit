#!/bin/sh
# Toggle the compact, centered wlogout layout (single point of truth for hyprland + waybar).
# Margins are computed from the focused monitor's logical size (respects scale), so the
# 5 buttons of ~187px + 16px gaps stay centered on any resolution/scale.
pkill -x wlogout && exit 0
W=1000; H=220
SIZE=$(hyprctl monitors -j | python3 -c '
import json, sys
m = json.load(sys.stdin)
m = next((x for x in m if x.get("focused")), m[0])
print(int(m["width"] / m["scale"]), int(m["height"] / m["scale"]))')
set -- $SIZE
MW=${1:-2752}; MH=${2:-1152}
LR=$(( (MW - W) / 2 )); TB=$(( (MH - H) / 2 ))
exec wlogout -b 5 -c 16 -L "$LR" -R "$LR" -T "$TB" -B "$TB"
