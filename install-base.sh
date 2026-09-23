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

# Safety copy: this script later does "umount -R /mnt" and mounts the fresh target filesystem
# there. If the kit itself is running from under /mnt (e.g. a USB stick mounted at /mnt/kit, seen
# on a Dell Latitude), that unmounts the kit out from under itself mid-script ("cp: cannot stat '/mnt/kit/rebuild'"). Take our own copy on the
# live medium's own tmpfs first, regardless of where we were started from, so this can't happen.
SAFE_KIT=/root/.rebuild-kit-safe-copy
rm -rf "$SAFE_KIT"; cp -a "$KIT" "$SAFE_KIT"; KIT="$SAFE_KIT"
# shellcheck source=lib/hardware.sh
source "$KIT/lib/hardware.sh"

# ---------------------------------------------------------------- argument parsing
# Defaults, overridable by the flags/positional args handled below.
DISK=""; USERNAME="user"; HOSTNAME_NEW="archlinux"; KEYMAP="us"; TZONE="UTC"
POS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --hostname) HOSTNAME_NEW="$2"; shift 2;;
    --keymap)   KEYMAP="$2"; shift 2;;
    --tz)       TZONE="$2"; shift 2;;
    -h|--help)  sed -n '2,15p' "$0"; exit 0;;
    *)          POS+=("$1"); shift;;
  esac
