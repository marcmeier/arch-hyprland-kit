# shellcheck shell=bash
# Boot with unified kernel images (UKI): mkinitcpio builds kernel, initramfs, microcode and the
# command line into one EFI file per kernel in /boot/EFI/Linux, and systemd-boot lists every file
# there by itself. No boot entries to write or derive, every kernel (linux, linux-lts, linux-surface)
# gets its own entry, and one signed file per kernel is what Secure Boot (sbctl) needs later.
# Used by install/install-base.sh (in the chroot) and install/bootstrap.sh. Runs as root.

ESP=${ESP:-/boot}

# uki_cmdline ROOT_UUID [LUKS_UUID]: /etc/kernel/cmdline, the command line baked into every image
uki_cmdline() {
  local root=$1 luks=${2:-}
  {
    if [[ -n $luks ]]; then
      printf 'rd.luks.name=%s=cryptroot root=/dev/mapper/cryptroot ' "$luks"
    else
      printf 'root=UUID=%s ' "$root"
    fi
    echo "rootflags=subvol=@ rw quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0"
  } > /etc/kernel/cmdline
}

# uki_presets: every kernel's mkinitcpio preset builds a UKI instead of a separate initramfs. New
# kernels get a fresh preset from the kernel package, so run this again after installing one.
uki_presets() {
  local preset kernel
  mkdir -p "$ESP/EFI/Linux"
  for preset in /etc/mkinitcpio.d/*.preset; do
    [[ -f $preset ]] || continue
    kernel=$(basename "$preset" .preset)
    sed -i -E \
      -e "s|^#?default_uki=.*|default_uki=\"$ESP/EFI/Linux/arch-$kernel.efi\"|" \
      -e 's|^default_image=|#default_image=|' \
      -e "s|^PRESETS=.*|PRESETS=('default')|" "$preset"
    # the separate initramfs images are not needed any more
    rm -f "$ESP/initramfs-$kernel.img" "$ESP/initramfs-$kernel-fallback.img"
  done
}

# uki_loader DEFAULT: loader.conf of systemd-boot. No menu (hold Space at power-on for it).
uki_loader() {
  printf 'default %s\ntimeout 0\nconsole-mode max\neditor no\n' "${1:-arch-linux.efi}" > "$ESP/loader/loader.conf"
}

uki_active() { [[ -s /etc/kernel/cmdline ]] && compgen -G "$ESP/EFI/Linux/*.efi" > /dev/null; }
