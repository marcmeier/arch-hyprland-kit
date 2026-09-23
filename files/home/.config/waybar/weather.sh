#!/usr/bin/env bash
# Waybar: weather from wttr.in (location from your IP, or set WTTR_LOCATION). Hidden on failure.
loc="${WTTR_LOCATION:-}"
short=$(curl -fsS -m 8 "https://wttr.in/${loc// /+}?format=%c+%t" 2>/dev/null | sed 's/+//g; s/  */ /g')
long=$(curl -fsS -m 8 "https://wttr.in/${loc// /+}?format=%l:+%C,+%t+(feels+%f)\nHumidity+%h,+wind+%w" 2>/dev/null)
if [[ -z $short || $short == *Unknown* || $short == *"Sorry"* ]]; then echo '{"text":"","tooltip":false}'; exit 0; fi
icon="${short%% *}"; rest="${short#* }"
printf '{"text":"<span size=\\"large\\">%s</span>  %s","tooltip":"%s"}\n' "$icon" "$rest" "${long//$'\n'/\\n}"
