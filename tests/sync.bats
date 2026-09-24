#!/usr/bin/env bats
# auto-snapshot.sh between two machines A and B and a bare repository as GitHub (helpers.bash)

setup() {
  load helpers
  setup_sandbox
  machine A
  machine B
}

# khal is the example of a config folder that only A has
give_A_khal() {
  mkdir -p "$(home A)/.config/khal"
  echo "[calendars]" > "$(home A)/.config/khal/config"
  rm -rf "$(home B)/.config/khal"
  sync_on A --now
}

@test "a first run on a fresh clone succeeds" {
  run sync_on A --now
  [ "$status" -eq 0 ]
  [ "$(result A)" = ok ]
}

@test "snapshot works on a machine without AUR packages" {
  PACMAN_AUR="" run sync_on A --now
  [ "$status" -eq 0 ]
  [ "$(result A)" = ok ]
}

@test "the sync works without a notes folder, as in the public template" {
  cd "$(home A)/$KIT_REL"
  sed -i 's/^KIT_NOTES_REL=.*/KIT_NOTES_REL=""/' kit.conf
  git rm -rq --ignore-unmatch files/docs files/CLAUDE.md
  git add -A
  git diff --cached --quiet || git commit -qm "no notes folder" # the template has none already
  run sync_on A --now
  [ "$status" -eq 0 ]
  [ "$(result A)" = ok ]
}

@test "a config folder one machine never had is not deleted on the others" {
  give_A_khal
  on_github files/home/.config/khal/config
  sync_on B --now
  on_github files/home/.config/khal/config
  sync_on A --now
  [ -f "$(home A)/.config/khal/config" ]
}

@test "a real deletion reaches the other machines, with a backup" {
  give_A_khal
  sync_on B --adopt # B takes over khal
  [ -f "$(home B)/.config/khal/config" ]
  rm -rf "$(home B)/.config/khal"
  sync_on B --now
  refute on_github files/home/.config/khal/config
  sync_on A --now
  [ ! -e "$(home A)/.config/khal/config" ]
  ls "$T"/A/state/rebuild/backup/*/.config/khal/config
}

@test "review first (default): incoming changes wait until Sync now" {
  sync_on B --now
  echo "-- test: from A" >> "$(home A)/.config/hypr/hyprland.lua"
  sync_on A --now
  cp "$(home B)/.config/hypr/hyprland.lua" "$T/before.lua"
  sync_on B
  [ "$(result B)" = held ]
  cmp "$T/before.lua" "$(home B)/.config/hypr/hyprland.lua"
  sync_on B --now
  grep -qF -- "-- test: from A" "$(home B)/.config/hypr/hyprland.lua"
  ls "$T"/B/state/rebuild/backup/*/.config/hypr/hyprland.lua
}

@test "same lines changed on both machines: stop, name the file, change nothing" {
  sync_on B --now
  echo "-- test: A says hi" >> "$(home A)/.config/hypr/hyprland.lua"
  sync_on A --now
  echo "-- test: B says hi" >> "$(home B)/.config/hypr/hyprland.lua"
  run sync_on B --now
  [ "$status" -ne 0 ]
  [ "$(result B)" = conflict ]
  [ "$(state B conflict)" = files/home/.config/hypr/hyprland.lua ]
  grep -qF -- "-- test: B says hi" "$(home B)/.config/hypr/hyprland.lua" # not overwritten
  github_has files/home/.config/hypr/hyprland.lua "-- test: A says hi"
  [ ! -e "$(home B)/$KIT_REL/.git/MERGE_HEAD" ] # merge aborted cleanly
}

@test "the sync pill names the conflicting file" {
  sync_on B --now
  echo "-- test: A" >> "$(home A)/.config/hypr/hyprland.lua"
  sync_on A --now
  echo "-- test: B" >> "$(home B)/.config/hypr/hyprland.lua"
  sync_on B --now || true
  run env HOME="$(home B)" XDG_STATE_HOME="$T/B/state" python3 "$(home B)/.config/waybar/sync.py"
  [[ $output == *'"class": "error"'* ]]
  [[ $output == *hyprland.lua* ]]
}

@test "window geometry stays out of the kit" {
  sync_on A --now
  refute github_has files/dconf.ini window-size
  github_has files/dconf.ini gtk-theme
}

@test "only the last 10 backups are kept" {
  sync_on B --now
  mkdir -p "$T/B/state/rebuild/backup"
  local i
  for i in $(seq -w 1 15); do mkdir "$T/B/state/rebuild/backup/2000-01-${i}T000000"; done
  echo "-- test: change" >> "$(home A)/.config/hypr/hyprland.lua"
  sync_on A --now
  sync_on B --now
  [ "$(ls "$T/B/state/rebuild/backup" | wc -l)" -eq 10 ]
  ls "$T/B/state/rebuild/backup" | grep -qv '^2000-' # the new one is among them
}

@test "mode off: the timer does nothing" {
  mkdir -p "$T/A/state/rebuild"
  echo off > "$T/A/state/rebuild/mode"
  echo "-- test: local change" >> "$(home A)/.config/hypr/hyprland.lua"
  sync_on A
  [ "$(result A)" = paused ]
  refute github_has files/home/.config/hypr/hyprland.lua "-- test: local change"
}
