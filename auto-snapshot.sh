#!/usr/bin/env bash
# Timer entry point (rebuild-snapshot.timer: a few minutes after login, then hourly). Keeps this
# machine and GitHub in step, in this order:
#   1. snapshot: record this machine's changes in the kit (snapshot.sh) and commit them
#   2. pull:     merge origin/main; where both sides changed the same lines, GitHub wins
#   3. apply:    copy what the merge brought in onto this machine (dotfiles, dconf, Claude notes),
#                reload Hyprland/Waybar/mako, install listed packages and VS Code extensions that
#                are missing here (never uninstalls anything)
#   4. push, and refresh the zip copy (KIT_ZIP in kit.conf) if anything changed
#
#   --adopt  make this machine match GitHub: drop unpushed local commits and copy every kit file
#            over the live one. For a machine that fell behind, before its first regular run.
#   --now    one full run whatever the mode says (also: a file $STATE/now, set by the waybar menu)
#
# Per machine switches in $STATE (~/.local/state/rebuild), set from the waybar sync pill
# (~/.config/waybar/sync-menu.sh); they never travel with the kit, so GitHub cannot flip them:
#   mode      auto (default): all four steps · review: record and fetch, but while GitHub has
#             something new, stop before the merge (nothing applied, nothing pushed) until
#             "Sync now" · off: the timer does nothing at all
#   installs  on (default) · off: never install packages or VS Code extensions from the lists
# Every run leaves its outcome in $STATE/status and refreshes the waybar pill (signal 11).
#
# Everything runs inside main(): the pull may rewrite this very file while bash is reading it.
set -euo pipefail
export LC_ALL=C   # same sort order as snapshot.sh, whatever locale the session has

main() {
  cd "$(dirname "$(readlink -f "$0")")"
  local H=$HOME ADOPT=0 NOW=0 OFFLINE=0 incoming sha
  case ${1:-} in --adopt) ADOPT=1 ;; --now) NOW=1 ;; esac
  STATE="${XDG_STATE_HOME:-$H/.local/state}/rebuild"
  mkdir -p "$STATE"
  exec 9> "$STATE/lock"
  flock -n 9 || { echo "rebuild sync: already running"; exit 0; }
  RESULT=failed APPLIED=0
  trap write_status EXIT
  [[ -e $STATE/now ]] && { NOW=1; rm -f "$STATE/now"; }
  MODE=$(cat "$STATE/mode" 2> /dev/null || echo auto)
  pkill -RTMIN+11 -x waybar 2> /dev/null || true   # the pill shows the run
  if [[ $MODE == off ]] && (( ! NOW && ! ADOPT )); then
    RESULT=paused; echo "rebuild sync: switched off on this machine (waybar sync pill)"; exit 0
  fi
  HOST=$(< /etc/hostname)
  source ./kit.conf

  local old
  if (( ADOPT )); then
    git fetch -q origin main
    git reset -q --hard origin/main
    old=""
  else
    # 1. snapshot
    ./snapshot.sh > /dev/null
    git add -A
    git diff --cached --quiet || git commit -q -m "Automatic snapshot $HOST $(date -Is)"
    old=$(git rev-parse HEAD)

    # 2. pull (offline: skip straight to installing what is missing)
    if git fetch -q origin main; then
      incoming=$(git rev-list --count HEAD..origin/main)
      if [[ $MODE == review ]] && (( incoming && ! NOW )); then
        RESULT=held
        # one notification per new GitHub state, not every hour
        sha=$(git rev-parse origin/main)
        if [[ $sha != "$(cat "$STATE/held.notified" 2> /dev/null)" ]]; then
          notify normal "$incoming change(s) on GitHub wait for your review (sync pill in the bar)"
          echo "$sha" > "$STATE/held.notified"
        fi
        exit 0
      fi
      if ! git merge -q --no-edit -X theirs origin/main; then
        git merge --abort 2> /dev/null || true
        RESULT=conflict
        notify critical "Could not take over the GitHub state (merge conflict). Please resolve it by hand: $PWD"
        exit 1
      fi
    else
      OFFLINE=1
      echo "rebuild sync: GitHub not reachable, working offline"
    fi
  fi

  # 3. apply
  RELOAD=()
  apply_kit "$old"
  install_missing
  reload_changed

  # 4. push + zip
  RESULT=ok
  (( OFFLINE )) && RESULT=offline
  if git rev-parse -q --verify origin/main > /dev/null && (( $(git rev-list --count origin/main..HEAD) )); then
    if git push -q origin main; then echo "rebuild sync: pushed to GitHub"
    else RESULT="push failed"; echo "rebuild sync: git push failed, will retry next run" >&2; fi
  fi
  refresh_zip
  (( APPLIED )) && notify normal "Taken over from GitHub: $APPLIED change(s)"
  echo "rebuild sync: done $(date -Is)"
}

