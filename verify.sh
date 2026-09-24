#!/usr/bin/env bash
# verify.sh - read-only check: does this machine match what the kit should have produced?
# Run as your NORMAL user (no sudo):  bash verify.sh (in the kit folder)
# Exit code = number of FAIL lines. WARN = worth a look, INFO = expected differences.
# restore.sh runs it automatically at the end.
# ok/warn/info always return 0, so "COND && ok ... || fail ..." works as if/else in this file
# shellcheck disable=SC2015
set -u
KIT="$(dirname "$(readlink -f "$0")")"
# shellcheck source=lib/hardware.sh
source "$KIT/lib/hardware.sh"
[[ $EUID -ne 0 ]] || {
  echo "run as your normal user, not root"
  exit 1
}
hw_detect
FAILS=0
WARNS=0
# small helpers so every check below is a single readable line
ok() { printf '  \033[32mOK\033[0m    %s\n' "$*"; }
fail() {
  printf '  \033[1;31mFAIL\033[0m  %s\n' "$*"
  FAILS=$((FAILS + 1))
}
warn() {
  printf '  \033[33mWARN\033[0m  %s\n' "$*"
  WARNS=$((WARNS + 1))
}
info() { printf '  INFO  %s\n' "$*"; }
sec() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }

sec "1. Home directory ownership and permissions"
[[ $(stat -c %U "$HOME") == "$USER" ]] && ok "$HOME belongs to $USER" || fail "$HOME is owned by $(stat -c %U "$HOME")  ->  sudo chown $USER:$(id -gn) $HOME"
n=$(find "$HOME" -xdev \( ! -user "$USER" \) 2> /dev/null | wc -l)
if ((n == 0)); then ok "everything below \$HOME belongs to $USER"; else
  fail "$n entries below \$HOME not owned by $USER  ->  sudo chown -R $USER:$(id -gn) $HOME"
  find "$HOME" -xdev ! -user "$USER" 2> /dev/null | head -5 | sed 's/^/          /'
fi
[[ -w $HOME && -w $HOME/.cache && -w $HOME/.config && -w $HOME/.local ]] && ok "\$HOME, .cache, .config, .local are writable" || fail ".cache/.config/.local missing or not writable"

sec "2. Packages"
mapfile -t HWP < <(hw_packages)
# comm -23: lines only in the kit's list, i.e. packages the kit expects but pacman doesn't have
miss=$(comm -23 <(sort -u "$KIT/packages/pacman.txt" | grep .) <(pacman -Qq | sort))
[[ -z $miss ]] && ok "all $(grep -c . "$KIT/packages/pacman.txt") pacman packages installed" || { fail "missing pacman packages: $(paste -sd" " <<< "$miss")"; }
miss=$(comm -23 <(sort -u "$KIT/packages/aur.txt" | grep .) <(pacman -Qqm | sort))
[[ -z $miss ]] && ok "all $(grep -c . "$KIT/packages/aur.txt") AUR packages installed" || fail "missing AUR packages: $(paste -sd" " <<< "$miss")"
miss=""
for p in "${HWP[@]}"; do [[ -n $p ]] && ! pacman -Qq "$p" > /dev/null 2>&1 && miss+="$p "; done
[[ -z $miss ]] && ok "hardware packages present ($(hw_summary))" || fail "missing hardware packages: $miss"
for c in yay elephant walker; do command -v "$c" > /dev/null && ok "command $c" || fail "command $c not found"; done

sec "3. Dotfiles from the kit (files/home -> \$HOME)"
missing=0
differ=0
DL=()
while IFS= read -r f; do
  f="${f#./}"
  if [[ ! -e $HOME/$f ]]; then
    fail "missing: ~/$f"
    missing=$((missing + 1))
  elif ! cmp -s "$KIT/files/home/$f" "$HOME/$f"; then
    differ=$((differ + 1))
    DL+=("$f")
  fi
