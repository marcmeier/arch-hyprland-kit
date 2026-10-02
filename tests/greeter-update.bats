#!/usr/bin/env bats
# system/files/usr/lib/driftless/greeter-update: runs as root without a password (polkit), so it must
# only ever copy what the caller could read itself

setup() {
  T=$BATS_TEST_TMPDIR
  mkdir -p "$T/usr/bin" "$T/theme" "$T/out"
  # setpriv: records the switch, then runs the command after "--" (as the test user)
  cat > "$T/usr/bin/setpriv" << STUB
#!/bin/sh
echo "\$*" >> "$T/setpriv.log"
while [ "\$1" != "--" ]; do shift; done
shift
exec "\$@"
STUB
  chmod +x "$T/usr/bin/setpriv"
  # a copy of the helper that writes to $T/out and finds the stub first
  sed -e "s#^export PATH=/usr/bin#export PATH=$T/usr/bin:/usr/bin#" \
    -e "s#^out=.*#out=$T/out#" \
    -e "s#/usr/share/driftless/greetd/regreet.toml#$BATS_TEST_DIRNAME/../system/files/usr/share/driftless/greetd/regreet.toml#" \
    "$BATS_TEST_DIRNAME/../system/files/usr/lib/driftless/greeter-update" > "$T/helper"
  HELPER=$T/helper
  echo "css" > "$T/theme/regreet.css"
  echo '{"primary": "#112233"}' > "$T/theme/colors.json"
  echo "png" > "$T/theme/login.png"
  echo "png" > "$T/theme/avatar.png"
}

@test "without a theme folder only regreet.toml is written" {
  run bash "$HELPER"
  [ "$status" -eq 0 ]
  [ -f "$T/out/regreet.toml" ]
  [ ! -e "$T/out/login.png" ]
}

@test "copies the theme files, readable by the greeter" {
  PKEXEC_UID=$(id -u) run bash "$HELPER" "$T/theme"
  [ "$status" -eq 0 ]
  for f in login.png colors.json regreet.css avatar.png; do
    cmp "$T/theme/$f" "$T/out/$f"
    [ "$(stat -c %a "$T/out/$f")" = 644 ]
  done
}

@test "reads with the caller's rights when called through pkexec or sudo" {
  PKEXEC_UID=$(id -u) run bash "$HELPER" "$T/theme"
  grep -q -- "--reuid=$(id -u) " "$T/setpriv.log"
  rm "$T/setpriv.log"
  SUDO_UID=$(id -u) run bash "$HELPER" "$T/theme"
  grep -q -- "--reuid=$(id -u) " "$T/setpriv.log"
}

@test "called by root directly, it reads without switching" {
  env -u PKEXEC_UID -u SUDO_UID bash "$HELPER" "$T/theme"
  [ ! -e "$T/setpriv.log" ]
  cmp "$T/theme/login.png" "$T/out/login.png"
  [ ! -e "$T/out/user" ]
}

@test "the caller's account comes first on the login screen" {
  SUDO_UID=$(id -u) run bash "$HELPER" "$T/theme"
  [ "$status" -eq 0 ]
  [ "$(cat "$T/out/user")" = "$(id -nu)" ]
  [ "$(stat -c %a "$T/out/user")" = 644 ]
}

@test "skips links, so nothing else ends up on the login screen" {
  rm "$T/theme/login.png"
  ln -s /etc/passwd "$T/theme/login.png"
  PKEXEC_UID=$(id -u) run bash "$HELPER" "$T/theme"
  [ "$status" -eq 0 ]
  [ ! -e "$T/out/login.png" ]
  [ -f "$T/out/avatar.png" ]
}

@test "skips files over 64 MiB and leaves no partial file" {
  truncate -s 65M "$T/theme/login.png"
  PKEXEC_UID=$(id -u) run bash "$HELPER" "$T/theme"
  [ "$status" -eq 0 ]
  [ ! -e "$T/out/login.png" ]
  [ ! -e "$T/out/login.png.new" ]
}

@test "refuses a caller id that is not a number" {
  PKEXEC_UID='0;x' run bash "$HELPER" "$T/theme"
  [ "$status" -ne 0 ]
  [ ! -e "$T/out/login.png" ]
}