# EXIT trap: outcome of this run for the waybar sync pill (sync.py)
write_status() {
  local rc=$?
  (( rc )) && [[ $RESULT == ok || $RESULT == offline ]] && RESULT=failed
  printf 'time=%s\nresult=%s\napplied=%s\n' "$(date +%s)" "$RESULT" "$APPLIED" > "$STATE/status"
  pkill -RTMIN+11 -x waybar 2> /dev/null || true
}

notify() {  # notify URGENCY TEXT
  echo "rebuild sync: $2"
  notify-send -u "$1" -a rebuild "Rebuild sync" "$2" 2> /dev/null || true
}

# kit path -> live path (empty: not applied automatically, e.g. /etc needs root)
live_path() {
  case $1 in
    files/home/*)    echo "$HOME/${1#files/home/}" ;;
    files/CLAUDE.md) [[ -n ${KIT_NOTES_REL:-} ]] && echo "$HOME/$KIT_NOTES_REL/CLAUDE.md" ;;
    files/docs/*)    [[ -n ${KIT_NOTES_REL:-} ]] && echo "$HOME/$KIT_NOTES_REL/docs/${1#files/docs/}" ;;
    files/dconf.ini) echo dconf ;;
  esac
}

# apply_kit OLD: copy every kit file that changed between OLD and HEAD onto this machine and delete
# the ones that were deleted. Without OLD (--adopt): every kit file that differs from the live one.
# Safe to overwrite: step 1 already committed this machine's own changes, so the merged kit has them.
apply_kit() {
  local status path live
  while read -r status path; do
    live=$(live_path "$path")
    [[ -n $live ]] || continue
    if [[ $live == dconf ]]; then
      [[ $status == D ]] || { dconf load / < "$path" && APPLIED=$((APPLIED + 1)); }
      continue
    fi
    if [[ $status == D ]]; then
      [[ -e $live ]] && rm -f "$live" && APPLIED=$((APPLIED + 1))
    elif ! cmp -s "$path" "$live" 2> /dev/null || [[ $(stat -c %a "$path") != "$(stat -c %a "$live")" ]]; then
      mkdir -p "$(dirname "$live")"
      cp -a "$path" "$live"
      APPLIED=$((APPLIED + 1))
    else
      continue
    fi
    case $path in
      files/home/.config/hypr/*)                               RELOAD+=(hypr) ;;
      files/home/.config/waybar/*|files/home/.config/theme/*)  RELOAD+=(waybar) ;;
      files/home/.config/mako/*)                               RELOAD+=(mako) ;;
      files/home/.config/systemd/user/*)                       RELOAD+=(systemd) ;;
    esac
  done < <(
    if [[ -n $1 ]]; then git diff --name-status --no-renames "$1" HEAD -- files
    else git ls-files files | sed 's/^/M\t/'; fi
  )
}

# Without our LC_ALL=C: bash modules like notifications.sh then print $'\U...' icons as literal
# escapes, which is invalid JSON for waybar. Without fd 9 (our lock): waybar would inherit it and
# hold the lock for as long as it runs, so every later sync ends with "already running".
detach() {
  systemd-run --user --scope --quiet --collect env -u LC_ALL setsid -f "$@" > /dev/null 2>&1 < /dev/null 9>&- \
    || env -u LC_ALL setsid -f "$@" > /dev/null 2>&1 < /dev/null 9>&- || true
}

reload_changed() {
  local r
  for r in $(printf '%s\n' "${RELOAD[@]}" | sort -u); do
    case $r in
      systemd) systemctl --user daemon-reload ;;
      hypr)    hyprctl reload > /dev/null 2>&1 || true ;;
      mako)    makoctl reload 2> /dev/null || true ;;
      # Own scope: under rebuild-snapshot.service, systemd kills everything left in the service's
      # cgroup when the oneshot ends (setsid does not leave the cgroup) - that took waybar down.
      waybar)
        pgrep -f 'python3? .*waybar/density-watch.py' > /dev/null \
          || detach "$HOME/.config/waybar/density-watch.py"
        detach "$HOME/.config/waybar/launch.sh" ;;
    esac
  done
}

# install_missing: listed packages / extensions this machine does not have yet. Packages need the
# sudo rule from lib/sudoers-rebuild-sync (pacman without password); without it only a notification.
install_missing() {
  local have miss_repo miss_aur miss_code failed=() msg x
  if [[ $(cat "$STATE/installs" 2> /dev/null) == off ]]; then
    echo "rebuild sync: installs switched off on this machine, not installing anything"
    return 0
  fi
  have=$(pacman -Qq | sort)
  mapfile -t miss_repo < <(comm -23 <(sort -u packages/pacman.txt) <(echo "$have"))
  mapfile -t miss_aur < <(comm -23 <(sort -u packages/aur.txt) <(echo "$have"))
  if (( ${#miss_repo[@]} + ${#miss_aur[@]} )); then
    if ! sudo -n -l /usr/bin/pacman > /dev/null 2>&1; then
      failed=("${miss_repo[@]}" "${miss_aur[@]}")
      msg="${#failed[@]} listed package(s) missing, but the sudo rule for pacman is not set up (see README)"
    else
      if (( ${#miss_repo[@]} )) && ! sudo -n pacman -S --needed --noconfirm "${miss_repo[@]}"; then
        for x in "${miss_repo[@]}"; do sudo -n pacman -S --needed --noconfirm "$x" || failed+=("$x"); done
      fi
      for x in "${miss_aur[@]}"; do
        yay -S --needed --noconfirm --removemake --answerclean None --answerdiff None --answeredit None "$x" || failed+=("$x")
      done
      APPLIED=$((APPLIED + ${#miss_repo[@]} + ${#miss_aur[@]} - ${#failed[@]}))
      msg="Could not install: ${failed[*]} (maybe update the system first: sudo pacman -Syu)"
    fi
  fi
  # notify only when the set of failures changes, not every hour
  if [[ "${failed[*]}" != "$(cat "$STATE/install-failed" 2> /dev/null)" ]]; then
    (( ${#failed[@]} )) && notify critical "$msg"
    echo "${failed[*]}" > "$STATE/install-failed"
  fi

  if command -v code > /dev/null && [[ -s packages/vscode-extensions.txt ]]; then
    mapfile -t miss_code < <(comm -23 <(sort -uf packages/vscode-extensions.txt | tr 'A-Z' 'a-z' | sort -u) \
                                      <(code --list-extensions 2> /dev/null | tr 'A-Z' 'a-z' | sort -u))
    for x in "${miss_code[@]}"; do
      code --install-extension "$x" > /dev/null 2>&1 && APPLIED=$((APPLIED + 1)) || echo "rebuild sync: VS Code extension $x failed" >&2
    done
  fi
}

# the zip copy (KIT_ZIP in kit.conf) only when the kit changed since the last zip
refresh_zip() {
  local zip=${KIT_ZIP:-} fp tmp
  [[ -n $zip ]] || return 0
  fp=$(git rev-parse HEAD)
  [[ -f $zip && $(cat "$STATE/zip.head" 2> /dev/null) == "$fp" ]] && return 0
  mkdir -p "$(dirname "$zip")"
  tmp=$(mktemp -u "$zip.XXXXXX.zip")
  (cd .. && zip -qr "$tmp" rebuild -x 'rebuild/.git/*')
  mv -f "$tmp" "$zip"
  echo "$fp" > "$STATE/zip.head"
  echo "rebuild sync: zip refreshed"
}

main "$@"; exit
