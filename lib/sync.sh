# shellcheck shell=bash
# driftless sync: keep this machine and GitHub in step. Run by driftless-sync.timer (after login,
# then hourly) and from the sync pill.
#
#   1. commit   edits to files the repository already tracks (the home is linked, so an edit in
#               ~/.config is an edit here). New files are never picked up on their own, and a staged
#               change that looks like a secret stops the run before anything is committed.
#   2. fetch    and check that every incoming commit is signed by a trusted machine (lib/signing.sh)
#   3. update   review mode (default): stop while GitHub has something new, until "sync --now".
#               Otherwise rebase this machine's commits onto GitHub's. A conflict aborts the
#               rebase: nothing changes, the pill names the files.
#   4. apply    links, reloads and packages for what the update changed. The files themselves need
#               no copying: the links already point at the new versions.
#   5. push
#
# Per machine switches, never in the repository ($STATE): mode (review|auto|off), installs (on|off).
# The old versions of every file are in git; nothing needs a backup folder.

# what the sync commits by itself: content. The code (driftless, lib/, install/, system/, tests/)
# changes in a development clone and arrives through GitHub like everything else.
AUTO_PATHS=(home personal hosts packages manifest dconf.ini signers)

# added lines in the staged diff that look like credentials
SECRET_RE='(ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-ant-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(password|passwd|secret|token)[[:space:]]*[=:][[:space:]]*["'"'"']?[^[:space:]"'"'"'$]{8,})'

git_() { git -C "$DRIFTLESS" "$@"; }

write_status() {
  local rc=$?
  ((rc)) && [[ $RESULT == ok || $RESULT == offline ]] && RESULT=failed
  printf 'time=%s\nresult=%s\napplied=%s\n' "$(date +%s)" "$RESULT" "$APPLIED" > "$STATE/status"
  poke_bar
}

# notify_once KEY URGENCY TEXT: a notification only when TEXT differs from the last one for KEY
notify_once() {
  [[ $3 == "$(cat "$STATE/$1.notified" 2> /dev/null)" ]] && {
    echo "driftless: $3"
    return 0
  }
  notify "$2" "$3"
  echo "$3" > "$STATE/$1.notified"
}

