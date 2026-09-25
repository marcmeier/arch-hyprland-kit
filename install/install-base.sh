#!/usr/bin/env bash
# =============================================================================
# install-base.sh - run from the Arch live ISO. Creates the base system driftless builds on:
# GPT with a 1 GiB ESP and btrfs (@ @home @log @pkg @snapshots), optionally inside LUKS2,
# systemd-boot with unified kernel images, NetworkManager, the user, and this repository in
# ~/.local/share/driftless. DESTROYS ALL DATA on the chosen disk.
#
#   bash install/install-base.sh [/dev/DISK] [--user NAME] [--hostname NAME] [--keymap MAP]
#                                [--tz ZONE] [--encrypt]
#
# --encrypt  the whole btrfs goes into LUKS2 (asks for a disk password at every boot). Strongly
#            advised on notebooks. Afterwards the TPM can unlock it instead: docs/encryption.md.
# Without a disk it lists the disks and asks. Defaults come from personal/config when present.
# Then: reboot, log in, connect (nmtui), sudo bash ~/.local/share/driftless/install/bootstrap.sh
# =============================================================================
set -euo pipefail
SRC=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)

# work from a copy: the repository may live under /mnt (a USB stick), which "umount -R /mnt" below
# would pull away mid-run
KIT=/root/.driftless-install
rm -rf "$KIT"
cp -a "$SRC" "$KIT"
# shellcheck source=lib/hardware.sh
source "$KIT/lib/hardware.sh"
# shellcheck source=lib/boot.sh
source "$KIT/lib/boot.sh"
DEFAULT_USER=user DEFAULT_KEYMAP=us DEFAULT_TIMEZONE=UTC
# shellcheck source=/dev/null
[[ -r $KIT/personal/config ]] && source "$KIT/personal/config"

