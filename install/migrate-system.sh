#!/usr/bin/env bash
# =============================================================================
# migrate-system.sh - the root part of moving from the old rebuild kit to driftless. Run it after
# install/migrate-from-rebuild.sh:  sudo bash install/migrate-system.sh
#
#   1. builds (as you) and installs driftless-system: the drop-ins, the greeter config, the helpers
#   2. renders the login screen from your theme into /var/lib/driftless/greeter
#   3. enables the manifest's system units that the old kit did not have (fstrim.timer ...)
#   4. moves the old kit's own files out of /etc and /usr/local (to /root/rebuild-kit-leftovers)
#      where driftless-system now has a drop-in; files of other packages are left alone
# The boot stays as it is (classic entries); docs/boot.md describes the switch to UKIs.
# =============================================================================
set -euo pipefail
DRIFTLESS=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
USERNAME=${SUDO_USER:?run with sudo from your account}
HOME_DIR=$(getent passwd "$USERNAME" | cut -d: -f6)
[[ $EUID -eq 0 ]] || { echo "run with sudo" && exit 1; }

echo "==> 1. driftless-system"
pkg=$(runuser -u "$USERNAME" -- env HOME="$HOME_DIR" "$DRIFTLESS/driftless" system --build-only | tail -1)
[[ -f $pkg ]] || { echo "build failed" && exit 1; }
# the old kit wrote 10-gpu.conf by hand; keep it (same name and content as driftless writes)
pacman -U --needed --noconfirm "$pkg"

echo "==> 2. login screen"
/usr/lib/driftless/greeter-update "$HOME_DIR/.cache/theme"
ls -l /var/lib/driftless/greeter
for f in regreet.toml regreet.css login.png avatar.png; do
  [[ -s /var/lib/driftless/greeter/$f ]] || { echo "!! $f missing: do not reboot before set-wallpaper --current" && exit 1; }
done

# the login screen offers the uwsm session from now on (ReGreet remembers the last choice per user)
session=$(sed -n 's/^Name=//p' /usr/share/wayland-sessions/hyprland-uwsm.desktop | head -1)
state=/var/lib/regreet/state.toml
if [[ -n $session && -f $state ]]; then
  cp -n "$state" "$state.bak-driftless"
  if grep -q "^$USERNAME = " "$state"; then
    sed -i "s/^$USERNAME = .*/$USERNAME = \"$session\"/" "$state"
  elif grep -q '^\[user_to_last_sess\]' "$state"; then
    sed -i "/^\[user_to_last_sess\]/a $USERNAME = \"$session\"" "$state"
  else
    printf '\n[user_to_last_sess]\n%s = "%s"\n' "$USERNAME" "$session" >> "$state"
  fi
  echo "   login screen: $USERNAME starts \"$session\" next time"
fi

echo "==> 3. system units of the manifest (new ones like fstrim.timer)"
while read -r unit; do
  systemctl enable -q "$unit" && echo "   enabled: $unit"
done < <(runuser -u "$USERNAME" -- env HOME="$HOME_DIR" "$DRIFTLESS/driftless" manifest unit)

echo "==> 4. old kit files out of the way"
OUT=/root/rebuild-kit-leftovers/$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"
for f in /usr/local/bin/rebuild-install /usr/share/polkit-1/actions/org.rebuild.install.policy \
  /usr/local/bin/smartd-notify /etc/sysctl.d/99-gaming.conf /etc/systemd/zram-generator.conf \
  /etc/systemd/coredump.conf.d/10-limit.conf /etc/NetworkManager/conf.d/hostname.conf \
  /etc/greetd/regreet.toml /etc/greetd/regreet.css /etc/greetd/avatar.png /usr/share/backgrounds/login.png \
  /etc/sudoers.d/10-rebuild-sync /etc/sudoers.d/90-rebuild-sync /etc/sudoers.d/99-restore-nopasswd; do
  [[ -e $f ]] || continue
  if pacman -Qo "$f" > /dev/null 2>&1; then
    echo "   kept (belongs to $(pacman -Qqo "$f")): $f"
    continue
  fi
  mkdir -p "$OUT$(dirname "$f")"
  mv "$f" "$OUT$f"
  echo "   moved: $f"
done
# smartd read /etc/smartd.conf with the old hook; the drop-in points it at driftless's config now
systemctl daemon-reload
systemctl try-restart smartd.service systemd-sysctl.service 2> /dev/null || true
echo
echo "Done. Old files: $OUT"
echo "Check before the next reboot:  systemctl cat greetd | grep ExecStart   and   $DRIFTLESS/driftless verify"
