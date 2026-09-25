#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh - turns a base install (install-base.sh, or any Arch with btrfs, systemd-boot, network
# and a user in wheel) into a driftless machine. Safe to run again.
#
#   sudo bash ~/.local/share/driftless/install/bootstrap.sh [--no-aur] [--review-aur]
#
# Root part: pacman.conf, mirrors, upgrade, the packages of this machine's groups, driftless-system,
# initramfs and boot, services, snapper, firewall. User part: driftless setup, AUR packages.
# Ends with driftless verify.
# =============================================================================
set -uo pipefail
DRIFTLESS=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
USERNAME=${SUDO_USER:-}
DO_AUR=1 REVIEW_AUR=0 FAILED=()
while (($#)); do
  case $1 in
    --no-aur) DO_AUR=0 ;;
    --review-aur) REVIEW_AUR=1 ;;
    -u) USERNAME=$2 && shift ;;
    -h | --help) sed -n '2,11p' "$0" && exit 0 ;;
    *) echo "unknown option: $1" && exit 1 ;;
  esac
  shift
done
[[ $EUID -eq 0 ]] || { echo "run as root: sudo bash $0" && exit 1; }
[[ -n $USERNAME && $USERNAME != root ]] || { echo "run it with sudo from your account, or pass -u USER" && exit 1; }
[[ -f /etc/arch-release ]] || { echo "not Arch Linux" && exit 1; }
HOME_DIR=$(getent passwd "$USERNAME" | cut -d: -f6)
UGRP=$(id -gn "$USERNAME")
# the library works with the user's state folder, not root's. HOME stays root's: with the user's HOME,
# root processes (pacman hooks, fc-cache ...) would create root-owned folders in the user's home.
export DRIFTLESS_STATE=$HOME_DIR/.local/state/driftless
# shellcheck source=lib/common.sh
source "$DRIFTLESS/lib/common.sh"
for lib in packages boot; do
  # shellcheck source=/dev/null
  source "$DRIFTLESS/lib/$lib.sh"
done
load_config

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
fail() {
  warn "$*"
  FAILED+=("$*")
}
as_user() { runuser -u "$USERNAME" -- env HOME="$HOME_DIR" "$@"; }

for _ in 1 2 3 4 5; do
  if ping -c1 -W5 archlinux.org > /dev/null 2>&1; then break; fi
  sleep 2
done
ping -c1 -W5 archlinux.org > /dev/null 2>&1 || die "no network: connect first (nmtui)"

# git refuses a repository owned by someone else (a copy made as root)
find "$DRIFTLESS" ! -user "$USERNAME" -print -quit | grep -q . && chown -R "$USERNAME:$UGRP" "$DRIFTLESS"

# AUR packages are built as the user and installed with the user's sudo. Ask for that password now
# and keep the ticket alive until the AUR step is done; it ends at the latest a minute after this
# script. runuser starts no new terminal, so every later call sees the ticket.
KEEPALIVE=""
if ((DO_AUR)) && [[ -n $(wanted | awk '$1 == "aur"') ]]; then
  echo "The AUR step installs as $USERNAME with sudo. Password for $USERNAME, once:"
  if as_user sudo -v; then
    (while kill -0 $$ 2> /dev/null; do
      as_user sudo -n -v 2> /dev/null
      sleep 60
    done) &
    KEEPALIVE=$!
    trap '[[ -n $KEEPALIVE ]] && kill $KEEPALIVE 2> /dev/null; as_user sudo -k' EXIT
  fi
fi

# ---------------------------------------------------------------- pacman
step "pacman: multilib, parallel downloads, mirrors, upgrade"
cp -n /etc/pacman.conf /etc/pacman.conf.bak-driftless
sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
grep -q '^\[multilib\]' /etc/pacman.conf || sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
grep -q '^\[multilib\]' /etc/pacman.conf || die "multilib could not be enabled"
install -Dm644 /dev/stdin /etc/driftless/reflector <<< "REFLECTOR_COUNTRY=${REFLECTOR_COUNTRY:-}"
pacman -Sy --needed --noconfirm archlinux-keyring reflector || fail "reflector"
reflector --save /etc/pacman.d/mirrorlist --protocol https --latest 20 --sort rate \
  ${REFLECTOR_COUNTRY:+--country "$REFLECTOR_COUNTRY"} || warn "reflector failed, keeping the mirror list"
pacman -Syu --noconfirm || die "system upgrade failed"

