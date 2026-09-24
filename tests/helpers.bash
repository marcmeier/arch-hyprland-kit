# shellcheck shell=bash
# Test sandbox: a bare repository as "GitHub" and machines with their own fake home, all under
# $BATS_TEST_TMPDIR. System tools the kit calls (pacman, dconf, notify-send, ...) are stubs.

KIT_SRC=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
# where the kit lives in a home, as the sync's systemd unit starts it
KIT_REL=$(sed -n 's#^ExecStart=%h/\(.*\)/auto-snapshot.sh$#\1#p' "$KIT_SRC/files/home/.config/systemd/user/rebuild-snapshot.service")

setup_sandbox() {
  T=$BATS_TEST_TMPDIR
  mkdir -p "$T/bin"
  local c
  for c in notify-send pkexec hyprctl makoctl systemd-run setsid pkill zip systemctl; do
    printf '#!/bin/sh\nexit 0\n' > "$T/bin/$c"
  done
  printf '#!/bin/sh\nexit 1\n' > "$T/bin/code" # VS Code not installed
  # pacman: repo packages from $PACMAN_REPO, AUR packages from $PACMAN_AUR (space separated)
  cat > "$T/bin/pacman" << 'EOF'
#!/bin/sh
case "$1" in
  -Qqen) printf '%s\n' ${PACMAN_REPO:-base git} ;;
  -Qqem) [ -n "${PACMAN_AUR-yay}" ] && printf '%s\n' ${PACMAN_AUR-yay} ;;
  -Qq) printf '%s\n' ${PACMAN_REPO:-base git} ${PACMAN_AUR-yay} ;;
esac
exit 0
EOF
  # dconf: "dump" prints $HOME/dconf.live, "load" replaces it
  cat > "$T/bin/dconf" << 'EOF'
#!/bin/sh
case "$1" in
  dump) cat "$HOME/dconf.live" 2> /dev/null ;;
  load) cat > "$HOME/dconf.live" ;;
esac
EOF
  chmod +x "$T"/bin/*
  export PATH="$T/bin:$PATH"
  export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
  export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
  export GIT_CONFIG_GLOBAL=/dev/null

  # "GitHub", seeded with the kit as it is in the working tree
  git init -q --bare -b main "$T/origin.git"
  mkdir "$T/seed"
  (cd "$KIT_SRC" && git ls-files -co --exclude-standard -z | xargs -0 cp --parents -a -t "$T/seed")
  sed -i 's#^KIT_ZIP=.*#KIT_ZIP=""#' "$T/seed/kit.conf"
  git -C "$T/seed" init -q -b main
  git -C "$T/seed" add -A
  git -C "$T/seed" commit -q -m seed
  git -C "$T/seed" push -q "$T/origin.git" main
}

# machine NAME: a fake home with the kit cloned where the unit expects it and every kit file live
machine() {
  local home=$T/$1/home
  mkdir -p "$home"
  git clone -q "$T/origin.git" "$home/$KIT_REL"
  cp -a "$home/$KIT_REL/files/home/." "$home/"
  printf '[org/gnome/desktop/interface]\ngtk-theme=Adwaita-dark\n\n[org/gnome/nautilus/window-state]\nwindow-size=(800, 600)\nmaximized=false\n' > "$home/dconf.live"
}

# sync_on NAME [ARGS]: one run of auto-snapshot.sh on machine NAME
sync_on() {
  local m=$1
  shift
  HOME="$T/$m/home" XDG_STATE_HOME="$T/$m/state" "$T/$m/home/$KIT_REL/auto-snapshot.sh" "$@"
}

home() { echo "$T/$1/home"; }
state() { cat "$T/$1/state/rebuild/$2" 2> /dev/null; }
result() { state "$1" status | sed -n 's/^result=//p'; }
on_github() { git -C "$T/origin.git" cat-file -e "main:$1" 2> /dev/null; }
github_file() { git -C "$T/origin.git" show "main:$1"; }
github_has() { github_file "$1" | grep -qF -- "$2"; }
# refute CMD...: fails when CMD succeeds (a plain "! CMD" never fails a bats test)
refute() { if "$@"; then return 1; fi; }
