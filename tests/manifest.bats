#!/usr/bin/env bats
# lib/common.sh (manifest, facts) and lib/packages.sh (groups)

setup() {
  load helpers
  setup_sandbox
  mkdir -p "$(home A)/.local/share"
  git clone -q "$T/origin.git" "$(repo A)"
  R=$(repo A)
  cat > "$R/manifest" << 'M'
# comment
link .a
link .b some/where   # trailing comment
link .c hosts/{host}/c
group one
group two if=laptop
group three if=!laptop
group four if=host:A
unit x.service if=cpu-amd
M
  printf '# header\nfoo\naur:bar  # built from the AUR\n' > "$R/packages/one.list"
  printf 'three\n' > "$R/packages/three.list"
  printf 'laptop-only\n' > "$R/packages/two.list"
  printf 'four\n' > "$R/packages/four.list"
  rm -rf "$R/personal"
}

lib() { HOME=$(home A) DRIFTLESS_HOST=A bash -c "DRIFTLESS=$(repo A); source $(repo A)/lib/common.sh; source $(repo A)/lib/packages.sh; $1"; }

@test "manifest: kinds, default sources, {host} and comments" {
  run lib "manifest link"
  [ "${lines[0]}" = ".a" ]
  [ "${lines[1]}" = ".b some/where" ]
  [ "${lines[2]}" = ".c hosts/A/c" ]
}

@test "manifest: if= picks by fact, negation and host" {
  run lib "manifest group"
  [ "$output" = "$(printf 'one\nthree\nfour')" ]
  run lib "manifest unit"
  [ "$output" = x.service ]
}

@test "manifest: a laptop gets its group" {
  mkdir -p "$T/hw/sys/class/power_supply/BAT0"
  run lib "manifest group"
  [[ $output == *two* ]]
  [[ $output != *three* ]]
}

@test "manifest: the personal and host layers add lines" {
  mkdir -p "$(repo A)/personal" "$(repo A)/hosts/A"
  echo "group p" > "$(repo A)/personal/manifest"
  echo "group h" > "$(repo A)/hosts/A/manifest"
  run lib "manifest group"
  [[ $output == *p* && $output == *h* ]]
}

@test "wanted: repo and AUR packages of the machine's groups, comments dropped" {
  run lib wanted
  [ "$output" = "$(printf 'aur bar\nrepo foo\nrepo four\nrepo three')" ]
}

@test "missing and unlisted" {
  PACMAN_PKGS="foo extra" run lib "missing repo"
  [ "$output" = "$(printf 'four\nthree')" ]
  PACMAN_PKGS="foo extra" run lib unlisted
  [ "$output" = extra ]
}

@test "unlisted leaves out the AUR helper and driftless-system" {
  PACMAN_PKGS="foo four three yay-bin driftless-system" PACMAN_AUR="bar" run lib unlisted
  [ -z "$output" ]
}

@test "packages add keeps the header and the order, marks AUR packages" {
  PACMAN_AUR="newaur" run lib "cmd_packages add newaur one"
  [ "$status" -eq 0 ]
  [ "$(head -1 "$(repo A)/packages/one.list")" = "# header" ]
  grep -qx 'aur:newaur' "$(repo A)/packages/one.list"
}

@test "packages remove takes a package out of every list" {
  lib "cmd_packages remove foo"
  refute grep -qx foo "$(repo A)/packages/one.list"
}
