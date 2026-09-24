#!/usr/bin/env bash
# =============================================================================
# install-base.sh - OPTIONAL. Run from the Arch live ISO to create the minimal
# base system this kit expects (GPT, 1G ESP, btrfs with @ @home @log @pkg
# @snapshots, systemd-boot, NetworkManager, user + sudo). Afterwards reboot and
# run restore.sh. DESTROYS ALL DATA on the chosen disk.
#
#   bash install-base.sh [/dev/DISK] [username] [--hostname NAME] [--keymap MAP] [--tz ZONE]
#
# Without a disk the script lists the disks and asks. CPU microcode (amd-ucode /
# intel-ucode) is picked from the detected CPU. Defaults: user user, hostname
# archlinux, keymap us, timezone UTC.
# =============================================================================
set -euo pipefail
KIT="$(dirname "$(readlink -f "$0")")"

# work from a copy: the kit may live under /mnt (e.g. a USB stick), which "umount -R /mnt" below
# would pull away mid-run
SAFE_KIT=/root/.rebuild-kit-safe-copy
rm -rf "$SAFE_KIT"
cp -a "$KIT" "$SAFE_KIT"
KIT="$SAFE_KIT"
# shellcheck source=lib/hardware.sh
source "$KIT/lib/hardware.sh"

