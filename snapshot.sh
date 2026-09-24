#!/usr/bin/env bash
# Records this machine's live state in the kit: package lists, dotfiles, dconf, VS Code, /etc copies.
# Run as your normal user; the sync (auto-snapshot.sh) runs it at the start of every run.
set -euo pipefail
export LC_ALL=C # one sort order for the shared lists on every machine and in every session
cd "$(dirname "$(readlink -f "$0")")"
# per machine memory of the last snapshot (package lists, kit files, /etc checksums), see lib/lists.sh
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/rebuild"
mkdir -p "$STATE"
source "$PWD/lib/lists.sh"
source "$PWD/kit.conf"

# hardware specific packages (microcode, GPU drivers, notebook extras) are chosen per machine by
# restore.sh (lib/hardware.sh) and must not travel with the list
source "$PWD/lib/hardware.sh"
echo "==> package lists"
# the lists are shared by all machines: only what was (un)installed here since the last snapshot changes them
pacman -Qqen | grep -Ev "$HW_PKG_REGEX" > "$STATE/pacman.now"
merge_list packages/pacman.txt "$STATE/pacman.now" "$STATE/pacman.base"
# yay-debug is a build by-product; yay itself is bootstrapped by restore.sh
# grep finds nothing on a machine without AUR packages, which is fine (pipefail would stop here)
pacman -Qqem | { grep -vx 'yay-debug' || true; } > "$STATE/aur.now"
merge_list packages/aur.txt "$STATE/aur.now" "$STATE/aur.base"
wc -l packages/*.txt

echo "==> dotfiles -> files/home"
rm -rf files/home && mkdir -p files/home/.config files/home/.local/share/applications
CONFIG_DIRS=(hypr emoji waybar wlogout mako walker ghostty qt6ct gtk-3.0 gtk-4.0 theme nwg-displays autostart yay vdirsyncer khal systemd)
for d in "${CONFIG_DIRS[@]}"; do [[ -e $HOME/.config/$d ]] && cp -a "$HOME/.config/$d" files/home/.config/; done
for f in starship.toml wall.png mimeapps.list user-dirs.dirs user-dirs.locale QtProject.conf; do
  [[ -e $HOME/.config/$f ]] && cp -a "$HOME/.config/$f" files/home/.config/
done
# a user-dirs.dirs whose folders all point at bare $HOME/ (xdg-user-dirs-update ran before the folders
# existed) must not end up in the kit: keep the committed one instead
# shellcheck disable=SC2016 # a literal $HOME in the file
if grep -q '^XDG_DOWNLOAD_DIR="\$HOME/"$' files/home/.config/user-dirs.dirs 2> /dev/null; then
  git show HEAD:files/home/.config/user-dirs.dirs > files/home/.config/user-dirs.dirs 2> /dev/null || rm -f files/home/.config/user-dirs.dirs
fi
cp -a "$HOME/.bashrc" "$HOME/.bash_profile" files/home/
mkdir -p files/home/.config/Code/User
cp -a "$HOME/.config/Code/User/settings.json" files/home/.config/Code/User/ 2> /dev/null || true
# custom launchers (no game-/profile-bound ones)
for f in "$HOME"/.local/share/applications/*.desktop; do
  case "$(basename "$f")" in net.lutris.* | Baldur* | brave-*) continue ;; esac
  cp -a "$f" files/home/.local/share/applications/
done
# no backup copies in the kit
find files/home \( -name '*.bak*' -o -name 'bak_*' \) -prune -exec rm -rf {} +

# project notes (KIT_NOTES_REL in kit.conf; they live outside the kit)
if [[ -n ${KIT_NOTES_REL:-} ]]; then
  NOTES="$HOME/$KIT_NOTES_REL"
  [[ -r $NOTES/CLAUDE.md ]] && cp -a "$NOTES/CLAUDE.md" files/CLAUDE.md
  if [[ -d $NOTES/docs ]]; then
    rm -rf files/docs
    cp -a "$NOTES/docs" files/docs
  fi
fi
# a kit file missing here was only deleted if this machine had it before (lib/lists.sh)
guard_deletions "$STATE/files.base" files/home files/docs

echo "==> dconf + VS Code extensions"
dconf dump / | filter_dconf > files/dconf.ini
# an empty answer (VS Code missing or broken) must not count as "every extension removed"
if code --list-extensions > "$STATE/vscode.now" 2> /dev/null && [[ -s $STATE/vscode.now ]]; then
  merge_list packages/vscode-extensions.txt "$STATE/vscode.now" "$STATE/vscode.base"
fi

echo "==> /etc files (readable ones)"
# /etc is never applied to the other machines, so their copies may be old: a live file only goes
# into the kit when it changed here since the last snapshot (or the kit has none yet)
: > "$STATE/etc.sha256.new"
take_sys() { # take_sys LIVE KITPATH MODE
  local live=$1 kit=$2 mode=$3 old
  [[ -r $live ]] || return 0
  old=$(awk -v p="$live" '$2 == p { print $1 }' "$STATE/etc.sha256" 2> /dev/null || true)
  if [[ ! -e $kit || (-n $old && $old != "$(sha256sum < "$live" | cut -d' ' -f1)") ]]; then
    install -Dm"$mode" "$live" "$kit"
  fi
  sha256sum "$live" >> "$STATE/etc.sha256.new"
}
for f in sysctl.d/99-gaming.conf greetd/config.toml greetd/regreet.toml greetd/regreet.css greetd/avatar.png security/limits.d/10-games.conf \
  xdg/reflector/reflector.conf NetworkManager/conf.d/hostname.conf \
  systemd/zram-generator.conf systemd/coredump.conf.d/10-limit.conf smartd.conf \
  pam.d/greetd locale.conf vconsole.conf; do
  take_sys "/etc/$f" "files/etc/$f" 644
done
# the hostname differs per machine by design; the kit's copy is only restore.sh's fallback name
[[ -e files/etc/hostname ]] || install -Dm644 /etc/hostname files/etc/hostname
# smartd hook (notifies via mako) lives outside /etc
take_sys /usr/local/bin/smartd-notify files/usr/local/bin/smartd-notify 755
# the sync's password-guarded package installer (pkexec) and its polkit action
take_sys /usr/local/bin/rebuild-install files/usr/local/bin/rebuild-install 755
take_sys /usr/share/polkit-1/actions/org.rebuild.install.policy files/usr/share/polkit-1/actions/org.rebuild.install.policy 644
# login screen background used by ReGreet
take_sys /usr/share/backgrounds/login.png files/usr/share/backgrounds/login.png 644
mv "$STATE/etc.sha256.new" "$STATE/etc.sha256"
echo "Done. Snapshot at $(date -Is)"
