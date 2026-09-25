# shellcheck shell=bash
# Symlinks from the home into the repository, as the manifest's "link" lines say.
#
# The repository is the source: ~/.config/hypr IS home/.config/hypr, so an edit in either place is the
# same edit and git sees it at once. Nothing is copied back and forth.
#
# $STATE/links remembers which targets driftless manages. That tells two cases apart:
#   - a target driftless never managed (first run on a machine): the live file or folder moves to
#     $STATE/backup/<time>/, files only the live folder had are kept in the repository folder
#     (untracked, git shows them), then the link is made
#   - a managed target that is a plain file again: a program replaced the link (many save through a
#     temporary file and a rename). Its content is what the program wrote, so it goes into the
#     repository and the link comes back ("heal")
# Links that left the manifest are removed, if they still point into the repository.
#
# --adopt TARGET... (moving a machine over from somewhere else): for these targets the live version
# wins on the first run; it is copied over the repository's (git shows the difference), then linked.
# --adopt alone: every target.

LINKS_STATE=$STATE/links

# link_entries: "TARGET<TAB>SOURCE" for every link line of this machine, sources absolute
link_entries() {
  local target source
  while read -r target source; do
    [[ -n $target ]] || continue
    source=${source:-home/$target}
    printf '%s\t%s\n' "$target" "$DRIFTLESS/$source"
  done < <(manifest link)
}

managed() { grep -qxF -- "$1" "$LINKS_STATE" 2> /dev/null; }

# points_into_repo PATH: is PATH a symlink whose target lies in this repository?
points_into_repo() {
  [[ -L $1 ]] || return 1
  local dest
  dest=$(readlink "$1")
  [[ $dest == "$DRIFTLESS"/* ]]
}

LINK_BACKUP=""
backup_live() { # backup_live TARGET: move ~/TARGET into this run's backup folder
  [[ -n $LINK_BACKUP ]] || LINK_BACKUP=$STATE/backup/$(date +%Y-%m-%dT%H%M%S)
  mkdir -p "$(dirname "$LINK_BACKUP/$1")"
  mv "$HOME/$1" "$LINK_BACKUP/$1"
}

# heal TARGET SOURCE: take a plain file or folder that replaced a managed link into the repository
heal() {
  local live=$HOME/$1 src=$2
  if [[ -d $live ]]; then
    mkdir -p "$src"
    cp -a "$live/." "$src/"
    rm -rf "$live"
  else
    cp -a "$live" "$src"
    rm -f "$live"
  fi
  ln -s "$src" "$live"
  echo "healed: ~/$1 (a program had replaced the link, its content is in the repository now)"
}

# link_one TARGET SOURCE DRY ADOPT: prints what it does; returns 0 unless something failed
link_one() {
  local target=$1 src=$2 dry=$3 adopt=${4:-0} live=$HOME/$1 kept
  if [[ ! -e $src && ! -L $src ]]; then
    return 0 # e.g. hosts/<host> on a machine without a host folder
  fi
  if [[ -L $live && $(readlink "$live") == "$src" ]]; then
    return 0
  fi
  if ((dry)); then
    if [[ -L $live ]]; then
      echo "relink: ~/$target"
    elif [[ -e $live ]]; then
      { managed "$target" || ((adopt)); } && echo "take over into the repository: ~/$target" || echo "replace (backup first): ~/$target"
    else
      echo "link: ~/$target"
    fi
    return 0
  fi
  mkdir -p "$(dirname "$live")"
  if [[ -L $live ]]; then
    rm -f "$live"
  elif [[ -e $live ]] && { managed "$target" || ((adopt)); }; then
    heal "$target" "$src"
    return 0
  elif [[ -e $live ]]; then
    if [[ -f $live && -f $src ]] && cmp -s "$live" "$src"; then
      rm -f "$live" # same content: nothing to keep
    else
      if [[ -d $live && -d $src ]]; then
        # files only this machine has stay available: copied into the repository folder, untracked
        kept=$(cd "$live" && find . \( -type f -o -type l \) | while read -r f; do [[ -e $src/$f || -L $src/$f ]] || echo "$f"; done)
        if [[ -n $kept ]]; then
          cp -an "$live/." "$src/"
          echo "kept in the repository (untracked): $(wc -l <<< "$kept") file(s) of ~/$target"
        fi
      fi
      backup_live "$target"
    fi
  fi
  ln -s "$src" "$live"
  echo "linked: ~/$target"
}

# unlink_stale: remove managed links that are no longer in the manifest
unlink_stale() {
  local dry=$1 target
  [[ -f $LINKS_STATE ]] || return 0
  while IFS= read -r target; do
    [[ -n $target ]] || continue
    grep -qxF -- "$target" <<< "$WANTED" && continue
    if points_into_repo "$HOME/$target"; then
      if ((dry)); then echo "unlink: ~/$target"; else
        rm -f "$HOME/$target"
        echo "unlinked: ~/$target (left the manifest)"
      fi
    fi
  done < "$LINKS_STATE"
}

# cmd_link [--dry-run] [--adopt [TARGET...]]
cmd_link() {
  local dry=0 adopt_all=0 adopt target src rc=0 arg
  local adopt_only=()
  for arg in "$@"; do
    case $arg in
      --dry-run | -n) dry=1 ;;
      --adopt) adopt_all=1 ;;
      -*) die "usage: driftless link [--dry-run] [--adopt [TARGET...]]" ;;
      *) adopt_only+=("$arg") ;;
    esac
  done
  # targets named after --adopt: only those
  ((${#adopt_only[@]})) && adopt_all=0
  mkdir -p "$STATE"
  WANTED=""
  while IFS=$'\t' read -r target src; do
    WANTED+="$target"$'\n'
    adopt=$adopt_all
    [[ " ${adopt_only[*]} " == *" $target "* ]] && adopt=1
    link_one "$target" "$src" "$dry" "$adopt" || rc=1
  done < <(link_entries)
  unlink_stale "$dry"
  if ((!dry)); then
    # only targets whose link exists count as managed; a skipped source is not
    while IFS=$'\t' read -r target src; do
      [[ -L $HOME/$target ]] && echo "$target"
    done < <(link_entries) > "$LINKS_STATE"
    [[ -n $LINK_BACKUP ]] && echo "previous files: $LINK_BACKUP"
  fi
  return "$rc"
}

# heal_all: the sync's first step. Only managed targets, and only when a program replaced the link.
heal_all() {
  local target src
  while IFS=$'\t' read -r target src; do
    [[ -e $src || -L $src ]] || continue
    if managed "$target" && [[ -e $HOME/$target && ! -L $HOME/$target ]]; then
      heal "$target" "$src"
    fi
  done < <(link_entries)
}

# link_problems: one line per link that is not as the manifest wants (for verify and status)
# shellcheck disable=SC2088 # "~/" is only text for people here
link_problems() {
  local target src
  while IFS=$'\t' read -r target src; do
    [[ -e $src || -L $src ]] || continue
    if [[ ! -L $HOME/$target ]]; then
      if [[ -e $HOME/$target ]]; then
        echo "~/$target is a plain file or folder (driftless link)"
      else echo "~/$target is missing (driftless link)"; fi
    elif [[ $(readlink "$HOME/$target") != "$src" ]]; then
      echo "~/$target points to $(readlink "$HOME/$target")"
    fi
  done < <(link_entries)
}