DISK="" USERNAME=$DEFAULT_USER HOSTNAME_NEW=archlinux KEYMAP=$DEFAULT_KEYMAP TZONE=$DEFAULT_TIMEZONE ENCRYPT=0
while (($#)); do
  case $1 in
    --user) USERNAME=$2 && shift 2 ;;
    --hostname) HOSTNAME_NEW=$2 && shift 2 ;;
    --keymap) KEYMAP=$2 && shift 2 ;;
    --tz) TZONE=$2 && shift 2 ;;
    --encrypt) ENCRYPT=1 && shift ;;
    -h | --help) sed -n '2,16p' "$0" && exit 0 ;;
    /dev/*) DISK=$1 && shift ;;
    *) echo "unknown argument: $1" && exit 1 ;;
  esac
done

# ---------------------------------------------------------------- checks
[[ $EUID -eq 0 ]] || { echo "run as root" && exit 1; }
[[ -d /sys/firmware/efi ]] || { echo "not booted in UEFI mode" && exit 1; }
if [[ -z $DISK ]]; then
  lsblk -d -e7,11 -o NAME,SIZE,TYPE,TRAN,MODEL
  read -rp "Install onto which disk (e.g. nvme0n1 or sda)? " d
  DISK=/dev/${d#/dev/}
fi
[[ -e $DISK ]] && DISK=$(readlink -f "$DISK") # /dev/disk/by-id/... -> the node the partition names need
[[ -b $DISK ]] || { echo "block device not found: '$DISK'" && exit 1; }
# DHCP/DNS may still be coming up right after boot
for _ in 1 2 3 4 5; do
  if ping -c1 -W5 archlinux.org > /dev/null 2>&1; then break; fi
  sleep 2
done
ping -c1 -W5 archlinux.org > /dev/null 2>&1 || { echo "no network (LAN, or iwctl for WLAN)" && exit 1; }

lsblk "$DISK"
echo
echo "ALL DATA ON $DISK WILL BE ERASED. User $USERNAME, hostname $HOSTNAME_NEW, keymap $KEYMAP, $TZONE, encryption: $( ((ENCRYPT)) && echo yes || echo no)"
read -rp "Type the device path again to confirm: " c
[[ $c == "$DISK" ]] || { echo aborted && exit 1; }
read -rsp "Password for $USERNAME (also root): " PW && echo
[[ -n $PW ]] || { echo "empty password" && exit 1; }
if ((ENCRYPT)); then
  read -rsp "Disk password (asked at every boot; empty: the same as above): " LUKS_PW && echo
  LUKS_PW=${LUKS_PW:-$PW}
fi

hw_detect
echo "Hardware: $(hw_summary)"
EXTRA=()
[[ -z $HW_VIRT && $HW_CPU != other ]] && EXTRA+=("$HW_CPU-ucode")
((HW_MARVELL)) && EXTRA+=(linux-firmware-marvell) # the Surface WiFi needs it on the first boot

# ---------------------------------------------------------------- partitions and file systems
PART_SEP=""
[[ $DISK == *nvme* || $DISK == *mmcblk* ]] && PART_SEP=p
ESP_DEV=$DISK${PART_SEP}1
ROOT_PART=$DISK${PART_SEP}2
OPTS="rw,noatime,compress=zstd:1,space_cache=v2"
[[ $(cat "/sys/block/${DISK#/dev/}/queue/rotational" 2> /dev/null) == 0 ]] && OPTS+=",ssd,discard=async"

timedatectl set-ntp true
umount -R /mnt 2> /dev/null || true
cryptsetup close cryptroot 2> /dev/null || true
sgdisk --zap-all "$DISK"
sgdisk -n1:0:+1G -t1:ef00 -c1:ESP -n2:0:0 -t2:8309 -c2:archroot "$DISK"
((ENCRYPT)) || sgdisk -t2:8304 "$DISK"
partprobe "$DISK"
udevadm settle
mkfs.fat -F32 -n ESP "$ESP_DEV"
ROOT_DEV=$ROOT_PART LUKS_UUID=""
if ((ENCRYPT)); then
  printf '%s' "$LUKS_PW" | cryptsetup luksFormat --type luks2 --batch-mode --key-file - "$ROOT_PART"
  printf '%s' "$LUKS_PW" | cryptsetup open --key-file - --allow-discards --persistent "$ROOT_PART" cryptroot
  ROOT_DEV=/dev/mapper/cryptroot
  LUKS_UUID=$(blkid -s UUID -o value "$ROOT_PART")
fi
mkfs.btrfs -f -L arch "$ROOT_DEV"
mount "$ROOT_DEV" /mnt
for s in @ @home @log @pkg @snapshots; do btrfs subvolume create "/mnt/$s"; done
umount /mnt
mount -o "$OPTS,subvol=@" "$ROOT_DEV" /mnt
mkdir -p /mnt/{boot,home,var/log,var/cache/pacman/pkg,.snapshots}
mount -o "$OPTS,subvol=@home" "$ROOT_DEV" /mnt/home
mount -o "$OPTS,subvol=@log" "$ROOT_DEV" /mnt/var/log
mount -o "$OPTS,subvol=@pkg" "$ROOT_DEV" /mnt/var/cache/pacman/pkg
mount -o "$OPTS,subvol=@snapshots" "$ROOT_DEV" /mnt/.snapshots
mount -o fmask=0077,dmask=0077 "$ESP_DEV" /mnt/boot

# ---------------------------------------------------------------- base system
sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
pacstrap -K /mnt base linux linux-firmware "${EXTRA[@]}" btrfs-progs networkmanager sudo git nano base-devel man-db
genfstab -U /mnt >> /mnt/etc/fstab
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_DEV")

# the repository with its history: the sync needs .git, and origin is where it syncs with
mkdir -p "/mnt/home/$USERNAME/.local/share"
# (from the copy: the original may have been under /mnt)
git clone -q "$KIT" "/mnt/home/$USERNAME/.local/share/driftless"
origin=$(git -C "$KIT" remote get-url origin 2> /dev/null || true)
[[ -n $origin ]] && git -C "/mnt/home/$USERNAME/.local/share/driftless" remote set-url origin "$origin"

# no -e in the chroot: one failing step must not skip the boot setup after it
arch-chroot /mnt /bin/bash -s -- "$USERNAME" "$HOSTNAME_NEW" "$KEYMAP" "$TZONE" "$ROOT_UUID" "$LUKS_UUID" << 'CHROOT'
set -uo pipefail
USERNAME=$1 HOSTNAME_NEW=$2 KEYMAP=$3 TZONE=$4 ROOT_UUID=$5 LUKS_UUID=$6
source "/home/$USERNAME/.local/share/driftless/lib/boot.sh"
ln -sf "/usr/share/zoneinfo/$TZONE" /etc/localtime
hwclock --systohc
sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen && locale-gen
echo LANG=en_US.UTF-8 > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
echo "$HOSTNAME_NEW" > /etc/hostname
useradd -m -G wheel -s /bin/bash "$USERNAME"
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME" && chmod 700 "/home/$USERNAME"
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel && chmod 440 /etc/sudoers.d/10-wheel
# systemd initramfs (driftless-system later adds the boot splash via mkinitcpio.conf.d)
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)/' /etc/mkinitcpio.conf
uki_cmdline "$ROOT_UUID" "$LUKS_UUID"
uki_presets
bootctl install || echo "==> !! bootctl install reported a problem (see above)"
uki_loader arch-linux.efi
mkinitcpio -P
systemctl enable NetworkManager systemd-timesyncd systemd-boot-update
CHROOT

# not in the heredoc, where $ ` or \ in a password would be expanded
printf '%s:%s\n' "$USERNAME" "$PW" root "$PW" | arch-chroot /mnt chpasswd ||
  echo "==> !! setting the passwords failed. Before rebooting: arch-chroot /mnt passwd $USERNAME"

# bootctl cannot write EFI variables inside a chroot: register the boot entry from out here. The
# fallback EFI/BOOT/BOOTX64.EFI works too, but may have to be picked in the firmware's boot menu.
if command -v efibootmgr > /dev/null; then
  while read -r bn; do efibootmgr -b "$bn" -B > /dev/null 2>&1; done \
    < <(efibootmgr | awk -F'[ *]' '/Linux Boot Manager/{ sub(/^Boot/, "", $1); print $1 }')
  efibootmgr -c -d "$DISK" -p 1 -L "Linux Boot Manager" -l '\EFI\systemd\systemd-bootx64.efi' > /dev/null &&
    echo "==> boot entry registered. Put it first in the firmware's boot order (not only the F12 menu)." ||
    echo "==> !! no boot entry registered: pick the disk in the firmware's boot menu (F12/F2)"
fi

echo
echo "Base installed. Now: umount -R /mnt && reboot"
echo "Log in as $USERNAME, connect (nmtui), then:  sudo bash ~/.local/share/driftless/install/bootstrap.sh"