# ---------------------------------------------------------------- arguments
DISK=""
USERNAME="user"
HOSTNAME_NEW="archlinux"
KEYMAP="us"
TZONE="UTC"
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --hostname)
      HOSTNAME_NEW="$2"
      shift 2
      ;;
    --keymap)
      KEYMAP="$2"
      shift 2
      ;;
    --tz)
      TZONE="$2"
      shift 2
      ;;
    -h | --help)
      sed -n '2,13p' "$0"
      exit 0
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done
# positional: an optional /dev/... disk, then the username
[[ ${POSITIONAL[0]:-} == /dev/* ]] && {
  DISK="${POSITIONAL[0]}"
  POSITIONAL=("${POSITIONAL[@]:1}")
}
[[ -n ${POSITIONAL[0]:-} ]] && USERNAME="${POSITIONAL[0]}"

# ---------------------------------------------------------------- preflight checks
[[ $EUID -eq 0 ]] || {
  echo "run as root"
  exit 1
}
if [[ -z $DISK ]]; then
  echo "Disks:"
  lsblk -d -e7,11 -o NAME,SIZE,TYPE,TRAN,MODEL
  read -rp "Install onto which disk (e.g. nvme0n1 or sda)? " d
  DISK="/dev/${d#/dev/}"
fi
# resolve /dev/disk/by-id/... and similar to the device node; the partition names below need it
[[ -e $DISK ]] && DISK="$(readlink -f "$DISK")"
[[ -b $DISK ]] || {
  echo "block device not found: '$DISK'"
  exit 1
}
[[ -d /sys/firmware/efi ]] || {
  echo "not booted in UEFI mode"
  exit 1
}
# DHCP/DNS may still be coming up right after boot
for _ in 1 2 3 4 5; do
  ping -c1 -W5 archlinux.org > /dev/null 2>&1 && break
  sleep 2
done
ping -c1 -W5 archlinux.org > /dev/null 2>&1 || {
  echo "no network (connect first: LAN cable, or iwctl for WLAN; test: ping archlinux.org)"
  exit 1
}

# ---------------------------------------------------------------- confirm and collect the password
lsblk "$DISK"
echo
echo "ALL DATA ON $DISK WILL BE ERASED."
read -rp "Type the device path again to confirm: " c
[[ $c == "$DISK" ]] || {
  echo aborted
  exit 1
}
read -rsp "Password for $USERNAME (also root): " PW
echo
[[ -n $PW ]] || {
  echo "empty password"
  exit 1
}

# ---------------------------------------------------------------- hardware detection
hw_detect
echo "Hardware: $(hw_summary)"
UCODE="$(hw_ucode_pkg)"
mapfile -t FWPKGS < <(hw_firmware_packages) # e.g. WiFi firmware, needed on the first boot

# ---------------------------------------------------------------- partition layout and mount options
# nvme0n1p1, mmcblk0p1, but sda1
PART_SEP=""
if [[ $DISK == *nvme* || $DISK == *mmcblk* ]]; then PART_SEP="p"; fi
ESP="${DISK}${PART_SEP}1"
ROOT="${DISK}${PART_SEP}2"
SSD_OPTS=""
if [[ $(cat "/sys/block/${DISK#/dev/}/queue/rotational" 2> /dev/null) == 0 ]]; then SSD_OPTS=",ssd,discard=async"; fi
MOUNT_OPTS="rw,noatime,compress=zstd:1${SSD_OPTS},space_cache=v2"

# ---------------------------------------------------------------- partition, format, mount
timedatectl set-ntp true
umount -R /mnt 2> /dev/null || true
sgdisk --zap-all "$DISK"
sgdisk -n1:0:+1G -t1:ef00 -c1:ESP -n2:0:0 -t2:8300 -c2:archroot "$DISK"
partprobe "$DISK"
sleep 1
mkfs.fat -F32 -n ESP "$ESP"
mkfs.btrfs -f -L arch "$ROOT"

# separate subvolumes so snapshots of @ leave out /home, logs and the package cache
mount "$ROOT" /mnt
for s in @ @home @log @pkg @snapshots; do btrfs subvolume create "/mnt/$s"; done
umount /mnt
mount -o "$MOUNT_OPTS,subvol=@" "$ROOT" /mnt
mkdir -p /mnt/{boot,home,var/log,var/cache/pacman/pkg,.snapshots}
mount -o "$MOUNT_OPTS,subvol=@home" "$ROOT" /mnt/home
mount -o "$MOUNT_OPTS,subvol=@log" "$ROOT" /mnt/var/log
mount -o "$MOUNT_OPTS,subvol=@pkg" "$ROOT" /mnt/var/cache/pacman/pkg
mount -o "$MOUNT_OPTS,subvol=@snapshots" "$ROOT" /mnt/.snapshots
mount "$ESP" /mnt/boot

# ---------------------------------------------------------------- base system (pacstrap)
sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
pacstrap -K /mnt base linux linux-firmware ${UCODE:+"$UCODE"} "${FWPKGS[@]}" btrfs-progs networkmanager \
  sudo git nano base-devel man-db
genfstab -U /mnt >> /mnt/etc/fstab

mkdir -p "/mnt/home/$USERNAME"
cp -a "$KIT" "/mnt/home/$USERNAME/rebuild"

ROOT_UUID="$(blkid -s UUID -o value "$ROOT")"
# no -e in the chroot: a failing bootctl must not skip the boot entry and services after it
arch-chroot /mnt /bin/bash << CHROOT
set -uo pipefail
ln -sf /usr/share/zoneinfo/$TZONE /etc/localtime
sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen; locale-gen
echo LANG=en_US.UTF-8 > /etc/locale.conf
echo KEYMAP=$KEYMAP > /etc/vconsole.conf
echo $HOSTNAME_NEW > /etc/hostname
useradd -m -G wheel -s /bin/bash "$USERNAME"
# the home and the kit in it were created as root above; git refuses a repo owned by someone else
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME"; chmod 700 "/home/$USERNAME"
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel; chmod 440 /etc/sudoers.d/10-wheel
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P
# inside a chroot bootctl writes the ESP files but no NVRAM entry; efibootmgr adds that below
bootctl install || echo "==> !! bootctl install reported a problem (see above). The ESP files may be incomplete."
printf 'default arch.conf\ntimeout 2\nconsole-mode max\n' > /boot/loader/loader.conf
# no microcode initrd line: the microcode hook puts it into the initramfs
cat > /boot/loader/entries/arch.conf <<ENTRY
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
options root=UUID=$ROOT_UUID rootflags=subvol=@ rw
ENTRY
systemctl enable NetworkManager systemd-timesyncd
CHROOT

# not in the unquoted heredoc above, where $, ` or \ in a password would be expanded
printf '%s:%s\n' "$USERNAME" "$PW" root "$PW" | arch-chroot /mnt chpasswd ||
  echo "==> !! setting the passwords failed. Before rebooting: arch-chroot /mnt passwd $USERNAME (and passwd for root)"

# NVRAM boot entry, from outside the chroot. Without it the disk still boots via the ESP fallback
# EFI/BOOT/BOOTX64.EFI, but may have to be picked in the firmware's boot menu.
if command -v efibootmgr > /dev/null; then
  # drop entries from earlier runs first
  while read -r bn; do efibootmgr -b "$bn" -B > /dev/null 2>&1; done \
    < <(efibootmgr | awk -F'[ *]' '/Linux Boot Manager/{sub(/^Boot/,"",$1); print $1}')
  if efibootmgr -c -d "$DISK" -p 1 -L "Linux Boot Manager" -l '\EFI\systemd\systemd-bootx64.efi'; then
    echo "==> NVRAM boot entry registered."
    echo "    Also move it above any network/PXE/HTTPS boot entries in the firmware's boot order" \
      "(BIOS setup, not the one-time F12 menu) so it starts by default without F12 every time."
  else
    echo "==> !! efibootmgr could not register a boot entry. EFI/BOOT/BOOTX64.EFI is still on the ESP as a fallback;" \
      "pick the disk from the firmware's one-time boot menu (F12/F2), or add a boot option by hand pointing at it."
  fi
else
  echo "==> efibootmgr not on this live medium; EFI/BOOT/BOOTX64.EFI is on the ESP as a fallback." \
    "Pick the disk from the firmware's one-time boot menu (F12/F2) if it is not listed automatically."
fi

echo
echo "Base installed (check the bootctl/efibootmgr lines above for errors!). Now: umount -R /mnt && reboot"
echo "Log in as $USERNAME, connect to network (nmtui), then:"
echo "  sudo bash ~/rebuild/restore.sh"
