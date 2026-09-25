#!/usr/bin/env bash
# =============================================================================
# restore.sh - rebuilds this setup (Arch, Hyprland, gaming stack, theme)
# on top of a MINIMAL Arch install (btrfs, systemd-boot, network working,
# a normal user in group wheel).
#
#   sudo bash restore.sh [-u USERNAME] [--no-aur] [--review-aur] [--no-snapshot]
#
# Idempotent: safe to run multiple times. Existing user configs are moved to
# <file>.bak-restore before being replaced.
# Not part of the kit (personal data): Steam library, Brave/Thunderbird
# profiles, SSH keys, keyrings, Nextcloud login. See README.md.
# =============================================================================
set -uo pipefail

KIT="$(dirname "$(readlink -f "$0")")"
# shellcheck source=lib/hardware.sh
source "$KIT/lib/hardware.sh"
source "$KIT/kit.conf"
USERNAME="${SUDO_USER:-}" # the user who called sudo; -u overrides
DO_AUR=1
REVIEW_AUR=0
DO_SNAP=1
FAILED=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -u)
      USERNAME="$2"
      shift 2
      ;;
    --no-aur)
      DO_AUR=0
      shift
      ;;
    --review-aur)
      REVIEW_AUR=1
      shift
      ;;
    --no-snapshot)
      DO_SNAP=0
      shift
      ;;
    -h | --help)
      sed -n '2,13p' "$0"
      exit 0
      ;;
    *)
      echo "unknown option: $1"
      exit 1
      ;;
  esac
done