facts > /dev/null
echo "   $(hw_summary)"
echo "   facts: $(facts | xargs)"

# ---------------------------------------------------------------- Surface repository
if has_fact surface && ! grep -q '^\[linux-surface\]' /etc/pacman.conf; then
  step "Surface: repository pkg.surfacelinux.com (key fingerprint checked)"
  key=$DRIFTLESS/install/surface-signing-key.gpg fpr=87DEFA4AB94A99A4C8C3112556C464BAAC421453
  if [[ $(gpg --show-keys --with-colons "$key" 2> /dev/null | awk -F: '$1 == "fpr" { print $10; exit }') == "$fpr" ]] &&
    pacman-key --add "$key" && pacman-key --lsign-key "$fpr"; then
    printf '\n[linux-surface]\nServer = https://pkg.surfacelinux.com/arch/\n' >> /etc/pacman.conf
    pacman -Sy
  else
    fail "Surface signing key missing or wrong fingerprint: no linux-surface"
  fi
fi

# ---------------------------------------------------------------- packages
mapfile -t REPO < <(wanted | awk '$1 == "repo" { print $2 }')
step "packages: ${#REPO[@]} from the groups $(manifest group | paste -sd' ')"
if ! pacman -S --needed --noconfirm -- "${REPO[@]}"; then
  warn "batch install failed, retrying one by one"
  for p in "${REPO[@]}"; do pacman -S --needed --noconfirm -- "$p" > /dev/null || fail "pacman: $p"; done
fi

