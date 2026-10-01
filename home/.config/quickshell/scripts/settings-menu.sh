#!/usr/bin/env bash
# Desktop settings, from a click on the avatar in the bar (or "Desktop settings" in the app launcher).
# Usage: settings-menu.sh [widgets|size|wallpaper|monitors|sync|keys]  (no argument: pick in walker)
#        settings-menu.sh wallpaper-pick IMAGE|random|previous|other|folder  (the walker wallpaper menu)
# Per machine choices: widget layout, bar size and monitor layout (~/.local/state) and the wallpaper with its
# colours (~/.config/wall.png and the files rendered from it, not in the repository). None of them
# travels to your other machines.
# Started from a service (the bar, elephant), a restart of that service would kill the menu halfway (the
# login screen step of a new wallpaper never ran): move to a scope of its own first.
if grep -q '\.service$' /proc/self/cgroup 2> /dev/null; then
  exec systemd-run --user --scope --collect --quiet -- "$0" "$@"
fi
SCRIPTS=$(dirname "$(readlink -f "$0")")
STATE=${XDG_STATE_HOME:-$HOME/.local/state}
# the wallpaper folder: WALLPAPER_DIR in the personal layer (e.g. a folder your cloud client syncs)
# shellcheck source=/dev/null
[[ -r ~/.config/driftless/personal/config ]] && source ~/.config/driftless/personal/config
WALLS=${WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}
pick() { walker --dmenu -p "$1"; }

# set-wallpaper renders the colours everywhere (the login screen part runs through pkexec, without a password)
set_wallpaper() {
  local name=${1##*/}
  [[ $1 == --random ]] && name="a random image"
  notify-send -a settings "Wallpaper" "Setting $name and its colours ..."
  if "$HOME/.config/theme/set-wallpaper.sh" "$1" > "$STATE/set-wallpaper.log" 2>&1; then
    notify-send -a settings "Wallpaper" "Done"
  else notify-send -a settings -u critical "Wallpaper" "Failed, see $STATE/set-wallpaper.log"; fi
}

wallpaper_other() {
  local f
  f=$(zenity --file-selection --title "Wallpaper" --filename "$HOME/Pictures/" \
    --file-filter "Images | *.png *.jpg *.jpeg *.webp *.PNG *.JPG *.JPEG *.WEBP") || return 0
  # keep it in the folder, so it is one click away next time
  [[ $(dirname "$(readlink -f "$f")") == "$(readlink -f "$WALLS")" ]] || cp -n "$f" "$WALLS/"
  set_wallpaper "$f"
}

wallpaper_previous() {
  [[ -f $HOME/.cache/theme/wall.prev.png ]] || {
    notify-send -a settings "Wallpaper" "No previous wallpaper"
    return 0
  }
  # set-wallpaper overwrites wall.prev.png with the current one first: hand it a copy
  cp -f "$HOME/.cache/theme/wall.prev.png" "$STATE/wall.prev.png"
  set_wallpaper "$STATE/wall.prev.png"
}

# with elephant-menus: thumbnails and a large preview (elephant/menus/wallpapers.lua, whose entries
# call wallpaper-pick below); without it a plain list
wallpaper() {
  mkdir -p "$WALLS" "$STATE"
  if [[ -e /usr/lib/elephant/menus.so ]]; then
    walker -m menus:wallpapers -t driftless-wallpapers -p "Wallpaper"
    return 0
  fi
  local items=() files=() f choice
  # the folder's images, newest first
  while IFS= read -r f; do
    files+=("$f")
    items+=("󰸉  $(basename "$f")")
  done < <(find -H "$WALLS" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) -printf '%T@ %p\n' | sort -rn | cut -d' ' -f2-)
  items+=("󰉋  Choose another image ..." "󰕌  Back to the previous wallpaper" "󰝰  Open the wallpaper folder")
  choice=$(printf '%s\n' "${items[@]}" | pick "Wallpaper") || return 0
  case $choice in
    *"Choose another"*) wallpaper_other ;;
    *previous*) wallpaper_previous ;;
    *folder) xdg-open "$WALLS" ;;
    *)
      for i in "${!items[@]}"; do [[ ${items[$i]} == "$choice" ]] && set_wallpaper "${files[$i]}"; done
      ;;
  esac
}