# commit_local: this machine's edits, as one signed commit "<host>: <what changed>"
commit_local() {
  local files hits what
  heal_all
  # only paths that exist: git refuses the whole add for one that does not (no personal/ in a template)
  local p paths=()
  for p in "${AUTO_PATHS[@]}"; do [[ -e $DRIFTLESS/$p ]] && paths+=("$p"); done
  git_ add -u -- "${paths[@]}"
  git_ diff --cached --quiet && return 0
  hits=$(git_ diff --cached -U0 --no-color | grep '^+[^+]' | grep -Eio "$SECRET_RE" | head -3 || true)
  if [[ -n $hits ]]; then
    git_ reset -q
    RESULT=secret
    notify_once secret critical "A change looks like it contains a secret, nothing committed. Check: git -C $DRIFTLESS diff"
    exit 1
  fi
  rm -f "$STATE/secret.notified"
  mapfile -t files < <(git_ diff --cached --name-only | sed -E 's#^home/(\.config/)?##; s#^personal/(home/(\.config/)?)?#personal: #')
  what=$(printf '%s\n' "${files[@]:0:3}" | paste -sd, | sed 's/,/, /g')
  ((${#files[@]} > 3)) && what+=" and $((${#files[@]} - 3)) more"
  git_ commit -q -m "$HOST: $what" -m "Driftless-Host: $HOST"
}

# verify_incoming: end the run while GitHub has a commit no trusted machine signed. A key in signers/
# that is not trusted yet is a new machine asking to join ($STATE/untrusted, sync menu).
verify_incoming() {
  local bad joining
  [[ -e $ALLOWED ]] || {
    rm -f "$STATE/untrusted"
    return 0
  } # signing not set up here yet
  bad=$(signing_check HEAD..origin/main)
  [[ -n $bad ]] || {
    rm -f "$STATE/untrusted"
    return 0
  }
  echo "$bad" > "$STATE/untrusted"
  joining=$(awk '$2 == "U" && $4 != "-" { print $4 }' <<< "$bad" | sort -u | paste -sd' ')
  if [[ -n $joining && -z $(awk '$2 != "U" || $4 == "-"' <<< "$bad") ]]; then
    RESULT=joining
    notify_once untrusted normal "New machine $joining: nothing taken over until you trust it (sync menu)"
  else
    RESULT=untrusted
    notify_once untrusted critical "$(wc -l <<< "$bad") commit(s) on GitHub are not signed by any of your machines. Nothing taken over (sync menu: Review incoming changes)"
  fi
  exit 0
}

# update: bring origin/main in. Returns 1 on a conflict (nothing changed then).
update() {
  local ahead behind
  behind=$(git_ rev-list --count HEAD..origin/main)
  ahead=$(git_ rev-list --count origin/main..HEAD)
  ((behind)) || return 0
  if ((ahead == 0)); then
    git_ merge -q --ff-only origin/main
    return
  fi
  # a linear history: this machine's commits go on top of GitHub's, signed again on the way
  git_ rebase -q --autostash origin/main > /dev/null 2>&1 && return 0
  git_ diff --name-only --diff-filter=U > "$STATE/conflict"
  git_ rebase --abort 2> /dev/null || true
  return 1
}

# changed OLD: the files that differ between OLD and HEAD
changed() { if [[ -n $1 ]]; then git_ diff --name-only "$1" HEAD; else git_ ls-files; fi; }

# apply_changes OLD: links, reloads and packages for what came in
apply_changes() {
  local old=$1 files
  files=$(changed "$old")
  [[ -n $files ]] || return 0
  APPLIED=$(grep -c . <<< "$files")
  local reload=()
  grep -qE '^(personal/|hosts/[^/]+/)?manifest$' <<< "$files" && {
    cmd_link > /dev/null || warn "links not complete (driftless link)"
    setup_units
  }
  if grep -q '^dconf.ini$' <<< "$files"; then dconf load / < "$DRIFTLESS/dconf.ini" 2> /dev/null || warn "dconf not loaded"; fi
  grep -qE '^home/\.config/theme/(templates/|apply\.py|palette\.py)' <<< "$files" && reload+=(theme waybar mako hypr)
  grep -qE '^home/\.config/hypr/' <<< "$files" && reload+=(hypr)
  grep -qE '^home/\.config/waybar/(config.*\.jsonc|render\.py|bar_layout\.py)$' <<< "$files" && reload+=(waybar)
  grep -qE '^home/\.config/waybar/feeds\.py$' <<< "$files" && reload+=(feeds)
  grep -qE '^home/\.config/systemd/' <<< "$files" && reload+=(systemd)
  grep -qE '^system/' <<< "$files" && notify_once system normal "driftless-system changed: run  driftless system  to update this machine's system files"
  ((${#reload[@]} == 0)) || reload "${reload[@]}"
  if grep -qE '^((personal/)?packages/|(personal/|hosts/[^/]+/)?manifest$)' <<< "$files"; then
    install_missing
  fi
  return 0
}

# reload WHAT...: the running programs pick up what changed
reload() {
  local r
  for r in $(printf '%s\n' "$@" | sort -u); do
    case $r in
      theme)
        python3 "$HOME/.config/theme/apply.py" --current > /dev/null || warn "theme not rendered"
        pkill -USR2 -x ghostty 2> /dev/null || true
        ;;
    esac
  done
  for r in $(printf '%s\n' "$@" | sort -u); do
    case $r in
      systemd) systemctl --user daemon-reload 2> /dev/null || true ;;
      hypr) hyprctl reload > /dev/null 2>&1 || true ;;
      mako) makoctl reload 2> /dev/null || true ;;
      waybar) systemctl --user try-restart waybar.service 2> /dev/null || true ;;
      feeds) systemctl --user try-restart driftless-bar.service 2> /dev/null || true ;;
    esac
  done
  return 0
}