done < <(cd "$KIT/files/home" && find . -type f ! -name '*.bak*')
((missing == 0)) && ok "all kit dotfiles exist"
((differ)) && info "$differ files differ from the kit (normal: wallpaper theme, monitor/battery patches, later edits): ${DL[*]:0:8}"

sec "4. System files from the kit (files/etc -> /etc)"
while IFS= read -r f; do
  # hostname is expected to differ (see restore.sh step 5)
  f="${f#./}"
  [[ $f == hostname ]] && continue
  # the greeter greets with this machine's hostname (restore.sh step 6), so that line may differ
  if [[ ! -e /etc/$f ]]; then
    fail "missing: /etc/$f"
  elif [[ $f == greetd/regreet.toml ]] && cmp -s <(grep -v '^greeting_msg = ' "$KIT/files/etc/$f") <(grep -v '^greeting_msg = ' "/etc/$f"); then
    :
  elif ! cmp -s "$KIT/files/etc/$f" "/etc/$f"; then warn "differs from kit: /etc/$f"; fi
done < <(cd "$KIT/files/etc" && find . -type f)
[[ -x /usr/local/bin/smartd-notify ]] && ok "smartd-notify installed" || fail "/usr/local/bin/smartd-notify missing"
[[ -s /usr/share/backgrounds/login.png ]] && ok "login background present" || fail "/usr/share/backgrounds/login.png missing"

sec "5. Services"
for u in NetworkManager bluetooth greetd systemd-timesyncd ufw smartd snapper-timeline.timer snapper-cleanup.timer paccache.timer reflector.timer; do
  systemctl is-enabled "$u" > /dev/null 2>&1 && ok "enabled: $u" || fail "not enabled: $u"
done
((HW_LAPTOP)) && { systemctl is-enabled power-profiles-daemon > /dev/null 2>&1 && ok "enabled: power-profiles-daemon" || fail "not enabled: power-profiles-daemon"; }
for u in vdirsyncer.timer rebuild-snapshot.timer; do
  # a plain file instead of the *.target.wants/ symlink disables the timer without any error
  systemctl --user is-enabled "$u" > /dev/null 2>&1 && ok "enabled: $u" || fail "not enabled: $u (check for a non-symlink file in ~/.config/systemd/user/timers.target.wants/)"
done
# the passwordless pacman rule of older kit versions must be gone (it made any process of this user
# root). Checked by its effect, since the user cannot read /etc/sudoers.d; -k ignores a cached login.
if sudo -n -k pacman -V > /dev/null 2>&1; then
  fail "pacman runs without password (rule of an older kit version)  ->  sudo rm -f /etc/sudoers.d/90-rebuild-sync /etc/sudoers.d/10-rebuild-sync /etc/sudoers.d/99-restore-nopasswd"
fi
if cmp -s "$KIT/files/usr/local/bin/rebuild-install" /usr/local/bin/rebuild-install &&
  [[ -e /usr/share/polkit-1/actions/org.rebuild.install.policy ]]; then
  ok "kit sync can install packages (pkexec rebuild-install, with password)"
else fail "rebuild-install or its polkit action missing or outdated, the sync cannot install packages  ->  see README"; fi
# signed kit commits (lib/signing.sh): without them, whoever can push to the repo feeds this machine
ST=${XDG_STATE_HOME:-$HOME/.local/state}/rebuild
if [[ $(git -C "$KIT" config commit.gpgsign) == true && -f $HOME/.ssh/rebuild-signing && -s $ST/allowed_signers ]] &&
  grep -qF "$(awk '{ print $2 }' "$HOME/.ssh/rebuild-signing.pub")" "$ST/allowed_signers"; then
  ok "kit commits are signed and checked ($(grep -c . "$ST/allowed_signers") trusted machine(s))"
else warn "commit signing not set up: the sync takes over whatever is on GitHub  ->  bash $KIT/lib/signing.sh setup"; fi
f=$(systemctl --failed --no-legend 2> /dev/null | awk '{print $2}' | tr '\n' ' ')
[[ -z $f ]] && ok "no failed system units" || warn "failed system units: $f"
f=$(systemctl --user --failed --no-legend 2> /dev/null | awk '{print $2}' | tr '\n' ' ')
[[ -z $f ]] && ok "no failed user units" || warn "failed user units: $f"

