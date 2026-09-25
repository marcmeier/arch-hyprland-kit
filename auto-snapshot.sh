#!/usr/bin/env bash
# Kit sync, run by rebuild-snapshot.timer (after login, then hourly):
#   1. snapshot  commit this machine's changes (snapshot.sh)
#   2. pull      merge origin/main, only if every incoming commit is signed by a trusted machine
#                (lib/signing.sh). On a conflict nothing is applied or pushed ($STATE/conflict).
#   3. apply     copy the merged changes onto this machine (old files go to $STATE/backup), reload
#                what changed, install listed packages that are missing (never uninstalls)
#   4. push
#
#   --adopt  make this machine match GitHub: drop unpushed commits, copy every kit file over
#   --now    one full run whatever the mode (also triggered by the file $STATE/now)
#
# Per machine switches in $STATE (~/.local/state/rebuild), never part of the kit:
#   mode      review (default): stop before the merge while GitHub has something new, until
#             "Sync now" · auto: all steps every run · off: do nothing
#   installs  on (default) · off: install nothing from the lists
#
# Everything runs inside main(): the pull may rewrite this file while bash is reading it.
set -euo pipefail
export LC_ALL=C # same sort order as snapshot.sh, whatever locale the session has

main() {
  cd "$(dirname "$(readlink -f "$0")")"
  local ADOPT=0 NOW=0 OFFLINE=0 incoming sha
  case ${1:-} in --adopt) ADOPT=1 ;; --now) NOW=1 ;; esac
  STATE="${XDG_STATE_HOME:-$HOME/.local/state}/rebuild"
  mkdir -p "$STATE"
  exec 9> "$STATE/lock"
  flock -n 9 || {
    echo "rebuild sync: already running"
    exit 0
  }
  RESULT=failed APPLIED=0 BACKUP=""
  trap write_status EXIT
  [[ -e $STATE/now ]] && {
    NOW=1
    rm -f "$STATE/now"
  }
  MODE=$(cat "$STATE/mode" 2> /dev/null || echo review)
  pkill -RTMIN+11 -x waybar 2> /dev/null || true # the pill shows the run
  if [[ $MODE == off ]] && ((!NOW && !ADOPT)); then
    RESULT=paused
    echo "rebuild sync: switched off on this machine (waybar sync pill)"
    exit 0
  fi
  HOST=$(< /etc/hostname)
  # a fresh install has no git identity, and without one no commit works: name the machine
  git config user.name > /dev/null || git config user.name "rebuild-kit $HOST"
  git config user.email > /dev/null || git config user.email "rebuild-kit@$HOST.invalid"
  source ./kit.conf
  source ./lib/lists.sh # MACHINE_LOCAL

  local old
  if ((ADOPT)); then
    git fetch -q origin main
    verify_incoming
    git reset -q --hard origin/main
    rm -f "$STATE/conflict" "$STATE/conflict.notified"
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
      if [[ $MODE == review ]] && ((incoming && !NOW)); then
        RESULT=held
        # one notification per new GitHub state, not every hour
        sha=$(git rev-parse origin/main)
        if [[ $sha != "$(cat "$STATE/held.notified" 2> /dev/null)" ]]; then
          notify normal "$incoming change(s) on GitHub wait for your review (sync pill in the bar)"
          echo "$sha" > "$STATE/held.notified"
        fi
        exit 0
      fi
      if ! git merge -q --no-edit origin/main; then
        git diff --name-only --diff-filter=U > "$STATE/conflict"
        git merge --abort 2> /dev/null || true
        RESULT=conflict
        sha=$(git rev-parse origin/main)
        if [[ $sha != "$(cat "$STATE/conflict.notified" 2> /dev/null)" ]]; then
          notify critical "This machine and GitHub changed the same lines in: $(paste -sd' ' "$STATE/conflict"). Nothing taken over. Merge by hand: cd $PWD && git merge origin/main"
          echo "$sha" > "$STATE/conflict.notified"
        fi
        exit 1
      fi
      rm -f "$STATE/conflict" "$STATE/conflict.notified"
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
  ((OFFLINE)) && RESULT=offline
  if git rev-parse -q --verify origin/main > /dev/null && (($(git rev-list --count origin/main..HEAD))); then
    if git push -q origin main; then
      echo "rebuild sync: pushed to GitHub"
    else
      RESULT="push failed"
      echo "rebuild sync: git push failed, will retry next run" >&2
    fi
  fi
  refresh_zip
  if ((APPLIED)); then
    if [[ -d $BACKUP ]]; then
      notify normal "Taken over from GitHub: $APPLIED change(s). Replaced files are kept in $BACKUP"
    else notify normal "Taken over from GitHub: $APPLIED change(s)"; fi
  fi
  echo "rebuild sync: done $(date -Is)"
}