# install_missing: repo packages through a password dialog (once per new set, or on "sync now"),
# AUR packages wait in the pill for "Install missing packages" in a terminal
install_missing() {
  local repo aur msg="" urgency=normal rc x
  if [[ $(cat "$STATE/installs" 2> /dev/null) == off ]]; then
    rm -f "$STATE/install-pending"
    return 0
  fi
  mapfile -t repo < <(missing repo)
  mapfile -t aur < <(missing aur)
  if ((${#repo[@]})) && { ((NOW)) || [[ "${repo[*]}" != "$(cat "$STATE/install-asked" 2> /dev/null)" ]]; }; then
    echo "${repo[*]}" > "$STATE/install-asked"
    if [[ ! -x /usr/lib/driftless/install-packages ]]; then
      msg="driftless-system is not installed here, so listed packages cannot be installed (driftless system)"
      urgency=critical
    else
      rc=0
      timeout 300 pkexec /usr/lib/driftless/install-packages "${repo[@]}" || rc=$?
      # 124 nobody answered, 126 dialog cancelled, 127 no polkit agent: the packages wait
      if ((rc && rc != 124 && rc != 126 && rc != 127)); then
        msg="Could not install: ${repo[*]} (maybe update first: sudo pacman -Syu)"
        urgency=critical
      fi
      mapfile -t repo < <(missing repo)
    fi
  fi
  {
    for x in "${repo[@]}"; do echo "repo $x"; done
    for x in "${aur[@]}"; do echo "aur $x"; done
  } > "$STATE/install-pending"
  if [[ -z $msg ]] && ((${#repo[@]} + ${#aur[@]})); then
    msg="$((${#repo[@]} + ${#aur[@]})) listed package(s) wait for install: ${repo[*]} ${aur[*]} (sync menu)"
  fi
  [[ -n $msg ]] && notify_once install "$urgency" "$msg"
  return 0
}

# the optional git bundle (BUNDLE in personal/config): a full copy with history, e.g. for a USB stick
refresh_bundle() {
  [[ -n ${BUNDLE:-} ]] || return 0
  local head
  head=$(git_ rev-parse HEAD)
  [[ -f $BUNDLE && $(cat "$STATE/bundle.head" 2> /dev/null) == "$head" ]] && return 0
  mkdir -p "$(dirname "$BUNDLE")"
  # with HEAD, so "git clone FILE" checks main out
  git_ bundle create -q "$BUNDLE.tmp" HEAD main && mv -f "$BUNDLE.tmp" "$BUNDLE" && echo "$head" > "$STATE/bundle.head"
}

cmd_sync() {
  local adopt=0 old incoming
  NOW=0
  case ${1:-} in --adopt) adopt=1 ;; --now) NOW=1 ;; esac
  mkdir -p "$STATE"
  exec 9> "$STATE/lock"
  flock -n 9 || {
    echo "driftless: a sync is already running"
    return 0
  }
  RESULT=failed APPLIED=0
  trap write_status EXIT
  [[ -e $STATE/now ]] && NOW=1 && rm -f "$STATE/now"
  MODE=$(cat "$STATE/mode" 2> /dev/null || echo review)
  poke_bar
  if [[ $MODE == off ]] && ((!NOW && !adopt)); then
    RESULT=paused
    return 0
  fi
  load_config
  git_ config user.name > /dev/null || git_ config user.name "driftless $HOST"
  git_ config user.email > /dev/null || git_ config user.email "driftless@$HOST.invalid"

  if ((adopt)); then
    git_ fetch -q origin main
    verify_incoming
    git_ reset -q --hard origin/main
    rm -f "$STATE/conflict"
    cmd_link
    setup_units
    apply_changes ""
  else
    commit_local
    old=$(git_ rev-parse HEAD)
    if git_ fetch -q origin main 2> /dev/null; then
      verify_incoming
      incoming=$(git_ rev-list --count HEAD..origin/main)
      if [[ $MODE == review ]] && ((incoming && !NOW)); then
        RESULT=held
        notify_once held normal "$incoming change(s) on GitHub wait for your review (sync pill in the bar)"
        return 0
      fi
      if ! update; then
        RESULT=conflict
        notify_once conflict critical "This machine and GitHub changed the same lines in: $(paste -sd' ' "$STATE/conflict"). Nothing changed. Merge by hand: cd $DRIFTLESS && git rebase origin/main"
        return 1
      fi
      rm -f "$STATE/conflict" "$STATE/conflict.notified"
    else
      RESULT=offline
    fi
    apply_changes "$old"
    [[ $RESULT == offline ]] || install_missing
  fi

  [[ $RESULT == offline ]] || RESULT=ok
  if [[ $RESULT == ok ]] && (($(git_ rev-list --count origin/main..HEAD 2> /dev/null || echo 0))); then
    git_ push -q origin HEAD:main || RESULT="push failed"
  fi
  refresh_bundle || warn "bundle not written"
  ((APPLIED)) && [[ -n $old ]] && notify normal "Taken over from GitHub: $APPLIED file(s)"
  return 0
}
