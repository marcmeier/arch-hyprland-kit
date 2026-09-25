#!/usr/bin/env bats
# lib/sync.sh between two machines A and B and a bare repository as GitHub (helpers.bash)

setup() {
  load helpers
  setup_sandbox
  machine A
  machine B
  trust_all A B
  dl A mode auto > /dev/null
  dl B mode auto > /dev/null
  # both machines publish their signing key once
  dl A sync > /dev/null
  dl B sync > /dev/null
  dl A sync > /dev/null
}

hypr() { echo "$(home "$1")/.config/hypr/hyprland.lua"; }

@test "an edit on A reaches B's live config through its link" {
  echo "-- from A" >> "$(hypr A)"
  run dl A sync
  [ "$status" -eq 0 ]
  [ "$(result A)" = ok ]
  github_has home/.config/hypr/hyprland.lua "-- from A"
  dl B sync
  grep -qx -- "-- from A" "$(hypr B)"
}

@test "the commit names the machine and what changed, and is signed" {
  echo "-- x" >> "$(hypr A)"
  dl A sync
  run git -C "$T/origin.git" log -1 --format='%s|%(trailers:key=Driftless-Host,valueonly,separator=)' main
  [ "$output" = "A: hypr/hyprland.lua|A" ]
  # checked where the list of trusted keys is: on B
  run git -C "$(repo B)" -c gpg.ssh.allowedSignersFile="$T/B/state/driftless/allowed_signers" log -1 --format=%G? origin/main
  [ "$output" = G ]
}

@test "a new file is never committed by itself" {
  echo "secret stuff" > "$(home A)/.config/hypr/new-file.conf"
  dl A sync
  refute on_github home/.config/hypr/new-file.conf
}

@test "a staged change that looks like a secret stops the run, nothing committed" {
  echo 'token = "ghp_abcdefghijklmnopqrstuvwxyz0123456789"' >> "$(hypr A)"
  run dl A sync
  [ "$status" -ne 0 ]
  [ "$(result A)" = secret ]
  refute github_has home/.config/hypr/hyprland.lua ghp_
  [ -z "$(git -C "$(repo A)" diff --cached --name-only)" ]
}

@test "review mode (default): incoming changes wait until sync --now" {
  dl B mode review
  echo "-- from A" >> "$(hypr A)"
  dl A sync
  dl B sync
  [ "$(result B)" = held ]
  refute grep -qx -- "-- from A" "$(hypr B)"
  dl B sync --now
  grep -qx -- "-- from A" "$(hypr B)"
}

@test "mode off: the timer does nothing" {
  dl B mode off
  echo "-- x" >> "$(hypr B)"
  dl B sync
  [ "$(result B)" = paused ]
  refute github_has home/.config/hypr/hyprland.lua "-- x"
}

@test "edits on both machines in different places: linear history, both arrive" {
  echo "-- from A" >> "$(hypr A)"
  echo "# from B" >> "$(home B)/.bashrc"
  dl A sync
  dl B sync
  dl A sync
  grep -qx -- "# from B" "$(home A)/.bashrc"
  grep -qx -- "-- from A" "$(hypr B)"
  [ -z "$(git -C "$T/origin.git" log --merges --format=%h main)" ]
}

@test "the same line changed on both: stop, name the file, change nothing" {
  sed -i '1s/.*/-- A was here/' "$(hypr A)"
  sed -i '1s/.*/-- B was here/' "$(hypr B)"
  dl A sync
  run dl B sync
  [ "$status" -ne 0 ]
  [ "$(result B)" = conflict ]
  grep -qx home/.config/hypr/hyprland.lua "$T/B/state/driftless/conflict"
  [ "$(head -1 "$(hypr B)")" = "-- B was here" ]
  [ -z "$(git -C "$(repo B)" status --porcelain -- home)" ] # nothing half-applied
}

@test "a commit nobody's machine signed is not taken over" {
  git clone -q "$T/origin.git" "$T/intruder"
  echo "-- evil" >> "$T/intruder/home/.config/hypr/hyprland.lua"
  git -C "$T/intruder" -c user.name=x -c user.email=x@x commit -qam evil
  git -C "$T/intruder" push -q origin main
  dl B sync
  [ "$(result B)" = untrusted ]
  refute grep -q evil "$(hypr B)"
}

@test "a new machine's commits wait until it is trusted" {
  machine C
  echo "-- from C" >> "$(hypr C)"
  dl C mode auto
  dl C sync
  dl A sync
  [ "$(result A)" = joining ]
  refute grep -q "from C" "$(hypr A)"
}

@test "a deletion reaches the other machine" {
  rm "$(home A)/.config/hypr/emoji-picker.sh"
  dl A sync
  refute on_github home/.config/hypr/emoji-picker.sh
  dl B sync
  [ ! -e "$(home B)/.config/hypr/emoji-picker.sh" ]
}

@test "a program replaced a linked file: its content is committed and the link restored" {
  rm "$(home A)/.config/mimeapps.list"
  echo "[Default Applications]" > "$(home A)/.config/mimeapps.list"
  dl A sync
  [ -L "$(home A)/.config/mimeapps.list" ]
  github_has home/.config/mimeapps.list "[Default Applications]"
}

@test "a new manifest line from A is linked on B" {
  mkdir -p "$(repo A)/home/.config/newapp"
  echo x > "$(repo A)/home/.config/newapp/config"
  echo "link .config/newapp" >> "$(repo A)/manifest"
  git -C "$(repo A)" add -A && git -C "$(repo A)" commit -qm "newapp"
  dl A sync
  dl B sync
  [ -L "$(home B)/.config/newapp" ]
}

@test "a new package in a list asks for the password once, AUR packages wait" {
  echo "newpkg" >> "$(repo A)/packages/desktop.list"
  echo "aur:newaur" >> "$(repo A)/packages/desktop.list"
  dl A sync
  mkdir -p "$(home B)/.."
  # driftless-system is "installed" in this test
  mkdir -p "$T/usr-lib" && touch "$T/usr-lib/install-packages"
  PACMAN_PKGS="$(cat "$(repo B)"/packages/*.list | grep -v '^#' | grep -v '^aur:' | grep -vx newpkg)" dl B sync
  grep -qx "aur newaur" "$T/B/state/driftless/install-pending"
  grep -qx "repo newpkg" "$T/B/state/driftless/install-pending"
}
