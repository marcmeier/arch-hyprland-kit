# shellcheck shell=bash
# Hardware detection from /proc and sysfs only (no lspci), so it works on the live ISO, in a chroot
# and on the installed system. The results are facts; the manifest turns facts into package groups
# (packages/hw-*.list) and settings, so this file never names a package.
#
# After hw_detect:
#   HW_CPU     amd | intel | other
#   HW_GPUS    space separated subset of: amd intel nvidia   (empty in VMs / unknown)
#   HW_VIRT    "" on real hardware, else the systemd-detect-virt name
#   HW_LAPTOP  1 on notebooks (chassis type or battery), else 0
#   HW_SURFACE 1 on Microsoft Surface devices, else 0
#   HW_MARVELL 1 with a Marvell PCI device (the Surface WiFi needs linux-firmware-marvell)

# roots for tests: a fake /proc and /sys
HW_PROC=${HW_PROC:-/proc}
HW_SYS=${HW_SYS:-/sys}

hw_detect() {
  local v c
  case "$(grep -m1 '^vendor_id' "$HW_PROC/cpuinfo" 2> /dev/null)" in
    *AuthenticAMD*) HW_CPU=amd ;;
    *GenuineIntel*) HW_CPU=intel ;;
    *) HW_CPU=other ;;
  esac

  # GPU vendors: every DRM card whose PCI class is a display controller (0x03xxxx)
  HW_GPUS=""
  for c in "$HW_SYS"/class/drm/card[0-9]*; do
    # card0, not the connectors (card0-DP-1)
    [[ -e $c/device/vendor && ${c##*/} != *-* ]] || continue
    [[ $(cat "$c/device/class" 2> /dev/null) == 0x03* ]] || continue
    v=$(cat "$c/device/vendor")
    case $v in
      0x1002) [[ " $HW_GPUS " == *" amd "* ]] || HW_GPUS+=" amd" ;;
      0x8086) [[ " $HW_GPUS " == *" intel "* ]] || HW_GPUS+=" intel" ;;
      0x10de) [[ " $HW_GPUS " == *" nvidia "* ]] || HW_GPUS+=" nvidia" ;;
    esac
  done
  HW_GPUS=${HW_GPUS# }

  if [[ -n ${HW_VIRT_OVERRIDE+x} ]]; then
    HW_VIRT=$HW_VIRT_OVERRIDE
  else
    HW_VIRT=$(systemd-detect-virt 2> /dev/null || true)
    [[ $HW_VIRT == none ]] && HW_VIRT=""
  fi

  HW_SURFACE=0
  [[ $(cat "$HW_SYS/class/dmi/id/sys_vendor" 2> /dev/null) == "Microsoft Corporation" &&
  $(cat "$HW_SYS/class/dmi/id/product_name" 2> /dev/null) == Surface* ]] && HW_SURFACE=1

  # chassis type says notebook, or there is a battery (covers odd chassis values)
  HW_LAPTOP=0
  case "$(cat "$HW_SYS/class/dmi/id/chassis_type" 2> /dev/null)" in 8 | 9 | 10 | 11 | 14 | 30 | 31 | 32) HW_LAPTOP=1 ;; esac
  compgen -G "$HW_SYS/class/power_supply/BAT*" > /dev/null && HW_LAPTOP=1

  HW_MARVELL=0
  grep -qsx '0x11ab' "$HW_SYS"/bus/pci/devices/*/vendor && HW_MARVELL=1
  return 0
}

hw_has_gpu() { [[ " $HW_GPUS " == *" $1 "* ]]; }

# hw_facts: one fact per line, for "if=" in the manifest
hw_facts() {
  local g
  # microcode belongs to the host in a VM
  [[ -z $HW_VIRT && $HW_CPU != other ]] && echo "cpu-$HW_CPU"
  for g in $HW_GPUS; do echo "gpu-$g"; done
  # NVIDIA next to an integrated GPU: prime-run for single programs
  hw_has_gpu nvidia && { hw_has_gpu intel || hw_has_gpu amd; } && echo hybrid
  [[ -n $HW_VIRT ]] && echo vm
  ((HW_LAPTOP)) && echo laptop
  ((HW_SURFACE)) && echo surface
  ((HW_MARVELL)) && echo marvell
  return 0
}

# kernel modules for the initramfs (early KMS: Plymouth and the console at native resolution)
hw_early_modules() {
  hw_has_gpu amd && echo amdgpu
  hw_has_gpu nvidia && echo nvidia nvidia_modeset nvidia_uvm nvidia_drm
  return 0
}

hw_summary() {
  echo "CPU: $HW_CPU | GPU: ${HW_GPUS:-none/unknown} | virt: ${HW_VIRT:-no} | laptop: $HW_LAPTOP | surface: $HW_SURFACE"
}