# say: section header · warn: non-fatal problem · fail: the same, also listed in the summary
say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!  %s\033[0m\n' "$*"; }
fail() {
  warn "$*"
  FAILED+=("$*")
}

# ---------------------------------------------------------------- preflight checks
[[ -n $USERNAME && $USERNAME != root ]] || {
  echo "Run it via sudo from your own account, or pass -u USERNAME."
  exit 1
}
[[ $EUID -eq 0 ]] || {
  echo "Run as root: sudo bash $0"
  exit 1
}
[[ -f /etc/arch-release ]] || {
  echo "This is not Arch Linux."
  exit 1
}
[[ -d $KIT/files && -d $KIT/packages ]] || {
  echo "Kit incomplete: $KIT"
  exit 1
}
# DHCP/DNS may still be coming up right after boot
for _ in 1 2 3 4 5; do
  ping -c1 -W5 archlinux.org > /dev/null 2>&1 && break
  sleep 2
done
ping -c1 -W5 archlinux.org > /dev/null 2>&1 || {
  echo "No network/DNS. Connect first (nmtui / iwctl)."
  exit 1
}

# AUR packages are built as the user (makepkg refuses root) and installed with the user's sudo.
# Ask for that password now, while you are here, and keep the ticket alive until the AUR step is
# done. runuser, unlike sudo, starts no new pseudo-terminal, so every later call sees this ticket.
# The keepalive stops at the latest a minute after this script ends, however it ends.
as_user() { runuser -u "$USERNAME" -- env HOME="$HOME_DIR" "$@"; }
SUDO_KEEPALIVE=""
start_sudo_keepalive() {
  echo "The AUR step installs as $USERNAME with sudo. Password for $USERNAME, once:"
  as_user sudo -v || {
    warn "no sudo ticket: yay will ask for the password itself"
    return 0
  }
  (while kill -0 $$ 2> /dev/null; do
    as_user sudo -n -v 2> /dev/null
    sleep 60
  done) &
  SUDO_KEEPALIVE=$!
  trap stop_sudo_keepalive EXIT
}
stop_sudo_keepalive() {
  [[ -n $SUDO_KEEPALIVE ]] && kill "$SUDO_KEEPALIVE" 2> /dev/null
  SUDO_KEEPALIVE=""
  as_user sudo -k 2> /dev/null
  trap - EXIT
}

# ---------------------------------------------------------------- 1. user
say "1/12 User '$USERNAME'"
if ! id "$USERNAME" > /dev/null 2>&1; then
  useradd -m -G wheel -s /bin/bash "$USERNAME"
  echo "Set a password for $USERNAME:"
  passwd "$USERNAME"
fi
usermod -aG wheel "$USERNAME"
HOME_DIR="$(getent passwd "$USERNAME" | cut -d: -f6)"
UGRP="$(id -gn "$USERNAME")"
((DO_AUR)) && [[ -s $KIT/packages/aur.txt ]] && start_sudo_keepalive
# a root-owned home (older install-base.sh) would break everything written there below
[[ $(stat -c %U "$HOME_DIR") == "$USERNAME" ]] || {
  chown "$USERNAME:$UGRP" "$HOME_DIR"
  chmod 700 "$HOME_DIR"
}
# the same for a kit copied or cloned as root: git refuses a repo owned by someone else
if [[ $KIT == "$HOME_DIR"/* ]] && find "$KIT" ! -user "$USERNAME" -print -quit | grep -q .; then
  chown -R "$USERNAME:$UGRP" "$KIT"
  [[ $(dirname "$KIT") != "$HOME_DIR" ]] && chown "$USERNAME:$UGRP" "$(dirname "$KIT")"
fi

# ------------------------------------------------------------ 2. pacman
say "2/12 pacman.conf (multilib, parallel downloads)"
cp -n /etc/pacman.conf /etc/pacman.conf.bak-restore
sed -i -e 's/^#\?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
# [multilib] ships commented-out in the default pacman.conf; uncomment its two lines if not done yet
if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
  sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
fi
grep -q '^\[multilib\]' /etc/pacman.conf || {
  echo "multilib could not be enabled"
  exit 1
}

say "3/12 Mirrors (reflector) + full system upgrade"
pacman -Sy --needed --noconfirm archlinux-keyring reflector || fail "reflector"
install -Dm644 "$KIT/files/etc/xdg/reflector/reflector.conf" /etc/xdg/reflector/reflector.conf
cp -n /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak-restore
# shellcheck disable=SC2046
reflector $(grep -vE '^\s*(#|$)' /etc/xdg/reflector/reflector.conf | tr '\n' ' ') ||
  warn "reflector failed, keeping existing mirrorlist"
pacman -Syu --noconfirm || {
  echo "system upgrade failed"
  exit 1
}

# ------------------------------------------------------ 4. native packages
say "4/12 Native packages ($(grep -c . "$KIT/packages/pacman.txt"))"
# wine-staging replaces wine: drop plain wine first if present so no prompt blocks
pacman -Qq wine > /dev/null 2>&1 && pacman -Rdd --noconfirm wine
if ! pacman -S --needed --noconfirm - < "$KIT/packages/pacman.txt"; then
  warn "batch install failed, retrying package by package"
  while read -r p; do
    [[ -z $p ]] && continue
    pacman -S --needed --noconfirm "$p" || fail "pacman: $p"
  done < "$KIT/packages/pacman.txt"
fi

# ------------------------------------------------ 4b. hardware specific
say "4b/12 Hardware detection: microcode, GPU drivers, notebook extras"
hw_detect
echo "   $(hw_summary)"
mapfile -t HW_PKGS < <(hw_packages)
if ((${#HW_PKGS[@]})); then
  echo "   packages: ${HW_PKGS[*]}"
  pacman -S --needed --noconfirm "${HW_PKGS[@]}" || fail "hardware packages: ${HW_PKGS[*]}"
fi
[[ -n $HW_GPUS ]] || warn "no AMD/Intel/NVIDIA GPU detected (VM?): generic mesa only"
hw_has_gpu nvidia && warn "NVIDIA: nvidia-open needs Turing (GTX 16 / RTX 20) or newer; older cards need a legacy AUR driver. Untested path."
# firmware for other devices (wifi, bluetooth, gpu blobs) is in linux-firmware (package list); fwupd handles the rest.

# ------------------------------------------------ 4c. Microsoft Surface
if ((HW_SURFACE)); then
  say "4c/12 Surface: linux-surface kernel + iptsd (third-party repo pkg.surfacelinux.com)"
  SURFACE_KEY="$KIT/laptop/surface-signing-key.gpg"
  SURFACE_FPR=87DEFA4AB94A99A4C8C3112556C464BAAC421453
  # verify the key's fingerprint before trusting it, not just that a file with that name exists
  if [[ $(gpg --show-keys --with-colons "$SURFACE_KEY" 2> /dev/null | awk -F: '$1=="fpr"{print $10; exit}') != "$SURFACE_FPR" ]]; then
    fail "Surface signing key file missing or fingerprint mismatch, kernel not installed"
  else
    if ! grep -q '^\[linux-surface\]' /etc/pacman.conf; then
      if ! { pacman-key --add "$SURFACE_KEY" && pacman-key --lsign-key "$SURFACE_FPR" &&
        printf '\n[linux-surface]\nServer = https://pkg.surfacelinux.com/arch/\n' >> /etc/pacman.conf; }; then
        fail "linux-surface repo/key"
      fi
    fi
    pacman -Syu --noconfirm --needed linux-surface iptsd || fail "linux-surface / iptsd"
  fi
fi

# ----------------------------------------------------------- 5. system config
say "5/12 System configuration"
KIT_ETC="$KIT/files/etc"
# hostname: keep what install-base.sh set; only fall back to the kit's name on an unnamed system
CUR_HOST="$(cat /etc/hostname 2> /dev/null)"
if [[ -z $CUR_HOST || $CUR_HOST == archiso || $CUR_HOST == localhost ]]; then cp "$KIT_ETC/hostname" /etc/hostname; fi
# language, console keymap and timezone: keep what install-base.sh (or the installer) set; the
# kit's values only fill in what is missing
[[ -s /etc/locale.conf ]] || cp "$KIT_ETC/locale.conf" /etc/locale.conf
[[ -s /etc/vconsole.conf ]] || cp "$KIT_ETC/vconsole.conf" /etc/vconsole.conf
sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen && locale-gen
[[ -e /etc/localtime ]] || ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc 2> /dev/null || true
# static /etc files that just get copied in as-is
install -Dm644 "$KIT_ETC/sysctl.d/99-gaming.conf" /etc/sysctl.d/99-gaming.conf
install -Dm644 "$KIT_ETC/security/limits.d/10-games.conf" /etc/security/limits.d/10-games.conf
install -Dm644 "$KIT_ETC/NetworkManager/conf.d/hostname.conf" /etc/NetworkManager/conf.d/hostname.conf
install -Dm644 "$KIT_ETC/systemd/zram-generator.conf" /etc/systemd/zram-generator.conf
install -Dm440 /dev/stdin /etc/sudoers.d/10-wheel <<< '%wheel ALL=(ALL:ALL) ALL'
visudo -cf /etc/sudoers.d/10-wheel > /dev/null || {
  rm -f /etc/sudoers.d/10-wheel
  fail "sudoers.d/10-wheel invalid, removed"
}
sysctl --system > /dev/null 2>&1 || true

# initramfs: systemd-based hooks (skipped if the root fs is encrypted)
if grep -qE '^HOOKS=.*\b(encrypt|sd-encrypt)\b' /etc/mkinitcpio.conf; then
  warn "encrypted root detected, leaving mkinitcpio HOOKS untouched"
else
  cp -n /etc/mkinitcpio.conf /etc/mkinitcpio.conf.bak-restore
  sed -i 's/^HOOKS=.*/HOOKS=(base systemd plymouth autodetect microcode modconf kms keyboard sd-vconsole block filesystems fsck)/' /etc/mkinitcpio.conf
  # early KMS (GPU driver in the initramfs) so the Plymouth splash appears early at native resolution
  rm -f /etc/mkinitcpio.conf.d/10-amdgpu.conf
  mapfile -t KMS_MODS < <(hw_early_modules)
  if ((${#KMS_MODS[@]})); then
    install -Dm644 /dev/stdin /etc/mkinitcpio.conf.d/10-gpu.conf <<< "MODULES=(${KMS_MODS[*]})"
  else
    rm -f /etc/mkinitcpio.conf.d/10-gpu.conf
  fi
  # plymouth is in packages/pacman.txt; -R rebuilds all initramfs images
  plymouth-set-default-theme -R bgrt || fail "plymouth theme/mkinitcpio"
fi

# --------------------------------------------------------- 6. login (greetd)
say "6/12 Login: greetd + ReGreet (graphical, runs in cage) + gnome-keyring PAM"
pacman -S --needed --noconfirm greetd greetd-regreet cage || fail "greetd/regreet/cage"
cp -n /etc/greetd/config.toml /etc/greetd/config.toml.bak-default 2> /dev/null || true
install -Dm644 "$KIT_ETC/greetd/config.toml" /etc/greetd/config.toml
install -Dm644 "$KIT_ETC/greetd/regreet.toml" /etc/greetd/regreet.toml
# the greeting is this machine's hostname, not the one the kit was snapshotted on
sed -i "s/^greeting_msg = .*/greeting_msg = \"$(cat /etc/hostname)\"/" /etc/greetd/regreet.toml
install -Dm644 "$KIT_ETC/greetd/regreet.css" /etc/greetd/regreet.css
[[ -r $KIT_ETC/greetd/avatar.png ]] && install -Dm644 "$KIT_ETC/greetd/avatar.png" /etc/greetd/avatar.png
install -Dm644 "$KIT/files/usr/share/backgrounds/login.png" /usr/share/backgrounds/login.png
cp -n /etc/pam.d/greetd /etc/pam.d/greetd.bak-restore 2> /dev/null || true
install -Dm644 "$KIT_ETC/pam.d/greetd" /etc/pam.d/greetd
# lets the login keyring unlock automatically when it shares the login password (see summary at the end)
if ! grep -q pam_gnome_keyring /etc/pam.d/login; then
  cp -n /etc/pam.d/login /etc/pam.d/login.bak-restore
  printf 'auth       optional     pam_gnome_keyring.so\nsession    optional     pam_gnome_keyring.so auto_start\n' >> /etc/pam.d/login
fi

# ------------------------------------------------------------ 7. services
say "7/12 Services"
systemctl enable NetworkManager.service NetworkManager-wait-online.service \
  bluetooth.service greetd.service systemd-timesyncd.service \
  paccache.timer reflector.timer || fail "enable system services"
systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service \
  gnome-keyring-daemon.socket xdg-user-dirs.service 2> /dev/null || true
# graphical.target so greetd starts (minimal installs may still default to multi-user)
systemctl set-default graphical.target

# ------------------------------------------------------------- 8. snapper
say "8/12 snapper (btrfs snapshots)"
if [[ $(findmnt -no FSTYPE /) == btrfs ]]; then
  if [[ ! -f /etc/snapper/configs/root ]]; then
    # /.snapshots is usually a separate subvolume (@snapshots) that snapper would refuse to create
    SNAP_MNT=0
    if findmnt -n /.snapshots > /dev/null 2>&1; then
      SNAP_MNT=1
      umount /.snapshots
      rmdir /.snapshots 2> /dev/null
    fi
    if snapper -c root create-config /; then
      # snapper's create-config makes its own .snapshots subvolume; swap the real @snapshots one back in
      if ((SNAP_MNT)); then
        btrfs subvolume delete /.snapshots > /dev/null 2>&1
        if ! { mkdir -p /.snapshots && mount /.snapshots 2> /dev/null; }; then
          warn "mount /.snapshots failed, check fstab"
        fi
        chmod 750 /.snapshots
      fi
      snapper -c root set-config TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes \
        TIMELINE_LIMIT_HOURLY=5 TIMELINE_LIMIT_DAILY=7 TIMELINE_LIMIT_WEEKLY=2 \
        TIMELINE_LIMIT_MONTHLY=1 TIMELINE_LIMIT_YEARLY=0
    else
      ((SNAP_MNT)) && {
        mkdir -p /.snapshots
        mount /.snapshots
      }
      fail "snapper create-config"
    fi
  fi
  systemctl enable snapper-timeline.timer snapper-cleanup.timer
else
  warn "root is not btrfs, snapper skipped"
fi

# ------------------------------------------ 8b. base hardening
say "8b/12 /home snapshots, LTS fallback kernel, firewall, SMART, coredump limit"
# a) snapper config for /home (same retention as root)
if [[ $(findmnt -no FSTYPE /home 2> /dev/null) == btrfs && ! -f /etc/snapper/configs/home ]]; then
  if ! { snapper -c home create-config /home &&
    snapper -c home set-config TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes NUMBER_CLEANUP=yes \
      TIMELINE_LIMIT_HOURLY=5 TIMELINE_LIMIT_DAILY=7 TIMELINE_LIMIT_WEEKLY=2 \
      TIMELINE_LIMIT_MONTHLY=1 TIMELINE_LIMIT_YEARLY=0; }; then
    fail "snapper home config"
  fi
fi
# a2) quiet splash boot, no menu (hold Space at power-on for the picker)
if [[ -f /boot/loader/entries/arch.conf ]] && ! grep -q '\bsplash\b' /boot/loader/entries/arch.conf; then
  sed -i '/^options /s/$/ quiet splash loglevel=3 vt.global_cursor_default=0 rd.udev.log_level=3/' /boot/loader/entries/arch.conf
fi
[[ -f /boot/loader/loader.conf ]] && sed -i 's/^timeout.*/timeout 0/' /boot/loader/loader.conf
# microcode: the mkinitcpio hook (step 5) already loads it; an initrd line is only needed without
# the hook (encrypted root), and a line for the other vendor's image would stop the boot
if [[ -f /boot/loader/entries/arch.conf ]]; then
  sed -i -E '/^initrd .*\/(amd|intel)-ucode\.img$/d' /boot/loader/entries/arch.conf
  UCODE="$(hw_ucode_pkg)"
  if ! grep -qE '^HOOKS=.*\bmicrocode\b' /etc/mkinitcpio.conf && [[ -n $UCODE && -f /boot/$UCODE.img ]]; then
    sed -i "0,/^initrd /s##initrd /$UCODE.img\ninitrd #" /boot/loader/entries/arch.conf
  fi
  if hw_has_gpu nvidia && ! grep -q 'nvidia-drm.modeset' /boot/loader/entries/arch.conf; then
    sed -i '/^options /s/$/ nvidia-drm.modeset=1/' /boot/loader/entries/arch.conf
  fi
fi
# b) systemd-boot entry for linux-lts, derived from the normal entry (root UUID/subvol/ucode stay identical)
if [[ -f /boot/vmlinuz-linux-lts && -f /boot/loader/entries/arch.conf && ! -f /boot/loader/entries/arch-lts.conf ]]; then
  sed -e 's/^title .*/title Arch Linux (LTS, Fallback)/' \
    -e 's#/vmlinuz-linux$#/vmlinuz-linux-lts#' \
    -e 's#/initramfs-linux\.img#/initramfs-linux-lts.img#' \
    /boot/loader/entries/arch.conf > /boot/loader/entries/arch-lts.conf || fail "arch-lts.conf"
fi
# b2) Surface: boot entry for the linux-surface kernel (derived from arch.conf, so it carries splash/ucode), made default
if [[ -f /boot/vmlinuz-linux-surface && -f /boot/loader/entries/arch.conf && ! -f /boot/loader/entries/arch-surface.conf ]]; then
  sed -e 's/^title .*/title Arch Linux (Surface)/' \
    -e 's#/vmlinuz-linux$#/vmlinuz-linux-surface#' \
    -e 's#/initramfs-linux\.img#/initramfs-linux-surface.img#' \
    /boot/loader/entries/arch.conf > /boot/loader/entries/arch-surface.conf || fail "arch-surface.conf"
  sed -i 's/^default.*/default arch-surface.conf/' /boot/loader/loader.conf
fi
# c) coredump limit, smartd (config + mako notify hook), firewall
install -Dm644 "$KIT_ETC/systemd/coredump.conf.d/10-limit.conf" /etc/systemd/coredump.conf.d/10-limit.conf
if [[ -r $KIT_ETC/smartd.conf ]]; then
  install -Dm644 "$KIT_ETC/smartd.conf" /etc/smartd.conf
  install -Dm755 "$KIT/files/usr/local/bin/smartd-notify" /usr/local/bin/smartd-notify
  # the hook notifies the desktop user: point it at this user and uid
  sed -i "s/runuser -u [a-z_][a-z0-9_-]*/runuser -u $USERNAME/; s#/run/user/[0-9]*/bus#/run/user/$(id -u "$USERNAME")/bus#" /usr/local/bin/smartd-notify
  systemctl enable smartd.service fwupd-refresh.timer 2> /dev/null || warn "smartd/fwupd enable"
fi
# only a firewall that is not on yet gets the defaults; an active one keeps its rules
if command -v ufw > /dev/null && ! grep -q '^ENABLED=yes' /etc/ufw/ufw.conf; then
  ufw default deny incoming > /dev/null 2>&1
  ufw default allow outgoing > /dev/null 2>&1
  ufw --force enable > /dev/null 2>&1 || sed -i 's/^ENABLED=.*/ENABLED=yes/' /etc/ufw/ufw.conf
fi
command -v ufw > /dev/null && { systemctl enable ufw.service || fail "ufw enable"; }

# ----------------------------------------------------- 9. dotfiles (as user)
say "9/12 Dotfiles -> $HOME_DIR"
STAMP="$(date +%s)"
# copy every file from files/home into the user's home, backing up anything that already differs
(cd "$KIT/files/home" && find . -type f) | while read -r f; do
  dst="$HOME_DIR/${f#./}"
  mkdir -p "$(dirname "$dst")"
  if [[ -e $dst ]] && ! cmp -s "$KIT/files/home/$f" "$dst"; then mv "$dst" "$dst.bak-restore-$STAMP"; fi
  cp -a "$KIT/files/home/$f" "$dst"
done
mkdir -p "$HOME_DIR/.local/bin" # for the set-wallpaper link; the kit ships no file there
chown -R "$USERNAME:$UGRP" "$HOME_DIR/.config" "$HOME_DIR/.local" "$HOME_DIR/.bashrc" "$HOME_DIR/.bash_profile"
chmod 700 "$HOME_DIR/.config/gtk-3.0" "$HOME_DIR/.config/gtk-4.0" 2> /dev/null || true
chmod +x "$HOME_DIR/.config/wlogout/wlogout.sh" 2> /dev/null || true
chmod +x "$HOME_DIR"/.config/theme/*.sh "$HOME_DIR"/.config/theme/*.py 2> /dev/null || true
ln -sfn "$HOME_DIR/.config/theme/set-wallpaper.sh" "$HOME_DIR/.local/bin/set-wallpaper" 2> /dev/null || true
# the theme files in the kit are one machine's (lib/lists.sh, MACHINE_LOCAL): render them anew from
# the current templates for the kit's wallpaper; this machine keeps its own from here on
as_user python3 "$HOME_DIR/.config/theme/apply.py" --current > /dev/null || warn "theme not rendered (later: set-wallpaper --current)"
# a few dotfiles need absolute paths (GTK/Waybar CSS imports, qt6ct): point them at this home,
# whatever user the kit was snapshotted as
grep -rlZ --include='*.css' --include='*.conf' -E '/home/[^/"]+/\.config' "$HOME_DIR/.config" 2> /dev/null |
  xargs -0r sed -i -E "s#/home/[^/\"]+/\.config#$HOME_DIR/.config#g"
# project notes (KIT_NOTES_REL in kit.conf): only put back when missing, never overwrite a newer one
if [[ -n ${KIT_NOTES_REL:-} ]]; then
  NOTES="$HOME_DIR/$KIT_NOTES_REL"
  if [[ -s $KIT/files/CLAUDE.md && ! -e $NOTES/CLAUDE.md ]]; then
    install -D -o "$USERNAME" -g "$UGRP" -m644 "$KIT/files/CLAUDE.md" "$NOTES/CLAUDE.md"
  fi
  if [[ -d $KIT/files/docs && ! -e $NOTES/docs ]]; then
    mkdir -p "$NOTES" && cp -a "$KIT/files/docs" "$NOTES/docs" && chown -R "$USERNAME:$UGRP" "$NOTES"
  fi
fi

# --- machine specific Hyprland / Waybar adjustments
HYPR_CONF="$HOME_DIR/.config/hypr/hyprland.lua"
if [[ -f $HYPR_CONF ]]; then
  # NVIDIA-only (no AMD/Intel iGPU alongside it): force the NVIDIA GL/VA-API vendor libs
  if hw_has_gpu nvidia && ! hw_has_gpu intel && ! hw_has_gpu amd && ! grep -q GLX_VENDOR "$HYPR_CONF"; then
    sed -i '0,/^hl.env(/s##hl.env("LIBVA_DRIVER_NAME", "nvidia")\nhl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")\nhl.env(#' "$HYPR_CONF"
  fi
fi
WAYBAR_DIR="$HOME_DIR/.config/waybar"
# drop the desktop's fixed network interface name / add a WiFi format on machines that have WiFi
if [[ -f $WAYBAR_DIR/config.jsonc ]]; then
  python3 "$KIT/lib/waybar-network.py" "$WAYBAR_DIR/config.jsonc" || warn "waybar network module not adjusted"
fi
if ((HW_LAPTOP)) && [[ -d $KIT/laptop ]]; then
  # add the battery module + its CSS only on laptops, and only if not already present (idempotent)
  if [[ -f $WAYBAR_DIR/config.jsonc ]] && ! grep -q '"battery"' "$WAYBAR_DIR/config.jsonc"; then
    python3 - "$WAYBAR_DIR/config.jsonc" "$KIT/laptop/waybar-battery.jsonc" << 'PY' || fail "waybar battery module"
import sys
cfg, snip = sys.argv[1], open(sys.argv[2]).read()
s = open(cfg).read()
s = s.replace('        "network",\n', '        "battery",\n        "network",\n', 1)
s = s.replace('    "network": {', snip.rstrip() + '\n\n    "network": {', 1)
open(cfg, 'w').write(s)
PY
    cat "$KIT/laptop/waybar-battery.css" >> "$WAYBAR_DIR/style.css"
    chown "$USERNAME:$UGRP" "$WAYBAR_DIR/config.jsonc" "$WAYBAR_DIR/style.css"
  fi
  systemctl enable power-profiles-daemon.service 2> /dev/null || warn "power-profiles-daemon enable"
fi
# the hourly sync: enabled by hand as "systemctl --user enable" would (no user session here). The
# unit runs the kit from ~/rebuild, and it has to be a git clone, not an unpacked zip.
TIMER_WANTS="$HOME_DIR/.config/systemd/user/timers.target.wants"
if [[ $KIT == "$HOME_DIR/rebuild" && -d $KIT/.git ]]; then
  sudo -u "$USERNAME" mkdir -p "$TIMER_WANTS"
  sudo -u "$USERNAME" ln -sfn "$HOME_DIR/.config/systemd/user/rebuild-snapshot.timer" "$TIMER_WANTS/rebuild-snapshot.timer"
  # signed commits (lib/signing.sh): this machine's key, and trust for the machines in signers/ of
  # this fresh clone. The first sync pushes the key; the other machines then ask whether to trust it.
  sudo -u "$USERNAME" -H bash "$KIT/lib/signing.sh" setup --no-sync || warn "commit signing not set up (lib/signing.sh setup)"
else
  warn "kit sync not enabled: it needs a git clone at $HOME_DIR/rebuild (this kit: $KIT)"
fi
# XDG folders by path: plain "sudo -u" keeps root's $HOME, so they must not rely on $HOME
sudo -u "$USERNAME" mkdir -p "$HOME_DIR"/{Desktop,Downloads,Documents,Music,Pictures,Videos,Templates,Public,Projects,Games}
sudo -u "$USERNAME" -H xdg-user-dirs-update 2> /dev/null || true
# dconf (GTK dark theme, cursor, font); needs a session bus
if [[ -s $KIT/files/dconf.ini ]]; then
  # shellcheck disable=SC2024 # root reads the kit file, the user only gets it on stdin
  sudo -u "$USERNAME" dbus-run-session -- dconf load / < "$KIT/files/dconf.ini" ||
    warn "dconf load failed (set GTK theme manually)"
fi
# the sync installs listed packages via "pkexec rebuild-install", with a password dialog every
# time. Also removes the passwordless rules of older kit versions (sync, and the AUR step of an
# interrupted restore.sh run).
rm -f /etc/sudoers.d/10-rebuild-sync /etc/sudoers.d/90-rebuild-sync /etc/sudoers.d/99-restore-nopasswd
install -Dm755 "$KIT/files/usr/local/bin/rebuild-install" /usr/local/bin/rebuild-install
install -Dm644 "$KIT/files/usr/share/polkit-1/actions/org.rebuild.install.policy" \
  /usr/share/polkit-1/actions/org.rebuild.install.policy

# ---------------------------------------------------------------- 10. AUR
if ((DO_AUR)); then
  say "10/12 AUR: yay + $(grep -c . "$KIT/packages/aur.txt") packages"
  if ((REVIEW_AUR)); then
    echo "   --review-aur: yay shows every PKGBUILD and asks before it builds"
  else
    warn "AUR packages are built without showing their PKGBUILDs. To read them first: --review-aur"
  fi

  if ! command -v yay > /dev/null; then
    # building yay needs Go and a fair amount of RAM; yay-bin is the fallback
    for pkg in yay yay-bin; do
      # shellcheck disable=SC2016 # expanded by the inner bash
      as_user bash -c '
        set -e; d=$(mktemp -d); cd "$d"
        git clone --depth=1 "https://aur.archlinux.org/$1.git" && cd "$1"
        if (( $2 )); then
          ${PAGER:-less} PKGBUILD
          read -rp "Build and install $1? [y/N] " a; [[ $a == [yY]* ]] || exit 1
        fi
        # makepkg calls "sudo -k pacman", which ignores the ticket and asks again: plain sudo instead
        conf=$(mktemp)
        printf "source /etc/makepkg.conf\nPACMAN_AUTH=(sudo)\n" > "$conf"
        makepkg --config "$conf" -si --noconfirm --needed' _ "$pkg" "$REVIEW_AUR" && break
      warn "AUR bootstrap with $pkg failed"
    done
    command -v yay > /dev/null || fail "yay bootstrap"
  fi

  # proton-ge-custom-bin ships the same limits.d/10-games.conf that step 5 installed; let it take over
  if command -v yay > /dev/null; then
    if ((REVIEW_AUR)); then
      YAY=(as_user yay -S --needed --removemake --answerclean None --answerdiff All --answeredit None)
    else
      YAY=(as_user yay -S --needed --noconfirm --removemake --answerclean None --answerdiff None --answeredit None)
    fi
    YAY+=(--overwrite '/etc/security/limits.d/10-games.conf')
    mapfile -t AUR_PKGS < <(grep . "$KIT/packages/aur.txt")
    if ! "${YAY[@]}" "${AUR_PKGS[@]}"; then
      warn "AUR batch failed, retrying package by package"
      while read -r p; do
        [[ -z $p ]] && continue
        "${YAY[@]}" "$p" || fail "aur: $p"
      done < "$KIT/packages/aur.txt"
    fi
  fi
  stop_sudo_keepalive
else
  say "10/12 AUR skipped (--no-aur)"
fi

# ---------------------------------------------------------- 11. VS Code
say "11/12 VS Code extensions"
if command -v code > /dev/null && [[ -s $KIT/packages/vscode-extensions.txt ]]; then
  while read -r x; do
    [[ -z $x ]] && continue
    sudo -u "$USERNAME" code --install-extension "$x" > /dev/null 2>&1 || warn "VS Code extension failed: $x (install later)"
  done < "$KIT/packages/vscode-extensions.txt"
fi

# --------------------------------------------------------------- 12. done
if ((DO_SNAP)) && [[ -f /etc/snapper/configs/root ]]; then
  say "12/12 snapper snapshot 'post-restore'"
  snapper -c root create -d "post-restore" || true
fi

chown -R "$USERNAME:$UGRP" "$HOME_DIR/.cache" "$HOME_DIR/.config" "$HOME_DIR/.local" 2> /dev/null || true

say "Verification (verify.sh, as $USERNAME)"
sudo -u "$USERNAME" bash "$KIT/verify.sh" || warn "verify.sh reported FAIL lines, see above"

say "Summary"
if ((${#FAILED[@]})); then
  warn "These steps had problems:"
  printf '   - %s\n' "${FAILED[@]}"
else
  echo "Everything went through."
fi
cat << EOF

Manual steps left (see README.md):
  * reboot  ->  ReGreet login  ->  Hyprland (uwsm)
  * Keyring auto-unlock only works if keyring and login password are identical
  * Calendar: run  bash $KIT/calendar-login.sh  (Nextcloud app password, sync, timer)
  * Steam login, Lutris/Battle.net + Diablo 4 (re-install via Lutris), Discord, Brave sync, Nextcloud login
  * Restore private data (SSH keys, Thunderbird/Brave profiles) from your own backup
  * Check Hyprland window classes: hyprctl clients
  * Different hardware than the desktop PC: look at ~/.config/hypr/hyprland.lua (monitor block) and run  set-wallpaper --current  once inside Hyprland (login image size)
EOF
