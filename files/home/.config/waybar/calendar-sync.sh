#!/usr/bin/env bash
# Sync Nextcloud calendars. On failure: one desktop notification (per failure streak) and a
# state file that makes the waybar calendar pill show a warning. On success the state is cleared.
STATE="${XDG_CACHE_HOME:-$HOME/.cache}/calendar-sync-failed"
VDIR="${VDIRSYNCER:-vdirsyncer}"

SYNC_ID="string:x-canonical-private-synchronous:calendar-sync"
if "$VDIR" sync && "$VDIR" metasync; then
  # recovered: replace the sticky failure notification by a short-lived one
  [[ -e $STATE ]] && notify-send -h "$SYNC_ID" -u normal -t 4000 "Calendar sync restored" 2>/dev/null
  rm -f "$STATE"
else
  if ! secret-tool lookup service nextcloud-caldav user "$USER" >/dev/null 2>&1; then
    reason="Keyring locked or app password missing (log in again or run calendar-login.sh)"
  else
    reason="vdirsyncer sync failed (run: vdirsyncer sync)"
  fi
  if [[ ! -e $STATE ]]; then
    notify-send -h "$SYNC_ID" -u critical "Calendar sync failed" "$reason" 2>/dev/null || true
  fi
  printf '%s\n' "$reason" > "$STATE"
fi
pkill -RTMIN+9 waybar 2>/dev/null || true
[[ ! -e $STATE ]]
