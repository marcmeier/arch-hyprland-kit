#!/usr/bin/env bash
# Control the rebuild kit sync of THIS machine (auto-snapshot.sh), from the waybar sync pill.
# Usage: sync-menu.sh [now|toggle|auto|review|off|installs|check|diff|log|github]  (no argument: pick in walker)
# The switches live in ~/.local/state/rebuild (mode, installs) and never travel with the kit.
REPO=$HOME/rebuild
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/rebuild
mode=$(cat "$STATE/mode" 2>/dev/null || echo auto)
installs=$(cat "$STATE/installs" 2>/dev/null || echo on)
refresh() { pkill -RTMIN+11 -x waybar; }
set_mode() { mkdir -p "$STATE"; echo "$1" > "$STATE/mode"; refresh; notify-send -a rebuild "Rebuild sync" "$2"; }

action=$1
if [ -z "$action" ]; then
    incoming=$(git -C "$REPO" rev-list --count HEAD..origin/main 2>/dev/null || echo 0)
    mark() { [ "$mode" = "$1" ] && echo "●" || echo "○"; }
    items=("󰓦  Sync now$( ((incoming)) && echo " (take over $incoming incoming)")")
    ((incoming)) && items+=("󰈈  Review incoming changes")
    items+=("$(mark auto)  Mode: automatic"
            "$(mark review)  Mode: review GitHub changes first"
            "$(mark off)  Mode: off"
            "󰏔  Install packages from the lists: $installs → $([ "$installs" = on ] && echo off || echo on)"
            "󰑓  Check GitHub now"
            "󰈙  Show sync log"
            "  Open commits on GitHub")
    choice=$(printf '%s\n' "${items[@]}" | walker --dmenu -p "Kit sync ($mode)") || exit 0
    case $choice in
        *"Sync now"*)      action=now ;;
        *Review*)          action=diff ;;
        *"Mode: auto"*)    action=auto ;;
        *"Mode: review"*)  action=review ;;
        *"Mode: off"*)     action=off ;;
        *"Install pack"*)  action=installs ;;
        *Check*)           action=check ;;
        *log*)             action=log ;;
        *GitHub)           action=github ;;
        *) exit 0 ;;
    esac
fi

case $action in
    # the service consumes $STATE/now: one full run, whatever the mode (review: takes over what waits)
    now)    touch "$STATE/now"; systemctl --user start --no-block rebuild-snapshot.service; refresh ;;
    toggle) if [ "$mode" = off ]; then set_mode auto "Sync resumed (automatic)"
            else set_mode off "Sync switched off on this machine"; fi ;;
    auto)   set_mode auto "Sync mode: automatic" ;;
    review) set_mode review "Sync mode: review first. GitHub changes wait for \"Sync now\"" ;;
    off)    set_mode off "Sync switched off on this machine" ;;
    installs)
        new=$([ "$installs" = on ] && echo off || echo on)
        echo "$new" > "$STATE/installs"; refresh
        notify-send -a rebuild "Rebuild sync" "Installing packages from the lists: $new" ;;
    # fetch only (nothing applied), under the sync's lock so it never races a running sync
    check)
        if flock -n "$STATE/lock" timeout 30 git -C "$REPO" fetch -q origin main; then
            n=$(git -C "$REPO" rev-list --count HEAD..origin/main)
            notify-send -a rebuild "Rebuild sync" "GitHub checked: $n incoming change(s)"
        else notify-send -a rebuild "Rebuild sync" "Check failed (sync running or GitHub not reachable)"; fi
        refresh ;;
    diff)   ghostty -e bash -c "cd '$REPO' && git -c color.ui=always log --reverse --stat -p HEAD..origin/main | less -R" ;;
    log)    ghostty -e bash -c "journalctl --user -u rebuild-snapshot.service -n 200 --no-pager | less -R +G" ;;
    github) url=$(git -C "$REPO" remote get-url origin | sed -E 's#^git@github.com:#https://github.com/#; s#\.git$##')
            xdg-open "$url/commits/main" ;;
    *) echo "usage: $0 [now|toggle|auto|review|off|installs|check|diff|log|github]" >&2; exit 2 ;;
esac