# ---------------------------------------------------------------- initramfs and boot
step "initramfs and boot"
mapfile -t KMS < <(hw_early_modules)
if ((${#KMS[@]})); then
  install -Dm644 /dev/stdin /etc/mkinitcpio.conf.d/10-gpu.conf <<< "# driftless: early KMS for the boot splash
MODULES=(${KMS[*]})"
else
  rm -f /etc/mkinitcpio.conf.d/10-gpu.conf
fi
plymouth-set-default-theme bgrt 2> /dev/null || fail "plymouth theme"
if [[ -s /etc/kernel/cmdline ]]; then
  uki_presets # kernels installed just now (linux-lts, linux-surface) build UKIs too
  has_fact surface && [[ -f /etc/mkinitcpio.d/linux-surface.preset ]] && uki_loader arch-linux-surface.efi
else
  warn "classic boot entries: kept as they are (a new install with install-base.sh uses unified kernel images)"
fi

# ---------------------------------------------------------------- driftless-system
step "driftless-system (drop-ins, greeter, helpers); builds as $USERNAME"
if pkg=$(as_user "$DRIFTLESS/driftless" system --build-only 2> /dev/null | tail -1) && [[ -f $pkg ]]; then
  pacman -U --needed --noconfirm "$pkg" || fail "driftless-system install"
else
  fail "driftless-system build"
fi
# with a new hooks line the package rebuilt every image; without, rebuild once for 10-gpu.conf
mkinitcpio -P > /dev/null || fail "mkinitcpio"

# ---------------------------------------------------------------- services, snapshots, firewall
step "services"
while read -r unit; do systemctl enable -q "$unit" || fail "enable $unit"; done < <(manifest unit)
systemctl enable -q systemd-boot-update.service 2> /dev/null || true
systemctl set-default graphical.target > /dev/null

if [[ $(findmnt -no FSTYPE /) == btrfs ]]; then
  step "snapper: root and home"
  for cfg in root:/ home:/home; do
    name=${cfg%%:*} path=${cfg#*:}
    [[ -f /etc/snapper/configs/$name ]] && continue
    if [[ $name == root ]] && findmnt -n /.snapshots > /dev/null; then
      # the @snapshots subvolume is mounted at /.snapshots; snapper wants to make its own
      umount /.snapshots && rmdir /.snapshots
      snapper -c root create-config / || fail "snapper root"
      btrfs subvolume delete /.snapshots > /dev/null && mkdir /.snapshots && mount /.snapshots && chmod 750 /.snapshots
    else
      snapper -c "$name" create-config "$path" || {
        fail "snapper $name"
        continue
      }
    fi
    snapper -c "$name" set-config TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes NUMBER_CLEANUP=yes \
      TIMELINE_LIMIT_HOURLY=5 TIMELINE_LIMIT_DAILY=7 TIMELINE_LIMIT_WEEKLY=2 TIMELINE_LIMIT_MONTHLY=1 TIMELINE_LIMIT_YEARLY=0
  done
  systemctl enable -q snapper-timeline.timer snapper-cleanup.timer
fi

step "firewall (only when not set up yet: an active one keeps its rules)"
if ! grep -q '^ENABLED=yes' /etc/ufw/ufw.conf 2> /dev/null; then
  if ! { ufw default deny incoming && ufw default allow outgoing && ufw --force enable; } > /dev/null; then
    fail "ufw"
  fi
fi

# ---------------------------------------------------------------- user part
# anything root created in the home up to here belongs to the user
chown -R "$USERNAME:$UGRP" "$HOME_DIR"/.config "$HOME_DIR"/.local "$HOME_DIR"/.cache 2> /dev/null
step "driftless setup (as $USERNAME)"
as_user "$DRIFTLESS/driftless" setup || fail "driftless setup"
# the login screen shows this user's wallpaper, colours and avatar (set-wallpaper does it later on)
/usr/lib/driftless/greeter-update "$HOME_DIR/.cache/theme" || fail "login screen theme"
# and offers this user the uwsm session first: ReGreet's own memory of the last choice, seeded once
session=$(sed -n 's/^Name=//p' /usr/share/wayland-sessions/hyprland-uwsm.desktop 2> /dev/null | head -1)
if [[ -n $session && ! -s /var/lib/regreet/state.toml ]]; then
  install -d -o greeter -g greeter /var/lib/regreet
  printf 'last_user = "%s"\n\n[user_to_last_sess]\n%s = "%s"\n' "$USERNAME" "$USERNAME" "$session" |
    install -o greeter -g greeter -m644 /dev/stdin /var/lib/regreet/state.toml
fi
chown -R "$USERNAME:$UGRP" "$HOME_DIR/.config" "$HOME_DIR/.local" "$HOME_DIR/.cache" 2> /dev/null

if ((DO_AUR)); then
  mapfile -t AUR < <(wanted | awk '$1 == "aur" { print $2 }')
  step "AUR: yay + ${#AUR[@]} packages"
  ((REVIEW_AUR)) || warn "AUR packages are built without showing their PKGBUILDs. To read them first: --review-aur"
  if ! command -v yay > /dev/null; then
    for pkg in yay-bin yay; do
      # shellcheck disable=SC2016 # expanded by the inner bash
      as_user bash -c '
        set -e; d=$(mktemp -d); cd "$d"
        git clone -q --depth=1 "https://aur.archlinux.org/$1.git" && cd "$1"
        if (( $2 )); then ${PAGER:-less} PKGBUILD; read -rp "Build $1? [y/N] " a; [[ $a == [yY]* ]]; fi
        # makepkg would call "sudo -k pacman", which ignores the ticket: plain sudo instead
        conf=$(mktemp); printf "source /etc/makepkg.conf\nPACMAN_AUTH=(sudo)\n" > "$conf"
        makepkg --config "$conf" -si --noconfirm --needed' _ "$pkg" "$REVIEW_AUR" && break
    done
    command -v yay > /dev/null || fail "yay bootstrap"
  fi
  if command -v yay > /dev/null && ((${#AUR[@]})); then
    if ((REVIEW_AUR)); then
      YAY=(yay -S --needed --removemake --answerclean None --answerdiff All --answeredit None)
    else
      YAY=(yay -S --needed --noconfirm --removemake --answerclean None --answerdiff None --answeredit None)
    fi
    as_user "${YAY[@]}" -- "${AUR[@]}" || for p in "${AUR[@]}"; do as_user "${YAY[@]}" -- "$p" || fail "aur: $p"; done
  fi
fi

[[ -f /etc/snapper/configs/root ]] && snapper -c root create -d "driftless bootstrap" 2> /dev/null

step "driftless verify (as $USERNAME)"
as_user "$DRIFTLESS/driftless" verify || warn "verify reported FAIL lines, see above"
echo
if ((${#FAILED[@]})); then
  warn "these steps had problems:"
  printf '   - %s\n' "${FAILED[@]}"
else
  echo "Everything went through."
fi
cat << EOF

Next: reboot, pick "Hyprland (uwsm-managed)" at the login screen. Then, once:
  * trust this machine on your others: their sync pill offers it ("Trust new machine")
  * personal data (SSH keys, browser and mail profiles, games) from your own backup
  * encrypted disk: let the TPM unlock it, see docs/encryption.md
EOF
