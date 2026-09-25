# shellcheck shell=bash
# driftless system: build the driftless-system package from system/ and install it.

# the package version follows the repository: commits that touched system/, plus the last one's id
system_version() {
  local n h
  n=$(git -C "$DRIFTLESS" rev-list --count HEAD -- system 2> /dev/null || echo 0)
  h=$(git -C "$DRIFTLESS" log -1 --format=%h -- system 2> /dev/null)
  echo "r$n.${h:-0}"
}

# system_build DIR: build the package into DIR, print its path
system_build() {
  local out=$1 build
  build=$(mktemp -d)
  cp -a "$DRIFTLESS/system/." "$build/"
  (cd "$build" && DRIFTLESS_SYSTEM_VERSION=$(system_version) PKGDEST=$out makepkg -f --nodeps --noconfirm > /dev/null) ||
    die "makepkg failed in $build"
  rm -rf "$build"
  find "$out" -name 'driftless-system-*.pkg.tar.*' -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-
}

cmd_system() {
  local out pkg
  out=$(mktemp -d)
  pkg=$(system_build "$out")
  echo "built: $(basename "$pkg")"
  if [[ ${1:-} == --build-only ]]; then
    echo "$pkg"
    return 0
  fi
  [[ -t 0 ]] || die "run it in a terminal: it installs with sudo"
  sudo pacman -U --needed "$pkg"
  rm -rf "$out"
}
