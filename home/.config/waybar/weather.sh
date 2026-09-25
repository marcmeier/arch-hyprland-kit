#!/usr/bin/env bash
# Waybar: weather from wttr.in. Location: WTTR_LOCATION from the personal layer, else guessed from
# your IP. Hidden on failure.
# shellcheck source=/dev/null
[[ -r ~/.config/driftless/personal/config ]] && source ~/.config/driftless/personal/config
loc="${WTTR_LOCATION:-}"
short=$(curl -fsS -m 8 "https://wttr.in/${loc// /+}?format=%c+%t" 2> /dev/null | sed 's/+//g; s/  */ /g')
long=$(curl -fsS -m 8 "https://wttr.in/${loc// /+}?format=%l:+%C,+%t+(feels+%f)\nHumidity+%h,+wind+%w" 2> /dev/null)
if [[ -z $short || $short == *Unknown* || $short == *"Sorry"* ]]; then
  echo '{"text":"","tooltip":false}'
  exit 0
fi
icon="${short%% *}"
rest="${short#* }"
printf '{"text":"<span size=\\"large\\">%s</span>  %s","tooltip":"%s"}\n' "$icon" "$rest" "${long//$'\n'/\\n}"