sec "6. Boot"
E=/boot/loader/entries
[[ -f $E/arch.conf ]] && ok "arch.conf exists" || fail "arch.conf missing"
grep -q '\bsplash\b' $E/arch.conf 2> /dev/null && ok "arch.conf has quiet splash" || warn "arch.conf lacks splash"
[[ -f /boot/vmlinuz-linux-lts ]] && { [[ -f $E/arch-lts.conf ]] && ok "arch-lts.conf exists" || fail "arch-lts.conf missing"; }
# every boot entry must point at kernel/initrd files that actually exist on disk
for e in "$E"/*.conf; do
  while read -r i; do
    [[ -f /boot$i ]] || fail "$(basename "$e"): initrd /boot$i does not exist"
  done < <(awk '$1=="initrd"{print $2}' "$e")
  k=$(awk '$1=="linux"{print $2}' "$e")
  [[ -f /boot$k ]] || fail "$(basename "$e"): kernel /boot$k does not exist"
done
if ((HW_SURFACE)); then
  pacman -Qq linux-surface > /dev/null 2>&1 && ok "linux-surface kernel installed" || fail "linux-surface kernel missing"
  pacman -Qq iptsd > /dev/null 2>&1 && ok "iptsd installed (touch/pen)" || warn "iptsd missing"
  [[ -f $E/arch-surface.conf ]] && ok "arch-surface.conf exists" || fail "arch-surface.conf missing"
  [[ $(uname -r) == *surface* ]] && ok "running the Surface kernel ($(uname -r))" || warn "not running the Surface kernel ($(uname -r)); reboot or pick it in the boot menu"
fi
for e in "$E"/*surface*.conf; do [[ -f $e ]] && { grep -q '\bsplash\b' "$e" && ok "$(basename "$e") has splash" || warn "$(basename "$e") lacks quiet splash"; }; done
grep -q '^timeout 0' /boot/loader/loader.conf 2> /dev/null && ok "boot menu hidden (hold Space)" || info "loader timeout is not 0"

sec "7. User setup"
for d in Projects Games; do [[ -d $HOME/$d ]] && ok "$HOME/$d" || fail "$HOME/$d missing"; done
miss=""
for d in Desktop Downloads Documents Music Pictures Videos Templates Public; do [[ -d $HOME/$d ]] || miss+="$d "; done
[[ -z $miss ]] && ok "standard folders (Desktop, Downloads, Documents, ...)" || fail "missing standard folders: $miss ->  xdg-user-dirs-update"
t=$(gsettings get org.gnome.desktop.interface gtk-theme 2> /dev/null)
[[ -n $t ]] && ok "GTK theme: $t" || warn "gsettings unavailable (no session bus?)"
diff -q <(sort "$KIT/packages/vscode-extensions.txt") <(code --list-extensions 2> /dev/null | sort) > /dev/null 2>&1 && ok "VS Code extensions match" || warn "VS Code extensions differ or code not runnable"
[[ -L $HOME/.local/bin/set-wallpaper ]] && ok "set-wallpaper link" || fail "$HOME/.local/bin/set-wallpaper missing"
snapper list-configs 2> /dev/null | grep -q '^root' && ok "snapper config root" || warn "snapper config root not visible (needs root?)"
source "$KIT/kit.conf"
if [[ -n ${KIT_NOTES_REL:-} ]]; then
  [[ -f $HOME/$KIT_NOTES_REL/CLAUDE.md ]] && ok "$HOME/$KIT_NOTES_REL/CLAUDE.md" || warn "$HOME/$KIT_NOTES_REL/CLAUDE.md missing"
fi

printf '\n\033[1m%d FAIL, %d WARN\033[0m\n' "$FAILS" "$WARNS"
exit "$FAILS"
