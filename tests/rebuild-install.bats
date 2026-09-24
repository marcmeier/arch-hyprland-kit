#!/usr/bin/env bats
# files/usr/local/bin/rebuild-install runs as root via pkexec: only plain package names may pass

INSTALL="$BATS_TEST_DIRNAME/../files/usr/local/bin/rebuild-install"

@test "refuses to run without packages" {
  run bash "$INSTALL"
  [ "$status" -eq 2 ]
}

@test "refuses options, paths and URLs" {
  local arg
  for arg in -U --config=/tmp/x --hookdir /tmp/evil.pkg.tar.zst https://example.com/x.pkg.tar.zst 'a;b' 'A'; do
    run bash "$INSTALL" firefox "$arg"
    [ "$status" -eq 2 ]
    [[ $output == *"not a package name"* ]]
  done
}

@test "passes plain names to pacman -S --needed after --" {
  grep -q 'exec pacman -S --needed --noconfirm -- "\$@"' "$INSTALL"
}
