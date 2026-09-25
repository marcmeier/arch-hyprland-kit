#!/usr/bin/env bash
# switch-to-uki.sh - moves a machine with classic systemd-boot entries to unified kernel images.
# Keeps the old entries as a fallback in the boot menu (hold Space at power-on). docs/boot.md
#   sudo bash install/switch-to-uki.sh
set -euo pipefail
DRIFTLESS=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
# shellcheck source=lib/boot.sh
source "$DRIFTLESS/lib/boot.sh"
[[ $EUID -eq 0 ]] || { echo "run with sudo" && exit 1; }
entry=/boot/loader/entries/arch.conf
[[ -f $entry ]] || { echo "no $entry: nothing to take the command line from" && exit 1; }
uki_active && { echo "already on unified kernel images" && exit 0; }

options=$(sed -n 's/^options[[:space:]]\+//p' "$entry")
[[ $options == *root=* ]] || { echo "no root= in $entry" && exit 1; }
[[ $options == *splash* ]] || options+=" quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0"
cp -n /etc/kernel/cmdline /etc/kernel/cmdline.bak-driftless 2> /dev/null || true
echo "$options" > /etc/kernel/cmdline
echo "command line: $options"

for preset in /etc/mkinitcpio.d/*.preset; do cp -n "$preset" "$preset.bak-driftless"; done
# keep the old initramfs files for the old entries: uki_presets would delete them
ESP_KEEP=$(mktemp -d)
cp -a /boot/initramfs-*.img "$ESP_KEEP/" 2> /dev/null || true
uki_presets
cp -a "$ESP_KEEP"/. /boot/ && rm -rf "$ESP_KEEP"
mkinitcpio -P

missing=0
for preset in /etc/mkinitcpio.d/*.preset; do
  kernel=$(basename "$preset" .preset)
  if [[ -f /boot/EFI/Linux/arch-$kernel.efi ]]; then echo "ok: arch-$kernel.efi"; else
    echo "!! missing: arch-$kernel.efi"
    missing=1
  fi
done
((missing)) && { echo "not switching the default entry; old entries unchanged" && exit 1; }
default=arch-linux.efi
[[ -f /boot/EFI/Linux/arch-linux-surface.efi ]] && default=arch-linux-surface.efi
sed -i 's/^timeout .*/timeout 3/' /boot/loader/loader.conf # see both for the first boots
grep -q '^default ' /boot/loader/loader.conf && sed -i "s/^default .*/default $default/" /boot/loader/loader.conf ||
  echo "default $default" >> /boot/loader/loader.conf
grep -q '^editor ' /boot/loader/loader.conf || echo "editor no" >> /boot/loader/loader.conf
echo "Done. Reboot; the old entries stay in the menu (3 s) until you delete them (docs/boot.md)."
