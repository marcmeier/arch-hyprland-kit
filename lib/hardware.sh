#!/usr/bin/env bash
# Hardware detection for the rebuild kit. Sourced by install-base.sh and restore.sh.
# Works from the live ISO and from the installed system (sysfs only, no lspci needed).
#
# After `hw_detect`:
#   HW_CPU     amd | intel | other
#   HW_GPUS    space separated subset of: amd intel nvidia   (empty in VMs / unknown)
#   HW_VIRT    "" on real hardware, else the systemd-detect-virt name
#   HW_LAPTOP  1 on notebooks (chassis type or battery), else 0
#   HW_SURFACE 1 on Microsoft Surface devices, else 0
# hw_packages prints the hardware specific pacman packages for this machine.
# HW_PKG_REGEX matches every package hw_packages can produce; snapshot.sh uses it to keep them
# out of packages/pacman.txt (they are picked per machine, never copied from another one).

HW_PKG_REGEX='^(amd-ucode|intel-ucode|vulkan-radeon|lib32-vulkan-radeon|vulkan-intel|lib32-vulkan-intel|intel-media-driver|libva-intel-driver|nvidia-open-dkms|nvidia-utils|lib32-nvidia-utils|nvidia-prime|linux-headers|linux-lts-headers|sof-firmware|linux-firmware-marvell|linux-surface|linux-surface-headers|iptsd|power-profiles-daemon|upower|mesa-vdpau|libva-mesa-driver)$'

hw_detect() {
  local v c

  # CPU vendor, straight from /proc/cpuinfo (no lscpu dependency)
  case "$(grep -m1 '^vendor_id' /proc/cpuinfo 2>/dev/null)" in
    *AuthenticAMD*) HW_CPU=amd;;
    *GenuineIntel*) HW_CPU=intel;;
    *)              HW_CPU=other;;
  esac

  # GPU vendor(s): walk the DRM cards and look at their PCI vendor ID
  HW_GPUS=""
  for c in /sys/class/drm/card[0-9]*; do
    [[ -e $c/device/vendor && $c != *-* ]] || continue
    # PCI class 0x03xxxx = display controller (skips render-only / bridge oddities)
    [[ $(cat "$c/device/class" 2>/dev/null) == 0x03* ]] || continue
    v="$(cat "$c/device/vendor")"
    case "$v" in
      0x1002) [[ " $HW_GPUS " == *" amd "*    ]] || HW_GPUS+=" amd";;
      0x8086) [[ " $HW_GPUS " == *" intel "*  ]] || HW_GPUS+=" intel";;
      0x10de) [[ " $HW_GPUS " == *" nvidia "* ]] || HW_GPUS+=" nvidia";;
    esac
  done
  HW_GPUS="${HW_GPUS# }"

  HW_VIRT="$(systemd-detect-virt 2>/dev/null || true)"; [[ $HW_VIRT == none ]] && HW_VIRT=""

  # Microsoft Surface: needs the linux-surface kernel (touch, pen, sensors) from a third-party repo
  HW_SURFACE=0
  [[ $(cat /sys/class/dmi/id/sys_vendor 2>/dev/null) == "Microsoft Corporation" \
     && $(cat /sys/class/dmi/id/product_name 2>/dev/null) == Surface* ]] && HW_SURFACE=1

  # notebook: either the DMI chassis type says so, or a battery is present (covers odd chassis values)
  HW_LAPTOP=0
  case "$(cat /sys/class/dmi/id/chassis_type 2>/dev/null)" in 8|9|10|11|14|30|31|32) HW_LAPTOP=1;; esac
  compgen -G '/sys/class/power_supply/BAT*' >/dev/null && HW_LAPTOP=1
  return 0
}

hw_has_gpu() { [[ " $HW_GPUS " == *" $1 "* ]]; }

hw_ucode_pkg() {
  [[ -n $HW_VIRT ]] && return 0          # the host handles microcode
  case "$HW_CPU" in amd) echo amd-ucode;; intel) echo intel-ucode;; esac
}

hw_packages() {
  local p=()
  p+=( $(hw_ucode_pkg) )
  if hw_has_gpu amd;    then p+=(vulkan-radeon lib32-vulkan-radeon); fi
  if hw_has_gpu intel;  then p+=(vulkan-intel lib32-vulkan-intel intel-media-driver); fi
  if hw_has_gpu nvidia; then
    # -open: Turing (RTX 20 / GTX 16) and newer. DKMS so linux and linux-lts both get a module.
    p+=(nvidia-open-dkms nvidia-utils lib32-nvidia-utils linux-headers linux-lts-headers)
    # hybrid notebook: prime-run to start single programs on the dGPU
    { hw_has_gpu intel || hw_has_gpu amd; } && p+=(nvidia-prime)
  fi
  # Marvell PCI devices (e.g. the 88W8897 WiFi in Surface Pro/Book/Laptop): the firmware is only an
  # optional dependency of linux-firmware, so a fresh install has no WiFi without it
  grep -qsx '0x11ab' /sys/bus/pci/devices/*/vendor && p+=(linux-firmware-marvell)
  if (( HW_LAPTOP )); then
    p+=(power-profiles-daemon upower brightnessctl sof-firmware)
  fi
  printf '%s\n' "${p[@]}"
}

# modules for the initramfs (early KMS => Plymouth/console at native resolution)
hw_early_modules() {
  hw_has_gpu amd    && echo amdgpu
  hw_has_gpu nvidia && echo nvidia nvidia_modeset nvidia_uvm nvidia_drm
  return 0
}

# firmware packages that must already be in the base system for WiFi to work on first boot
hw_firmware_packages() { hw_packages | grep '^linux-firmware-' || true; }

hw_summary() {
  echo "CPU: $HW_CPU | GPU: ${HW_GPUS:-none/unknown} | virt: ${HW_VIRT:-no} | laptop: $HW_LAPTOP | surface: $HW_SURFACE"
}
