#!/usr/bin/env bats
# lib/hardware.sh: facts from a fake /proc and /sys

setup() {
  T=$BATS_TEST_TMPDIR
  mkdir -p "$T/proc" "$T/sys/class/dmi/id"
  export HW_PROC=$T/proc HW_SYS=$T/sys HW_VIRT_OVERRIDE=""
  source "$BATS_TEST_DIRNAME/../lib/hardware.sh"
}

gpu() { # gpu N VENDOR
  mkdir -p "$T/sys/class/drm/card$1/device"
  echo 0x030000 > "$T/sys/class/drm/card$1/device/class"
  echo "$2" > "$T/sys/class/drm/card$1/device/vendor"
}

@test "AMD desktop: microcode and GPU facts" {
  echo "vendor_id	: AuthenticAMD" > "$T/proc/cpuinfo"
  gpu 0 0x1002
  hw_detect
  run hw_facts
  [ "$output" = "$(printf 'cpu-amd\ngpu-amd')" ]
}

@test "hybrid notebook: Intel + NVIDIA with a battery" {
  echo "vendor_id	: GenuineIntel" > "$T/proc/cpuinfo"
  gpu 0 0x8086
  gpu 1 0x10de
  mkdir -p "$T/sys/class/power_supply/BAT0"
  hw_detect
  run hw_facts
  [[ $output == *gpu-intel* && $output == *gpu-nvidia* && $output == *hybrid* && $output == *laptop* ]]
  run hw_early_modules
  [[ $output == *nvidia_drm* ]]
}

@test "a VM has no microcode fact" {
  echo "vendor_id	: AuthenticAMD" > "$T/proc/cpuinfo"
  HW_VIRT_OVERRIDE=kvm
  hw_detect
  run hw_facts
  [ "$output" = vm ]
}

@test "Surface with Marvell WiFi" {
  echo "Microsoft Corporation" > "$T/sys/class/dmi/id/sys_vendor"
  echo "Surface Pro" > "$T/sys/class/dmi/id/product_name"
  mkdir -p "$T/sys/bus/pci/devices/0000:01:00.0"
  echo 0x11ab > "$T/sys/bus/pci/devices/0000:01:00.0/vendor"
  hw_detect
  run hw_facts
  [[ $output == *surface* && $output == *marvell* ]]
}

@test "render-only and connector entries are not GPUs" {
  mkdir -p "$T/sys/class/drm/card0-DP-1/device"
  echo 0x1002 > "$T/sys/class/drm/card0-DP-1/device/vendor"
  hw_detect
  [ -z "$HW_GPUS" ]
}