# EXIT trap: outcome of this run for the waybar sync pill (sync.py)
# shellcheck disable=SC2317 # only called by the trap
write_status() {
  local rc=$?
  ((rc)) && [[ $RESULT == ok || $RESULT == offline ]] && RESULT=failed
  printf 'time=%s\nresult=%s\napplied=%s\n' "$(date +%s)" "$RESULT" "$APPLIED" > "$STATE/status"
  pkill -RTMIN+11 -x waybar 2> /dev/null || true
}

# verify_incoming: end the run while GitHub has a commit no trusted machine signed. A key in
# signers/ that is not trusted yet is a new machine asking to join ($STATE/untrusted, sync menu).
verify_incoming() {
  local bad sha joining
  [[ -e $STATE/allowed_signers ]] || {
    rm -f "$STATE/untrusted"
    return 0
  } # not set up here yet
  bad=$(lib/signing.sh check HEAD..origin/main)
  [[ -n $bad ]] || {
    rm -f "$STATE/untrusted"
    return 0
  }
  echo "$bad" > "$STATE/untrusted"
  joining=$(awk '$2 == "U" && $4 != "-" { print $4 }' <<< "$bad" | sort -u | tr '\n' ' ')
  if [[ -n $joining && -z $(awk '$2 != "U" || $4 == "-"' <<< "$bad") ]]; then
    RESULT=joining
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

notify() { # notify URGENCY TEXT
  echo "rebuild sync: $2"
  notify-send -u "$1" -a rebuild "Rebuild sync" "$2" 2> /dev/null || true
}

# kit path -> live path (empty: not applied automatically, e.g. /etc needs root)
live_path() {
  case $1 in
    files/home/*) echo "$HOME/${1#files/home/}" ;;
    files/CLAUDE.md) [[ -n ${KIT_NOTES_REL:-} ]] && echo "$HOME/$KIT_NOTES_REL/CLAUDE.md" ;;
    files/docs/*) [[ -n ${KIT_NOTES_REL:-} ]] && echo "$HOME/$KIT_NOTES_REL/docs/${1#files/docs/}" ;;
    files/dconf.ini) echo dconf ;;
  esac
}

# apply_kit OLD: copy the kit files changed between OLD and HEAD onto this machine, delete the
# deleted ones. Without OLD (--adopt): every kit file that differs. Replaced files go to $BACKUP.
apply_kit() {
  local status path live
  BACKUP=$STATE/backup/$(date +%Y-%m-%dT%H%M%S)
  while read -r status path; do
    live=$(live_path "$path")
    [[ -n $live ]] || continue
    # this machine's wallpaper and theme stay (lib/lists.sh); new templates are rendered below
    machine_local "$path" && continue
    if [[ $live == dconf ]]; then
      if [[ $status != D ]]; then
        mkdir -p "$BACKUP"
        dconf dump / > "$BACKUP/dconf.ini"
        dconf load / < "$path" && APPLIED=$((APPLIED + 1))
      fi
      continue
    fi
    if [[ $status == D ]]; then
      [[ -e $live ]] || continue
      backup "$live"
      rm -f "$live"
      APPLIED=$((APPLIED + 1))
    elif ! cmp -s "$path" "$live" 2> /dev/null || [[ $(stat -c %a "$path") != "$(stat -c %a "$live")" ]]; then
      [[ -e $live ]] && backup "$live"
      mkdir -p "$(dirname "$live")"
      cp -a "$path" "$live"
      # this machine has the file now: from here on, deleting it here is a deletion (lib/lists.sh)
      echo "$path" >> "$STATE/files.base"
      APPLIED=$((APPLIED + 1))
    else
      continue
    fi
    case $path in
      files/home/.config/hypr/*) RELOAD+=(hypr) ;;
      # new templates or renderer: render them with this machine's own colours (reload_changed)
      files/home/.config/theme/templates/* | files/home/.config/theme/apply.py) RELOAD+=(theme hypr mako waybar) ;;
      # the renderer keeps running: restart it, or it goes on with the old code
      files/home/.config/waybar/density-watch.py | files/home/.config/waybar/bar_layout.py) RELOAD+=(density waybar) ;;
      files/home/.config/waybar/* | files/home/.config/theme/*) RELOAD+=(waybar) ;;
      files/home/.config/mako/*) RELOAD+=(mako) ;;
      files/home/.config/systemd/user/*) RELOAD+=(systemd) ;;
    esac
  done < <(
    if [[ -n $1 ]]; then
      git diff --name-status --no-renames "$1" HEAD -- files
    else git ls-files files | sed 's/^/M\t/'; fi
  )
  prune_backups
}

# backup LIVE: keep a copy of a live file before the sync replaces or deletes it, under its path
# relative to the home ($BACKUP/.config/hypr/hyprland.lua)
backup() {
  local dest=$BACKUP/${1#"$HOME"/}
  mkdir -p "$(dirname "$dest")"
  cp -a "$1" "$dest"
}

# only the last 10 runs that replaced something keep their backup
prune_backups() {
  local old
  [[ -d $STATE/backup ]] || return 0
  find "$STATE/backup" -mindepth 1 -maxdepth 1 -type d -print0 | sort -rz | tail -zn +11 |
    while IFS= read -r -d '' old; do rm -rf "$old"; done
}

# without LC_ALL=C (waybar modules would print icons as invalid JSON escapes) and without fd 9
# (waybar would inherit the sync's lock and hold it for as long as it runs)
detach() {
  systemd-run --user --scope --quiet --collect env -u LC_ALL setsid -f "$@" > /dev/null 2>&1 < /dev/null 9>&- ||
    env -u LC_ALL setsid -f "$@" > /dev/null 2>&1 < /dev/null 9>&- || true
}

reload_changed() {
  local r
  # first, so the reloads below pick up the freshly rendered files
  if printf '%s\n' "${RELOAD[@]}" | grep -qx theme; then
    python3 "$HOME/.config/theme/apply.py" --current > /dev/null || echo "rebuild sync: theme not rendered" >&2
    pkill -USR2 -x ghostty 2> /dev/null || true
  fi
  for r in $(printf '%s\n' "${RELOAD[@]}" | sort -u); do
    case $r in
      systemd) systemctl --user daemon-reload ;;
      hypr) hyprctl reload > /dev/null 2>&1 || true ;;
      mako) makoctl reload 2> /dev/null || true ;;
      # own scope: systemd kills what is left in the service's cgroup when the oneshot ends
      waybar)
        if printf '%s\n' "${RELOAD[@]}" | grep -qx density; then
          kill "$(cat "$HOME/.cache/waybar/density-watch.pid" 2> /dev/null)" 2> /dev/null || true
          sleep 0.3
        fi
        pgrep -f 'python3? .*waybar/density-watch.py' > /dev/null ||
          detach "$HOME/.config/waybar/density-watch.py"
        detach "$HOME/.config/waybar/launch.sh"
        ;;
    esac
  done
}

# install_missing: listed packages and extensions this machine lacks. Repo packages go through
# "pkexec rebuild-install" (password dialog, once per new set or on "Sync now"). AUR packages are
# never built here; they wait in $STATE/install-pending for "Install missing packages" (yay).
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
  if ((${#miss_repo[@]})); then
    if [[ ! -x /usr/local/bin/rebuild-install || ! -e /usr/share/polkit-1/actions/org.rebuild.install.policy ]]; then
      msg="rebuild-install is not set up here, so listed packages cannot be installed (see README)"
    elif ((NOW)) || [[ "${miss_repo[*]}" != "$(cat "$STATE/install-asked" 2> /dev/null)" ]]; then
      echo "${miss_repo[*]}" > "$STATE/install-asked"
      echo "rebuild sync: asking to install ${miss_repo[*]}"
      rc=0
      timeout 300 pkexec /usr/local/bin/rebuild-install "${miss_repo[@]}" || rc=$?
      # 126: dialog cancelled, 127: no polkit agent (no desktop session), 124: nobody answered
      if ((rc == 124 || rc == 126 || rc == 127)); then
        echo "rebuild sync: install not confirmed (exit $rc)"
      elif ((rc)); then
        msg="Could not install: ${miss_repo[*]} (maybe update the system first: sudo pacman -Syu)"
      fi
      have=$(pacman -Qq | sort)
      APPLIED=$((APPLIED + ${#miss_repo[@]}))
      mapfile -t miss_repo < <(comm -23 <(sort -u packages/pacman.txt) <(echo "$have"))
      APPLIED=$((APPLIED - ${#miss_repo[@]}))
    fi
  fi
  {
    for x in "${miss_repo[@]}"; do echo "repo $x"; done
    for x in "${miss_aur[@]}"; do echo "aur $x"; done
  } > "$STATE/install-pending"
  ((${#miss_repo[@]} + ${#miss_aur[@]})) && [[ -z $msg ]] &&
    urgency=normal msg="$((${#miss_repo[@]} + ${#miss_aur[@]})) listed package(s) wait for install: ${miss_repo[*]} ${miss_aur[*]} (sync menu: Install missing packages)"
  # notify only when the message changes, not every hour
  if [[ $msg != "$(cat "$STATE/install-notified" 2> /dev/null)" ]]; then
    [[ -n $msg ]] && notify "$urgency" "$msg"
    echo "$msg" > "$STATE/install-notified"
  fi

  if command -v code > /dev/null && [[ -s packages/vscode-extensions.txt ]]; then
    mapfile -t miss_code < <(comm -23 <(sort -uf packages/vscode-extensions.txt | tr '[:upper:]' '[:lower:]' | sort -u) \
      <(code --list-extensions 2> /dev/null | tr '[:upper:]' '[:lower:]' | sort -u))
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

main "$@"
exit
