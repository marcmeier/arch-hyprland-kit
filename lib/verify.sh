# shellcheck shell=bash
# driftless verify: read-only check of whether this machine is what the repository describes.
# Runs as the user, without sudo. Exit code = number of FAIL lines.
# Every list it checks comes from the manifest, the same one bootstrap and setup act on.

# ok/warn/info return 0, so "COND && ok ... || fail ..." reads as if/else here
# shellcheck disable=SC2015
cmd_verify() {
  local FAILS=0 WARNS=0 p unit miss failed
  ok() { printf '  \033[32mOK\033[0m    %s\n' "$*"; }
  fail() {
    printf '  \033[1;31mFAIL\033[0m  %s\n' "$*"
    FAILS=$((FAILS + 1))
  }
  warn_() {
    printf '  \033[33mWARN\033[0m  %s\n' "$*"
    WARNS=$((WARNS + 1))
  }
  info() { printf '  INFO  %s\n' "$*"; }
  sec() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
  [[ $EUID -ne 0 ]] || die "run as your normal user, not root"
  facts > /dev/null

  sec "Machine"
  info "$HOST: $(hw_summary)"
  info "facts: $(facts | xargs)"

  sec "Home"
  [[ $(stat -c %U "$HOME") == "$USER" ]] && ok "$HOME belongs to $USER" || fail "$HOME is owned by $(stat -c %U "$HOME")  ->  sudo chown $USER: $HOME"
  p=$(find "$HOME" -xdev -maxdepth 3 ! -user "$USER" 2> /dev/null | head -3)
  [[ -z $p ]] && ok "nothing near the top of \$HOME belongs to someone else" || fail "not yours: $(paste -sd' ' <<< "$p")"

  sec "Links"
  p=$(link_problems)
  [[ -z $p ]] && ok "all $(link_entries | grep -c .) links point into $DRIFTLESS" || while IFS= read -r l; do fail "$l"; done <<< "$p"
  p=$(git -C "$DRIFTLESS" status --porcelain --untracked-files=normal -- home personal hosts | head -5)
  [[ -z $p ]] && ok "no untracked or uncommitted files in the linked folders" ||
    info "not committed yet (the next sync commits edits, never new files): $(awk '{ print $2 }' <<< "$p" | paste -sd' ')"

  sec "Packages"
  miss=$(missing repo | paste -sd' ')
  [[ -z $miss ]] && ok "all repo packages of the groups $(manifest group | paste -sd' ')" || fail "missing: $miss  ->  driftless packages install"
  miss=$(missing aur | paste -sd' ')
  [[ -z $miss ]] && ok "all AUR packages" || fail "missing AUR: $miss  ->  driftless packages install"
  miss=$(unlisted | paste -sd' ')
  [[ -z $miss ]] && ok "every installed package is in a list" || info "installed, in no list: $miss  (driftless packages add NAME)"

  sec "System"
  if pacman -Qq driftless-system > /dev/null 2>&1; then
    local have want
    have=$(pacman -Q driftless-system | awk '{ print $2 }')
    want=$(system_version)
    [[ ${have%-*} == "$want" ]] && ok "driftless-system $have" || warn_ "driftless-system $have, the repository has $want  ->  driftless system"
  else
    fail "driftless-system not installed  ->  driftless system"
  fi
  while read -r unit; do
    systemctl is-enabled -q "$unit" 2> /dev/null && ok "enabled: $unit" || fail "not enabled: $unit"
  done < <(manifest unit)
  if systemctl --user show-environment > /dev/null 2>&1; then
    while read -r unit; do
      systemctl --user is-enabled -q "$unit" 2> /dev/null && ok "enabled (user): $unit" || fail "not enabled (user): $unit  ->  driftless setup"
    done < <(manifest user-unit)
  else
    info "no user manager (not logged in graphically): user units not checked"
  fi
  failed=$(systemctl --failed --no-legend --plain 2> /dev/null | awk '{ print $1 }' | paste -sd' ' || true)
  [[ -z $failed ]] && ok "no failed system units" || warn_ "failed system units: $failed"
  if systemctl --user show-environment > /dev/null 2>&1; then
    failed=$(systemctl --user --failed --no-legend --plain 2> /dev/null | awk '{ print $1 }' | paste -sd' ' || true)
    [[ -z $failed ]] && ok "no failed user units" || warn_ "failed user units: $failed"
  fi
  if sudo -n -k true 2> /dev/null; then
    fail "sudo works without a password here: any program of yours can become root"
  fi

  sec "Boot and disk"
  if compgen -G '/boot/EFI/Linux/*.efi' > /dev/null; then
    ok "unified kernel images: $(find /boot/EFI/Linux -name '*.efi' -printf '%f ' 2> /dev/null)"
  elif [[ -d /boot/loader/entries ]]; then
    info "classic boot entries (a new install uses unified kernel images, see docs/boot.md)"
    local entry kernel
    for entry in /boot/loader/entries/*.conf; do
      [[ -r $entry ]] || continue
      kernel=$(awk '$1 == "linux" { print $2 }' "$entry")
      [[ -z $kernel || -f /boot$kernel ]] || fail "$(basename "$entry"): kernel /boot$kernel does not exist"
    done
  fi
  if lsblk -rno TYPE 2> /dev/null | grep -qx crypt; then
    ok "the system disk is encrypted"
  elif has_fact laptop; then
    warn_ "notebook without disk encryption: whoever takes it has your data (install-base.sh --encrypt)"
  else
    info "no disk encryption"
  fi

  sec "Sync"
  [[ $(git -C "$DRIFTLESS" config commit.gpgsign) == true && -s $ALLOWED ]] &&
    ok "commits are signed and checked ($(grep -c . "$ALLOWED") trusted machine(s))" ||
    warn_ "commit signing not set up: the sync would take over anything pushed to GitHub  ->  driftless setup"
  if systemctl --user show-environment > /dev/null 2>&1; then
    systemctl --user is-enabled -q driftless-sync.timer && ok "sync timer enabled (mode: $(cat "$STATE/mode" 2> /dev/null || echo review))" || warn_ "sync timer not enabled"
  fi
  [[ -r $STATE/status ]] && info "last sync: $(sed -n 's/^result=//p' "$STATE/status"), $(date -d "@$(sed -n 's/^time=//p' "$STATE/status")" '+%F %H:%M')"
  [[ -f $HOME/.config/theme/colors.json ]] && ok "theme rendered" || fail "theme not rendered  ->  set-wallpaper --current"

  printf '\n\033[1m%d FAIL, %d WARN\033[0m\n' "$FAILS" "$WARNS"
  return "$FAILS"
}