done
# remaining positional args: first one starting with /dev/ is the disk, the next is the username
[[ ${POS[0]:-} == /dev/* ]] && { DISK="${POS[0]}"; POS=("${POS[@]:1}"); }
[[ -n ${POS[0]:-} ]] && USERNAME="${POS[0]}"

# ---------------------------------------------------------------- preflight checks
[[ $EUID -eq 0 ]] || { echo "run as root"; exit 1; }
if [[ -z $DISK ]]; then
  echo "Disks:"; lsblk -d -e7,11 -o NAME,SIZE,TYPE,TRAN,MODEL
  read -rp "Install onto which disk (e.g. nvme0n1 or sda)? " d
  DISK="/dev/${d#/dev/}"
fi
# accept /dev/disk/by-id/..., by-label/..., by-uuid/... too: resolve to the real device node
# (e.g. /dev/nvme0n1). Without this, the "${DISK}p1"/"${DISK}p2" logic below would silently build
# a nonsense path out of an alias and fail confusingly deep inside partitioning/formatting.
[[ -e $DISK ]] && DISK="$(readlink -f "$DISK")"
[[ -b $DISK ]] || { echo "block device not found: '$DISK'"; exit 1; }
[[ -d /sys/firmware/efi ]] || { echo "not booted in UEFI mode"; exit 1; }
# retry a few times: right after booting the live ISO, DHCP/DNS may not be ready yet
for _ in 1 2 3 4 5; do ping -c1 -W5 archlinux.org >/dev/null 2>&1 && break; sleep 2; done
ping -c1 -W5 archlinux.org >/dev/null 2>&1 || { echo "no network (connect first: LAN cable, or iwctl for WLAN; test: ping archlinux.org)"; exit 1; }

# ---------------------------------------------------------------- confirm and collect the password
lsblk "$DISK"
echo; echo "ALL DATA ON $DISK WILL BE ERASED."
read -rp "Type the device path again to confirm: " c; [[ $c == "$DISK" ]] || { echo aborted; exit 1; }
read -rsp "Password for $USERNAME (also root): " PW; echo
[[ -n $PW ]] || { echo "empty password"; exit 1; }

# ---------------------------------------------------------------- hardware detection
hw_detect; echo "Hardware: $(hw_summary)"
UCODE="$(hw_ucode_pkg)"
FWPKGS="$(hw_firmware_packages | tr '\n' ' ')"   # e.g. linux-firmware-marvell: WiFi works on the first boot

# ---------------------------------------------------------------- partition layout and mount options
# nvme/mmcblk devices need a "p" before the partition number (nvme0n1p1); plain disks don't (sda1)
P=""; [[ $DISK == *nvme* || $DISK == *mmcblk* ]] && P="p"
ESP="${DISK}${P}1"; ROOT="${DISK}${P}2"
# ssd flag only for non-rotational disks (btrfs detects it itself, but be explicit)
SSD=""; [[ $(cat "/sys/block/${DISK#/dev/}/queue/rotational" 2>/dev/null) == 0 ]] && SSD=",ssd,discard=async"
# noatime (no write-per-read), zstd level 1 compression, discard=async on SSDs, the v2 space cache
MO="rw,noatime,compress=zstd:1${SSD},space_cache=v2"

# ---------------------------------------------------------------- partition, format, mount
timedatectl set-ntp true
umount -R /mnt 2>/dev/null || true
sgdisk --zap-all "$DISK"
sgdisk -n1:0:+1G -t1:ef00 -c1:ESP -n2:0:0 -t2:8300 -c2:archroot "$DISK"
partprobe "$DISK"; sleep 1
mkfs.fat -F32 -n ESP "$ESP"
mkfs.btrfs -f -L arch "$ROOT"

# btrfs subvolumes: @ (root), @home, @log, @pkg (pacman cache), @snapshots - each mounted
# separately below so snapper can snapshot @ without dragging /home, logs or the package cache along
mount "$ROOT" /mnt
for s in @ @home @log @pkg @snapshots; do btrfs subvolume create "/mnt/$s"; done
umount /mnt
mount -o "$MO,subvol=@" "$ROOT" /mnt
mkdir -p /mnt/{boot,home,var/log,var/cache/pacman/pkg,.snapshots}
mount -o "$MO,subvol=@home"      "$ROOT" /mnt/home
mount -o "$MO,subvol=@log"       "$ROOT" /mnt/var/log
mount -o "$MO,subvol=@pkg"       "$ROOT" /mnt/var/cache/pacman/pkg
mount -o "$MO,subvol=@snapshots" "$ROOT" /mnt/.snapshots
mount "$ESP" /mnt/boot

# ---------------------------------------------------------------- base system (pacstrap)
sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
pacstrap -K /mnt base linux linux-firmware $UCODE $FWPKGS btrfs-progs networkmanager \
  sudo git nano base-devel man-db
genfstab -U /mnt >> /mnt/etc/fstab

# put the kit where it will be found after the first boot
mkdir -p "/mnt/home/$USERNAME"
cp -a "$KIT" "/mnt/home/$USERNAME/rebuild"

ROOT_UUID="$(blkid -s UUID -o value "$ROOT")"
# NOT "bash -e": on some firmware (seen on a Dell Latitude) bootctl install fails to register the
# NVRAM boot entry (Secure Boot / NVRAM full / vendor quirk) even though the ESP files it copies
# are fine. With -e that single failure used to abort the whole block silently, before loader.conf,
# the arch.conf boot entry and "systemctl enable NetworkManager" were ever written - the firmware
# then had nothing bootable to find at all. Now every step runs regardless, and a failed bootctl is
# reported loudly with a recovery hint instead of vanishing.
arch-chroot /mnt /bin/bash <<CHROOT
set -uo pipefail
# locale, keymap, hostname
ln -sf /usr/share/zoneinfo/$TZONE /etc/localtime
sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen; locale-gen
echo LANG=en_US.UTF-8 > /etc/locale.conf
echo KEYMAP=$KEYMAP > /etc/vconsole.conf
echo $HOSTNAME_NEW > /etc/hostname
# user + sudo (the home dir was already created above as the kit's destination)
useradd -m -G wheel -s /bin/bash "$USERNAME"
# the home dir and the kit copy in it were created as root before the user existed; useradd -m
# leaves them root-owned, and git/snapshot.sh would then fail as the user ("dubious ownership")
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME"; chmod 700 "/home/$USERNAME"
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel; chmod 440 /etc/sudoers.d/10-wheel
# initramfs: systemd hooks instead of the legacy busybox ones
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P
# bootctl, run inside arch-chroot, always refuses to touch EFI/NVRAM variables here ("Not booted
# with EFI or running in a container, skipping EFI variable modifications" - confirmed on a Dell
# Latitude): it still writes the ESP files fine (incl. the generic EFI/BOOT/BOOTX64.EFI fallback
# every firmware recognises), just not the NVRAM boot entry. That is registered further down,
# after leaving the chroot, with efibootmgr instead.
bootctl install || echo "==> !! bootctl install reported a problem (see above). The ESP files may be incomplete."
printf 'default arch.conf\ntimeout 2\nconsole-mode max\n' > /boot/loader/loader.conf
# no separate microcode initrd line: the microcode hook above already puts it into the initramfs
cat > /boot/loader/entries/arch.conf <<ENTRY
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
options root=UUID=$ROOT_UUID rootflags=subvol=@ rw
ENTRY
systemctl enable NetworkManager systemd-timesyncd
CHROOT

# passwords outside the heredoc above: that one is unquoted, so a password with $, ` or \ would be
# expanded (or break the whole block) inside the chroot. chpasswd reads them verbatim from stdin.
printf '%s:%s\n' "$USERNAME" "$PW" root "$PW" | arch-chroot /mnt chpasswd \
  || echo "==> !! setting the passwords failed. Before rebooting: arch-chroot /mnt passwd $USERNAME (and passwd for root)"

# register the NVRAM boot entry from OUT HERE, not from inside the chroot (see above): the live
# medium's own EFI variables work normally. The ESP fallback file makes the disk bootable even if
# this fails or efibootmgr is missing, but firmware may then need the disk picked once from its
# one-time boot menu (F12/F2 on Dell) instead of booting it by default.
if command -v efibootmgr >/dev/null; then
  # idempotent: a re-run (repair, second attempt) must not pile up duplicate "Linux Boot Manager"
  # entries (seen on a Dell Latitude after two install-base.sh runs) - drop any old ones first
  while read -r bn; do efibootmgr -b "$bn" -B >/dev/null 2>&1; done \
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
