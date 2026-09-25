#!/usr/bin/env bash
# =============================================================================
# migrate-from-rebuild.sh - moves a running machine from the rebuild kit / arch-hyprland-kit v1
# (auto-snapshot.sh, copies back and forth) to driftless (links into ~/.local/share/driftless).
# Run as your user, in the Hyprland session, one machine at a time. Safe to run again.
# Clone your driftless repository to ~/.local/share/driftless first and run it from there.
#
#   bash install/migrate-from-rebuild.sh [--dry-run]
#
# What it does:
#   1. stops the old sync timer (the old repository stays where it is, untouched)
#   2. removes the old kit's programs from the live folders (density-watch.py, ws.py, the old sync
#      scripts ...): the new ones replace them, and they must not end up in the repository
#   3. links: everything comes from the repository (driftless changed those files on purpose), the live
#      versions are kept in ~/.local/state/driftless/backup/<time>/. Your own changes to the old kit's
#      dotfiles are in that backup: carry them over by hand. Targets listed in MIGRATE_ADOPT
#      (personal/config) keep their live version instead, e.g. notes that are newer on the machine.
#   4. driftless setup: signing (the old key and trust list are taken over), theme, user units
#   5. switches the bar and the helpers from the Hyprland autostart to their systemd units
# The root part follows by hand, it prints the command: install/migrate-system.sh
# =============================================================================
set -euo pipefail
DRIFTLESS=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
DRY=0
[[ ${1:-} == --dry-run ]] && DRY=1
run() { if ((DRY)); then echo "would run: $*"; else "$@"; fi; }
[[ $EUID -ne 0 ]] || { echo "run as your user, not root" && exit 1; }
[[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || echo "!! not inside Hyprland: the bar switch (step 5) waits for the next login"

echo "==> 0. repo packages the new setup needs (hyprpolkitagent, ...), with sudo"
((DRY)) || "$DRIFTLESS/driftless" packages install repo

echo "==> 1. old sync timer off"
run systemctl --user disable --now rebuild-snapshot.timer 2> /dev/null || true
run systemctl --user stop rebuild-snapshot.service 2> /dev/null || true
run rm -f ~/.config/systemd/user/timers.target.wants/rebuild-snapshot.timer

echo "==> 2. old kit programs out of the live folders"
OBSOLETE=(
  .config/waybar/density-watch.py .config/waybar/launch.sh .config/waybar/ws.py .config/waybar/window.py
  .config/waybar/media.py .config/waybar/avatar.png .config/waybar/__pycache__ .config/theme/__pycache__
  .config/emoji/__pycache__ .config/walker/themes/marc .config/walker/themes/kit
  .config/theme/templates/qt6ct-marc.conf .config/theme/templates/qt6ct-kit.conf
  .config/systemd/user/rebuild-snapshot.service
  .config/systemd/user/rebuild-snapshot.timer .config/nwg-displays
)
for f in "${OBSOLETE[@]}"; do
  [[ -e ~/$f || -L ~/$f ]] && run rm -rf ~/"$f"
done
# backup copies from before (*.bak-*) would land in the repository folder as untracked files: they
# move to a folder of their own instead (kept, not deleted)
OLD_BAK=${XDG_STATE_HOME:-$HOME/.local/state}/driftless/backup/old-bak-files
find ~/.config/hypr ~/.config/waybar ~/.config/theme ~/.config/wlogout ~/.config/walker ~/.config/ghostty \
  -maxdepth 2 -name '*.bak*' -print 2> /dev/null | while read -r f; do
  rel=${f#"$HOME"/}
  run mkdir -p "$OLD_BAK/$(dirname "$rel")"
  run mv "$f" "$OLD_BAK/$rel"
done
# theme/apply.py now renders the qt6ct config itself
run rm -f ~/.config/qt6ct/colors/marc.conf ~/.config/qt6ct/colors/kit.conf

echo "==> 3. links: from the repository (live versions to the backup), MIGRATE_ADOPT from here"
MIGRATE_ADOPT=()
# shellcheck source=/dev/null
[[ -r $DRIFTLESS/personal/config ]] && source "$DRIFTLESS/personal/config"
args=()
((DRY)) && args+=(--dry-run)
((${#MIGRATE_ADOPT[@]})) && args+=(--adopt "${MIGRATE_ADOPT[@]}")
"$DRIFTLESS/driftless" link "${args[@]}"

if ((DRY)); then
  echo "dry run: nothing changed"
  exit 0
fi

echo "==> 4. driftless setup"
# the old bar runs from the Hyprland autostart: stop it before the units take over
pkill -f 'waybar/density-watch.py' 2> /dev/null || true
pkill -x waybar 2> /dev/null || true
pkill -x swaybg 2> /dev/null || true
pkill -x mako 2> /dev/null || true
pkill -x hypridle 2> /dev/null || true
pkill -f 'wl-paste --watch cliphist' 2> /dev/null || true
pkill -f polkit-gnome-authentication-agent-1 2> /dev/null || true
pkill -x elephant 2> /dev/null || true
"$DRIFTLESS/driftless" setup
# a session started without uwsm never activates graphical-session.target, so the units above stay
# down: start the same programs in this session (hyprland.lua does so at every login without uwsm)
if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && ! systemctl --user is-active -q graphical-session.target; then
  echo "   session without uwsm: starting bar and helpers directly (next login: pick Hyprland (uwsm-managed))"
  for c in "$HOME/.config/waybar/render.py && waybar -c $HOME/.cache/waybar/config.jsonc" "$HOME/.config/waybar/feeds.py" \
    mako hypridle /usr/lib/hyprpolkitagent/hyprpolkitagent "wl-paste --watch cliphist store" \
    "swaybg -i $HOME/.config/wall.png -m fill" elephant; do
    hyprctl dispatch "hl.dsp.exec_cmd(\"$c\")" > /dev/null
  done
fi
# the old sync's units are gone now: no "failed" left behind in systemctl --user
systemctl --user daemon-reload
systemctl --user reset-failed rebuild-snapshot.service rebuild-snapshot.timer 2> /dev/null || true

echo "==> 5. check"
git -C "$DRIFTLESS" status --short | head -20
cat << EOF

Done in the home. The previous live files are in ~/.local/state/driftless/backup/ (newest folder).
Changed notes and anything else that differs from the repository shows in
  git -C $DRIFTLESS status
and the sync commits edits to tracked files (driftless sync --now).

Root part (system drop-ins, login screen, old kit files out of /etc), in a terminal:
  sudo bash $DRIFTLESS/install/migrate-system.sh
EOF
