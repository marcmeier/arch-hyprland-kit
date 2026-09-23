#!/usr/bin/env bash
# Timer entry point (rebuild-snapshot.timer: a few minutes after login, then hourly). Keeps this
# machine and GitHub in step, in this order:
#   1. snapshot: record this machine's changes in the kit (snapshot.sh) and commit them
#   2. pull:     merge origin/main; where both sides changed the same lines, GitHub wins. Once
#                lib/signing.sh set this machine up, only when every incoming commit is signed by
#                one of your machines (verify_incoming); otherwise nothing is taken over
#   3. apply:    copy what the merge brought in onto this machine (dotfiles, dconf, Claude notes),
#                reload Hyprland/Waybar/mako, install listed packages (after the password, see
#                install_missing) and VS Code extensions that are missing here (never uninstalls)
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
# install-pending lists the packages that wait (not confirmed, or AUR), for the pill and its menu.
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
    verify_incoming
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
      verify_incoming
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

# verify_incoming: stop the run (nothing merged, applied or pushed) while GitHub has a commit that no
# trusted machine signed (lib/signing.sh). A commit from a machine that published its key in
# signers/ but is not trusted here yet is a join request: the sync menu offers to trust it.
# $STATE/untrusted lists what holds the sync back, for the pill and its menu.
verify_incoming() {
  local bad sha joining
  [[ -e $STATE/allowed_signers ]] || { rm -f "$STATE/untrusted"; return 0; }   # not set up here yet
  bad=$(lib/signing.sh check HEAD..origin/main)
  [[ -n $bad ]] || { rm -f "$STATE/untrusted"; return 0; }
  echo "$bad" > "$STATE/untrusted"
  joining=$(awk '$2 == "U" && $4 != "-" { print $4 }' <<< "$bad" | sort -u | tr '\n' ' ')
  if [[ -n $joining && -z $(awk '$2 != "U" || $4 == "-"' <<< "$bad") ]]; then RESULT=joining
  else RESULT=untrusted; fi
  # one notification per GitHub state, not every hour
  sha=$(git rev-parse origin/main)
  if [[ $sha != "$(cat "$STATE/untrusted.notified" 2> /dev/null)" ]]; then
    if [[ $RESULT == joining ]]; then
      notify normal "New machine ${joining% }: nothing taken over until you trust it (sync menu: Trust new machine)"
    else
      notify critical "$(wc -l <<< "$bad") commit(s) on GitHub are not signed by any of your machines. Nothing taken over. Check them: sync menu, Review incoming changes"
    fi
    echo "$sha" > "$STATE/untrusted.notified"
  fi
  exit 0
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

# install_missing: listed packages / extensions this machine does not have yet. Nothing here runs as
# root without the password: official repo packages go through "pkexec rebuild-install", whose polkit
# dialog names them and asks for it. The dialog comes once per new set of missing packages (and on
# "Sync now"); cancelled or unanswered within 5 minutes, they wait in the sync pill. AUR packages are
# never built unattended (their PKGBUILDs deserve a look): they wait for "Install missing packages"
# in the sync menu, a terminal with yay. $STATE/install-pending lists what waits, for pill and menu.
install_missing() {
  local have miss_repo miss_aur miss_code msg="" urgency=critical rc x
  if [[ $(cat "$STATE/installs" 2> /dev/null) == off ]]; then
    echo "rebuild sync: installs switched off on this machine, not installing anything"
    rm -f "$STATE/install-pending"
    return 0
  fi
  have=$(pacman -Qq | sort)
  mapfile -t miss_repo < <(comm -23 <(sort -u packages/pacman.txt) <(echo "$have"))
  mapfile -t miss_aur < <(comm -23 <(sort -u packages/aur.txt) <(echo "$have"))
  if (( ${#miss_repo[@]} )); then
    if [[ ! -x /usr/local/bin/rebuild-install || ! -e /usr/share/polkit-1/actions/org.rebuild.install.policy ]]; then
      msg="rebuild-install is not set up here, so listed packages cannot be installed (see README)"
    elif (( NOW )) || [[ "${miss_repo[*]}" != "$(cat "$STATE/install-asked" 2> /dev/null)" ]]; then
      echo "${miss_repo[*]}" > "$STATE/install-asked"
      echo "rebuild sync: asking to install ${miss_repo[*]}"
      rc=0; timeout 300 pkexec /usr/local/bin/rebuild-install "${miss_repo[@]}" || rc=$?
      # 126: dialog cancelled, 127: no polkit agent (no desktop session), 124: nobody answered
      if (( rc == 124 || rc == 126 || rc == 127 )); then
        echo "rebuild sync: install not confirmed (exit $rc)"
      elif (( rc )); then
        msg="Could not install: ${miss_repo[*]} (maybe update the system first: sudo pacman -Syu)"
      fi
      have=$(pacman -Qq | sort)
      APPLIED=$((APPLIED + ${#miss_repo[@]}))
      mapfile -t miss_repo < <(comm -23 <(sort -u packages/pacman.txt) <(echo "$have"))
      APPLIED=$((APPLIED - ${#miss_repo[@]}))
    fi
  fi
  { for x in "${miss_repo[@]}"; do echo "repo $x"; done
    for x in "${miss_aur[@]}"; do echo "aur $x"; done; } > "$STATE/install-pending"
  (( ${#miss_repo[@]} + ${#miss_aur[@]} )) && [[ -z $msg ]] \
    && urgency=normal msg="$(( ${#miss_repo[@]} + ${#miss_aur[@]} )) listed package(s) wait for install: ${miss_repo[*]} ${miss_aur[*]} (sync menu: Install missing packages)"
  # notify only when the message changes, not every hour
  if [[ $msg != "$(cat "$STATE/install-notified" 2> /dev/null)" ]]; then
    [[ -n $msg ]] && notify "$urgency" "$msg"
    echo "$msg" > "$STATE/install-notified"
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
