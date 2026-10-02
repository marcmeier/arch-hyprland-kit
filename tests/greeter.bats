#!/usr/bin/env bats
# system/files/usr/lib/driftless/greeter: the Quickshell greeter, and ReGreet when it fails, so a
# broken greeter never keeps anyone out

setup() {
  T=$BATS_TEST_TMPDIR
  mkdir -p "$T/usr/bin" "$T/share" "$T/run"
  touch "$T/share/shell.qml"
  # cage runs what follows "--" and logs it; quickshell exits with $QS_EXIT
  printf '#!/bin/sh\nwhile [ "$1" != "--" ]; do shift; done\nshift\necho "$*" >> "%s/cage.log"\nexec "$@"\n' "$T" > "$T/usr/bin/cage"
  printf '#!/bin/sh\necho "$QT_WAYLAND_DISABLE_WINDOWDECORATION" > "%s/decoration"\nexit "${QS_EXIT:-0}"\n' "$T" > "$T/usr/bin/quickshell"
  printf '#!/bin/sh\nexit 0\n' > "$T/usr/bin/regreet"
  chmod +x "$T/usr/bin/"*
  sed -e "s#^export PATH=/usr/bin#export PATH=$T/usr/bin:/usr/bin#" \
    -e "s#/usr/share/driftless/greeter#$T/share#g" \
    "$BATS_TEST_DIRNAME/../system/files/usr/lib/driftless/greeter" > "$T/greeter"
}

@test "starts the Quickshell greeter, its cache in the runtime dir" {
  XDG_RUNTIME_DIR=$T/run run bash "$T/greeter"
  [ "$status" -eq 0 ]
  [ "$(cat "$T/cage.log")" = "quickshell -p $T/share" ]
  [ -d "$T/run" ]
  # no title bar or frame drawn by Qt around the screen
  [ "$(cat "$T/decoration")" = 1 ]
}

@test "falls back to ReGreet when the greeter fails" {
  QS_EXIT=1 XDG_RUNTIME_DIR=$T/run run bash "$T/greeter"
  [ "$status" -eq 0 ]
  grep -q '^quickshell ' "$T/cage.log"
  grep -q '^regreet --config /var/lib/driftless/greeter/regreet.toml' "$T/cage.log"
}

@test "goes straight to ReGreet without the greeter's files" {
  rm "$T/share/shell.qml"
  XDG_RUNTIME_DIR=$T/run run bash "$T/greeter"
  [ "$(cat "$T/cage.log")" = "regreet --config /var/lib/driftless/greeter/regreet.toml --style /var/lib/driftless/greeter/regreet.css" ]
}