# nwg-displays writes monitors.lua/workspaces.lua next to the paths it gets; hyprland.lua loads them
# from ~/.local/state/hypr. Hyprland does not watch those files: reload whenever nwg-displays saves
# (also when its "keep these settings?" countdown restores the old ones).
arrange() {
  local dir=$STATE/hypr seen now
  mkdir -p "$dir"
  stamp() { stat -c %Y "$dir/monitors.lua" "$dir/workspaces.lua" 2> /dev/null | paste -sd' '; }
  seen=$(stamp)
  nwg-displays -m "$dir/monitors.conf" -w "$dir/workspaces.conf" &
  local pid=$!
  while kill -0 "$pid" 2> /dev/null; do
    sleep 0.5
    now=$(stamp)
    [[ $now != "$seen" ]] && seen=$now && hyprctl reload > /dev/null
  done
  now=$(stamp)
  [[ $now != "$seen" ]] && hyprctl reload > /dev/null
}

monitors() {
  local items=("󰍹  Arrange monitors (position, resolution, scale)")
  # laptop panel + external monitor: quick modes like Win+P (display-mode.sh)
  hyprctl -j monitors all | grep -q '"name": "eDP-' && items+=("󰍺  Display mode (extend, mirror, one screen)")
  [[ -f $STATE/hypr/monitors.lua ]] && items+=("󰑓  Reset to the automatic layout")
  local choice
  choice=$(printf '%s\n' "${items[@]}" | pick "Monitors") || return 0
  case $choice in
    *Arrange*) arrange ;;
    *"Display mode"*) "$HOME/.config/hypr/display-mode.sh" ;;
    *Reset*)
      rm -f "$STATE"/hypr/{monitors,workspaces}.{conf,lua}
      hyprctl reload > /dev/null
      notify-send -a settings "Monitors" "Automatic layout again"
      ;;
  esac
}

# bar size: automatic (compact bar on the narrow outputs, bar_layout.py) or one size on every monitor;
# the bar follows at once
size() {
  local current choice mode items=() label
  current=$("$SCRIPTS/bar_layout.py" --get-mode)
  for mode in auto spacious compact; do
    case $mode in
      auto) label="󰁨  Automatic (compact on notebook panels)" ;;
      spacious) label="󰍹  Always full size" ;;
      compact) label="󰍺  Always compact" ;;
    esac
    [[ $mode == "$current" ]] && label+="  (current)"
    items+=("$label")
  done
  choice=$(printf '%s\n' "${items[@]}" | pick "Bar size") || return 0
  case $choice in
    *Automatic*) mode=auto ;;
    *full*) mode=spacious ;;
    *compact) mode=compact ;;
    *) return 0 ;;
  esac
  [[ $mode == "$current" ]] && return 0
  "$SCRIPTS/bar_layout.py" --mode "$mode"
}

action=$1
if [[ -z $action ]]; then
  choice=$(printf '%s\n' "󰕮  Bar widgets (show, hide, move)" "󰯌  Bar size (full, compact, automatic)" "󰸉  Wallpaper and colours" "󰍹  Monitors" "󰓦  Sync with your other machines" "󰌌  Keybindings (search)" |
    pick "Settings") || exit 0
  case $choice in
    *widgets*) action=widgets ;;
    *size*) action=size ;;
    *Wallpaper*) action=wallpaper ;;
    *Monitors) action=monitors ;;
    *sync) action=sync ;;
    *Keybindings*) action=keys ;;
    *) exit 0 ;;
  esac
fi
case $action in
  widgets) exec "$SCRIPTS/widgets.py" ;;
  size) size ;;
  wallpaper) wallpaper ;;
  # Enter in the walker wallpaper menu (elephant/menus/wallpapers.lua)
  wallpaper-pick)
    mkdir -p "$WALLS" "$STATE"
    case ${2:-} in
      random) set_wallpaper --random ;;
      previous) wallpaper_previous ;;
      other) wallpaper_other ;;
      folder) xdg-open "$WALLS" ;;
      /*) set_wallpaper "$2" ;;
      *) exit 2 ;;
    esac
    ;;
  monitors) monitors ;;
  sync) exec "$SCRIPTS/sync-menu.sh" ;;
  keys) exec "$HOME/.config/hypr/keybinds.py" ;;
  *)
    echo "usage: $0 [widgets|size|wallpaper|monitors|sync|keys]" >&2
    exit 2
    ;;
esac
