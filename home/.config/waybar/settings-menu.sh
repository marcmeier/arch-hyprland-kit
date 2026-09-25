#!/usr/bin/env bash
# Desktop settings, from a click on the avatar in waybar (or "Desktop settings" in the app launcher).
# Usage: settings-menu.sh [widgets|wallpaper|monitors|sync]  (no argument: pick in walker)
# Per machine choices: widget layout and monitor layout (~/.local/state) and the wallpaper with its
# colours (~/.config/wall.png and the files rendered from it, not in the repository). None of them
# travels to your other machines.
WAYBAR=$HOME/.config/waybar
STATE=${XDG_STATE_HOME:-$HOME/.local/state}
WALLS=$HOME/Pictures/Wallpapers
pick() { walker --dmenu -p "$1"; }

# set-wallpaper restarts the bar and asks for the password of the login screen part (pkexec)
set_wallpaper() {
  notify-send -a settings "Wallpaper" "Setting $(basename "$1") and its colours ..."
  if "$HOME/.config/theme/set-wallpaper.sh" "$1" > "$STATE/set-wallpaper.log" 2>&1; then
    notify-send -a settings "Wallpaper" "Done"
  else notify-send -a settings -u critical "Wallpaper" "Failed, see $STATE/set-wallpaper.log"; fi
}

wallpaper() {
  mkdir -p "$WALLS" "$STATE"
  local items=() files=() f choice
  # the folder's images, newest first
  while IFS= read -r f; do
    files+=("$f")
    items+=("󰸉  $(basename "$f")")
  done < <(find "$WALLS" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) -printf '%T@ %p\n' | sort -rn | cut -d' ' -f2-)
  items+=("󰉋  Choose another image ..." "󰕌  Back to the previous wallpaper" "󰝰  Open the wallpaper folder")
  choice=$(printf '%s\n' "${items[@]}" | pick "Wallpaper") || return 0
  case $choice in
    *"Choose another"*)
      f=$(zenity --file-selection --title "Wallpaper" --filename "$HOME/Pictures/" \
        --file-filter "Images | *.png *.jpg *.jpeg *.webp *.PNG *.JPG *.JPEG *.WEBP") || return 0
      # keep it in the folder, so it is one click away next time
      [[ $(dirname "$f") == "$WALLS" ]] || cp -n "$f" "$WALLS/"
      set_wallpaper "$f"
      ;;
    *previous*)
      [[ -f $HOME/.cache/theme/wall.prev.png ]] || {
        notify-send -a settings "Wallpaper" "No previous wallpaper"
        return 0
      }
      # set-wallpaper overwrites wall.prev.png with the current one first: hand it a copy
      cp -f "$HOME/.cache/theme/wall.prev.png" "$STATE/wall.prev.png"
      set_wallpaper "$STATE/wall.prev.png"
      ;;
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

action=$1
if [[ -z $action ]]; then
  choice=$(printf '%s\n' "󰕮  Waybar widgets (show, hide, move)" "󰸉  Wallpaper and colours" "󰍹  Monitors" "󰓦  Sync with your other machines" |
    pick "Settings") || exit 0
  case $choice in
    *widgets*) action=widgets ;;
    *Wallpaper*) action=wallpaper ;;
    *Monitors) action=monitors ;;
    *sync) action=sync ;;
    *) exit 0 ;;
  esac
fi
case $action in
  widgets) exec "$WAYBAR/widgets.py" ;;
  wallpaper) wallpaper ;;
  monitors) monitors ;;
  sync) exec "$WAYBAR/sync-menu.sh" ;;
  *)
    echo "usage: $0 [widgets|wallpaper|monitors|sync]" >&2
    exit 2
    ;;
esac
