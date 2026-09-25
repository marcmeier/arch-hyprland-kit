# shellcheck shell=bash
# Package groups: packages/NAME.list (or personal/packages/NAME.list), one package per line,
# "aur:" in front of AUR packages. The manifest's "group" lines pick the groups for this machine.
#
# The lists are written by hand (or with "driftless packages add"), never recorded from what a
# machine happens to have: a package you try out on one machine stays there. What is installed
# but in no list is shown by "driftless packages", so you decide: add it, or remove it.

group_file() {
  local f
  for f in "$DRIFTLESS/packages/$1.list" "$DRIFTLESS/personal/packages/$1.list"; do
    [[ -r $f ]] && {
      echo "$f"
      return 0
    }
  done
  return 1
}

# wanted: "repo NAME" / "aur NAME" for every package this machine should have, sorted
wanted() {
  local group file
  while read -r group; do
    file=$(group_file "$group") || {
      warn "manifest names group $group, but there is no packages/$group.list"
      continue
    }
    grep -v '^\s*\(#\|$\)' "$file" | sed -E 's/\s+#.*//; s/^aur:(.*)/aur \1/; t; s/^/repo /'
  done < <(manifest group) | sort -u
}

wanted_names() { wanted | awk '{ print $2 }' | sort -u; }

# missing KIND: wanted packages of KIND (repo|aur) that are not installed
missing() {
  comm -23 <(wanted | awk -v k="$1" '$1 == k { print $2 }' | sort -u) <(pacman -Qq | sort -u)
}

# unlisted: explicitly installed packages that no group of this machine lists
unlisted() {
  comm -23 <(pacman -Qqe | sort -u) <({
    wanted_names
    # the AUR helper and this kit's own package are never in a list
    printf '%s\n' yay yay-debug yay-bin yay-bin-debug driftless-system
  } | sort -u)
}

# install_repo PKG...: through the root helper and a password dialog (pkexec), or plain sudo in a
# terminal. The helper takes package names only and runs nothing but pacman -S --needed.
install_repo() {
  (($#)) || return 0
  if [[ -t 0 ]]; then
    sudo pacman -S --needed -- "$@"
  elif [[ -x /usr/lib/driftless/install-packages ]]; then
    pkexec /usr/lib/driftless/install-packages "$@"
  else
    die "no terminal and no driftless-system yet: install them with  sudo pacman -S --needed $*"
  fi
}

# install_aur PKG...: yay, which shows every PKGBUILD diff before it builds. Needs a terminal: an AUR
# package is a script from the internet and is never built unattended.
install_aur() {
  (($#)) || return 0
  [[ -t 0 ]] || die "AUR packages are only built in a terminal: driftless packages install"
  command -v yay > /dev/null || die "yay is missing (install/bootstrap.sh installs it)"
  yay -S --needed --answerdiff All --answerclean None --answeredit None -- "$@"
}

cmd_packages() {
  local sub=${1:-status}
  shift || true
  case $sub in
    status)
      local repo aur extra
      repo=$(missing repo | paste -sd' ')
      aur=$(missing aur | paste -sd' ')
      extra=$(unlisted | paste -sd' ')
      echo "groups here: $(manifest group | paste -sd' ')"
      [[ -z $repo ]] && echo "repo packages: all installed" || echo "missing (repo): $repo"
      [[ -z $aur ]] && echo "AUR packages: all installed" || echo "missing (AUR): $aur"
      [[ -z $extra ]] || echo "installed, but in no list: $extra
  keep one everywhere:  driftless packages add NAME [GROUP]
  or remove it here:    sudo pacman -Rns NAME"
      ;;
    install)
      # "repo" or "aur" alone: e.g. the repo part over SSH, the AUR part later in a terminal
      local only=${1:-}
      mapfile -t r < <(missing repo)
      mapfile -t a < <(missing aur)
      [[ $only == aur ]] || install_repo "${r[@]}"
      [[ $only == repo ]] || install_aur "${a[@]}"
      ;;
    add)
      local name=${1:?usage: driftless packages add NAME [GROUP]} group=${2:-} file entry
      if [[ -z $group ]]; then
        group=$(find "$DRIFTLESS/packages" -name '*.list' ! -name 'hw-*' -printf '%f\n' | sed 's/\.list$//' | sort |
          walker --dmenu -p "Group for $name" 2> /dev/null) || true
        [[ -n $group ]] || die "no group given"
      fi
      file=$(group_file "$group") || die "no group $group"
      entry=$name
      pacman -Qqm "$name" > /dev/null 2>&1 && entry="aur:$name"
      grep -qxF "$entry" "$file" && {
        echo "$name is already in $group"
        return 0
      }
      {
        grep '^#' "$file"
        {
          grep -v '^#' "$file"
          echo "$entry"
        } | sort -u
      } > "$file.new"
      mv "$file.new" "$file"
      echo "added $entry to $group (the next sync takes it to your other machines)"
      ;;
    remove)
      local name=${1:?usage: driftless packages remove NAME} file
      for file in "$DRIFTLESS"/packages/*.list "$DRIFTLESS"/personal/packages/*.list; do
        [[ -r $file ]] && sed -i -E "/^(aur:)?$(printf '%s' "$name" | sed 's/[.+]/\\&/g')\$/d" "$file"
      done
      echo "removed $name from the lists. The other machines keep it until you remove it there."
      ;;
    *) die "usage: driftless packages [status|install [repo|aur]|add NAME [GROUP]|remove NAME]" ;;
  esac
}
