#!/usr/bin/env bats
# system/files/usr/lib/driftless/install-packages: the only thing the sync may run as root

setup() {
  T=$BATS_TEST_TMPDIR
  mkdir -p "$T/usr/bin"
  printf '#!/bin/sh\necho "pacman $*"\n' > "$T/usr/bin/pacman"
  chmod +x "$T/usr/bin/pacman"
  # the helper sets PATH=/usr/bin; run a copy that points at the stub instead
  sed "s#^export PATH=/usr/bin#export PATH=$T/usr/bin:/usr/bin#" \
    "$BATS_TEST_DIRNAME/../system/files/usr/lib/driftless/install-packages" > "$T/helper"
  HELPER=$T/helper
}

@test "refuses to run without packages" {
  run bash "$HELPER"
  [ "$status" -eq 2 ]
}

@test "refuses options, paths and URLs" {
  for bad in -U --config /tmp/x.pkg.tar.zst https://example.com/p "a;b" ../x; do
    run bash "$HELPER" "$bad"
    [ "$status" -eq 2 ]
  done
}

@test "passes plain names to pacman -S --needed after --" {
  run bash "$HELPER" steam lib32-mesa
  [ "$output" = "pacman -S --needed --noconfirm -- steam lib32-mesa" ]
}
