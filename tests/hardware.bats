#!/usr/bin/env bats
# lib/hardware.sh: packages chosen per machine

setup() {
  source "$BATS_TEST_DIRNAME/../lib/hardware.sh"
  HW_CPU=amd HW_VIRT="" HW_GPUS="" HW_LAPTOP=0 HW_SURFACE=0
}

@test "hw_packages: nothing at all in a VM without microcode or GPU packages" {
  HW_VIRT=kvm
  mapfile -t pkgs < <(hw_packages)
  [ "${#pkgs[@]}" -eq 0 ] # an empty line would reach pacman as a package name ""
}

@test "hw_packages: microcode and GPU driver on real hardware" {
  HW_GPUS=amd
  run hw_packages
  [[ $output == *amd-ucode* ]]
  [[ $output == *vulkan-radeon* ]]
}
