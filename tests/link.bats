#!/usr/bin/env bats
# lib/link.sh: the home is made of links into the repository

setup() {
  load helpers
  setup_sandbox
  mkdir -p "$(home A)/.local/share"
  git clone -q "$T/origin.git" "$(repo A)"
}

@test "a fresh home gets a link for every manifest line" {
  run dl A link
  [ "$status" -eq 0 ]
  [ "$(readlink "$(home A)/.config/hypr")" = "$(repo A)/home/.config/hypr" ]
  [ "$(readlink "$(home A)/.bashrc")" = "$(repo A)/home/.bashrc" ]
  [ "$(readlink "$(home A)/.local/bin/driftless")" = "$(repo A)/driftless" ]
}

@test "an edit in the home is an edit in the repository" {
  dl A link
  echo "-- edited" >> "$(home A)/.config/hypr/hyprland.lua"
  git -C "$(repo A)" diff --quiet && false
  git -C "$(repo A)" diff | grep -q -- "-- edited"
}

@test "a host folder is linked only on its host" {
  mkdir -p "$(repo A)/hosts/A"
  echo "-- A" > "$(repo A)/hosts/A/hyprland.lua"
  dl A link
  [ -f "$(home A)/.config/driftless/host/hyprland.lua" ]
  [ ! -e "$(home A)/.config/driftless/host/nothing" ]
}

@test "existing files are moved to a backup, files only the machine had are kept" {
  mkdir -p "$(home A)/.config/hypr"
  echo old > "$(home A)/.config/hypr/hyprland.lua"
  echo mine > "$(home A)/.config/hypr/only-here.conf"
  run dl A link
  [ "$status" -eq 0 ]
  [ -L "$(home A)/.config/hypr" ]
  [ "$(cat "$(home A)/.config/hypr/only-here.conf")" = mine ]
  ls "$T"/A/state/driftless/backup/*/.config/hypr/hyprland.lua
  grep -qx old "$T"/A/state/driftless/backup/*/.config/hypr/hyprland.lua
}

@test "the same file already in place needs no backup" {
  cp "$(repo A)/home/.bashrc" "$(home A)/.bashrc"
  dl A link
  [ -L "$(home A)/.bashrc" ]
  refute ls "$T"/A/state/driftless/backup/*/.bashrc
}

@test "a link a program replaced by a file is healed: its content goes into the repository" {
  dl A link
  rm "$(home A)/.config/mimeapps.list"
  echo "[Default Applications]" > "$(home A)/.config/mimeapps.list"
  run dl A link
  [[ $output == *healed* ]]
  [ -L "$(home A)/.config/mimeapps.list" ]
  [ "$(cat "$(repo A)/home/.config/mimeapps.list")" = "[Default Applications]" ]
}

@test "--adopt: on the first run the live file wins" {
  echo "live notes" > "$(home A)/.bashrc"
  dl A link --adopt
  [ -L "$(home A)/.bashrc" ]
  [ "$(cat "$(repo A)/home/.bashrc")" = "live notes" ]
}

@test "--adopt TARGET: only that target keeps its live version" {
  echo "live notes" > "$(home A)/.bashrc"
  echo "live profile" > "$(home A)/.bash_profile"
  dl A link --adopt .bashrc
  [ "$(cat "$(repo A)/home/.bashrc")" = "live notes" ]
  [ "$(cat "$(repo A)/home/.bash_profile")" != "live profile" ]
  grep -qx "live profile" "$T"/A/state/driftless/backup/*/.bash_profile
}

@test "a link that left the manifest is removed" {
  dl A link
  sed -i '/^link .config\/emoji$/d' "$(repo A)/manifest"
  run dl A link
  [[ $output == *"unlinked: ~/.config/emoji"* ]]
  [ ! -e "$(home A)/.config/emoji" ]
}

@test "--dry-run changes nothing" {
  run dl A link --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"link: ~/.config/hypr"* ]]
  [ ! -e "$(home A)/.config/hypr" ]
}

@test "link_problems names a missing link" {
  dl A link
  rm "$(home A)/.config/waybar"
  run dl A status
  [[ $output == *"~/.config/waybar is missing"* ]]
}
