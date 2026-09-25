# shellcheck shell=bash
# driftless setup: everything a machine needs in the home, as the user. Safe to run again.
# install/bootstrap.sh runs it at the end of a new install; an existing machine runs it once to join.

# enable_user_unit UNIT: "systemctl --user enable", also without a running user manager (the bootstrap
# runs as root before the first login): then the [Install] symlinks are made by hand.
enable_user_unit() {
  local unit=$1 file target
  if systemctl --user show-environment > /dev/null 2>&1; then
    systemctl --user enable -q "$unit" 2> /dev/null && return 0
  fi
  for file in "$HOME/.config/systemd/user/$unit" /etc/systemd/user/"$unit" /usr/lib/systemd/user/"$unit"; do
    [[ -f $file ]] && break
  done
  [[ -f $file ]] || {
    warn "user unit $unit not found"
    return 1
  }
  # shellcheck disable=SC2013 # WantedBy= lists names separated by spaces
  for target in $(sed -n 's/^WantedBy=//p' "$file"); do
    mkdir -p "$HOME/.config/systemd/user/$target.wants"
    ln -sfn "$file" "$HOME/.config/systemd/user/$target.wants/$unit"
  done
}

setup_units() {
  local unit session=0
  systemctl --user is-active -q graphical-session.target 2> /dev/null && session=1
  while read -r unit; do
    enable_user_unit "$unit" || continue
    # timers and session services start right away when there is a session; else at the next login
    if ((session)) || [[ $unit == *.timer ]]; then
      systemctl --user start "$unit" 2> /dev/null || true
    fi
  done < <(manifest user-unit)
  systemctl --user daemon-reload 2> /dev/null || true
}

cmd_setup() {
  load_config
  say "links"
  cmd_link
  say "commit signing"
  signing_setup
  say "theme"
  [[ -f $HOME/.config/wall.png ]] || cp "$HOME/.config/theme/default-wallpaper.jpg" "$HOME/.config/wall.png" 2> /dev/null || true
  python3 "$HOME/.config/theme/apply.py" --current > /dev/null || warn "theme not rendered (later: set-wallpaper --current)"
  say "GNOME/GTK settings"
  if command -v dconf > /dev/null; then
    dbus-run-session -- dconf load / < "$DRIFTLESS/dconf.ini" 2> /dev/null ||
      dconf load / < "$DRIFTLESS/dconf.ini" || warn "dconf not loaded"
  fi
  say "folders"
  mkdir -p "$HOME"/{Desktop,Downloads,Documents,Music,Pictures,Videos,Templates,Public,Projects,Games}
  say "user units"
  setup_units
  echo "done. Check with: driftless verify"
}

# driftless dconf capture: write this machine's values of the sections in dconf.ini back into it
cmd_dconf() {
  case ${1:-} in
    load) dconf load / < "$DRIFTLESS/dconf.ini" ;;
    capture)
      local section out
      out=$(mktemp)
      grep '^#' "$DRIFTLESS/dconf.ini" > "$out"
      while read -r section; do
        printf '[%s]\n' "$section"
        dconf dump "/$section/" | grep -v '^\[' | grep .
        echo
      done < <(sed -n 's/^\[\(.*\)\]$/\1/p' "$DRIFTLESS/dconf.ini") >> "$out"
      sed -i '${/^$/d}' "$out"
      mv "$out" "$DRIFTLESS/dconf.ini"
      git -C "$DRIFTLESS" diff --stat -- dconf.ini
      ;;
    *) die "usage: driftless dconf load|capture" ;;
  esac
}
