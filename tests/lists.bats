#!/usr/bin/env bats
# lib/lists.sh: how one machine's snapshot changes the lists and files shared by all machines

setup() {
  source "$BATS_TEST_DIRNAME/../lib/lists.sh"
  cd "$BATS_TEST_TMPDIR"
}

@test "merge_list: adds what was installed here, drops what was removed here" {
  printf 'a\nb\nc\n' > list
  printf 'a\nb\n' > base # this machine had a and b
  printf 'b\nd\n' > now  # removed a, installed d
  merge_list list now base
  run cat list
  [ "$output" = "$(printf 'b\nc\nd')" ] # c belongs to another machine and stays
  run cat base
  [ "$output" = "$(printf 'b\nd')" ]
}

@test "merge_list: first run without a base removes nothing" {
  printf 'a\nc\n' > list
  printf 'b\n' > now
  merge_list list now base
  run cat list
  [ "$output" = "$(printf 'a\nb\nc')" ]
}

@test "guard_deletions: a file this machine never had is put back" {
  git init -q repo && cd repo
  mkdir -p files/home/.config/khal
  echo x > files/home/.config/khal/config
  git add -A && git -c user.name=t -c user.email=t@t commit -q -m init
  rm -rf files/home/.config/khal # this machine has no khal
  guard_deletions "$BATS_TEST_TMPDIR/base" files/home
  [ -f files/home/.config/khal/config ]
}

@test "guard_deletions: a file this machine had and deleted stays deleted" {
  git init -q repo && cd repo
  mkdir -p files/home/.config/khal
  echo x > files/home/.config/khal/config
  git add -A && git -c user.name=t -c user.email=t@t commit -q -m init
  echo files/home/.config/khal/config > "$BATS_TEST_TMPDIR/base"
  rm -rf files/home/.config/khal
  guard_deletions "$BATS_TEST_TMPDIR/base" files/home
  [ ! -e files/home/.config/khal/config ]
  run cat "$BATS_TEST_TMPDIR/base"
  [ "$output" = "" ]
}

@test "guard_deletions: a DIR that does not exist is fine (the notes folder is optional)" {
  git init -q repo && cd repo
  mkdir -p files/home
  echo x > files/home/a
  git add -A && git -c user.name=t -c user.email=t@t commit -q -m init
  set -o pipefail
  guard_deletions "$BATS_TEST_TMPDIR/base" files/home files/docs
  run cat "$BATS_TEST_TMPDIR/base"
  [ "$output" = files/home/a ]
}

@test "filter_dconf: drops window geometry and sections left empty" {
  run filter_dconf << 'EOF'
[org/gnome/desktop/interface]
gtk-theme='Adwaita-dark'

[org/gnome/nautilus/window-state]
maximized=true
window-size=(800, 600)

[org/gnome/nautilus/preferences]
show-hidden=true
sidebar-width=200
EOF
  [ "$output" = "$(printf "[org/gnome/desktop/interface]\ngtk-theme='Adwaita-dark'\n\n[org/gnome/nautilus/preferences]\nshow-hidden=true")" ]
}

@test "MACHINE_LOCAL covers every file theme/apply.py renders" {
  local dest
  while read -r dest; do
    machine_local "files/home/.config/$dest"
  done < <(python3 -c 'import importlib.util as u, sys
s = u.spec_from_file_location("apply", sys.argv[1]); m = u.module_from_spec(s); s.loader.exec_module(m)
print("\n".join(list(m.TARGETS.values()) + ["theme/colors.json", "wall.png", "wlogout/icons/lock-hover.png"]))' \
    "$BATS_TEST_DIRNAME/../files/home/.config/theme/apply.py")
  run machine_local files/home/.config/wlogout/icons/lock.png
  [ "$status" -ne 0 ]
}
