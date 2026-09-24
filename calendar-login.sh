#!/usr/bin/env bash
# One-time (and after every rebuild): store the Nextcloud app password in the keyring,
# discover the calendars, first sync, start the 10-minute sync timer.
# Run as normal user:  bash calendar-login.sh
set -euo pipefail
if ! command -v vdirsyncer > /dev/null || ! command -v khal > /dev/null; then
  echo "install first: sudo pacman -S vdirsyncer khal"
  exit 1
fi

# a kit with the placeholder config (cloud.example.com): ask for the own server and login once
CFG=~/.config/vdirsyncer/config
if grep -q 'cloud\.example\.com' "$CFG"; then
  read -rp "Nextcloud address (e.g. https://cloud.example.org): " url
  read -rp "Nextcloud user name: " nc_user
  sed -i "s#https://cloud\.example\.com#${url%/}#; s/YOUR_NEXTCLOUD_USER/$nc_user/; s/YOUR_LINUX_USER/$USER/" "$CFG"
fi

# the app password is never stored in a file, only in the desktop keyring (secret-tool);
# vdirsyncer's config reads it back from there via "password.fetch"
if ! secret-tool lookup service nextcloud-caldav user "$USER" > /dev/null 2>&1; then
  echo "Nextcloud -> Settings -> Security -> 'Create new app password', then paste it here:"
  secret-tool store --label="Nextcloud CalDAV (vdirsyncer)" service nextcloud-caldav user "$USER"
fi

yes | vdirsyncer discover nextcloud || true
vdirsyncer metasync
vdirsyncer sync
systemctl --user daemon-reload
systemctl --user enable --now vdirsyncer.timer
echo
khal printcalendars
echo "Done. Open the calendar with: ikhal"
