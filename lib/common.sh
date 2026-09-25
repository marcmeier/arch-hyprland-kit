# shellcheck shell=bash
# Shared by every driftless command: paths, messages, host facts and the manifest.
#
# The manifest is a plain list of what this repository wants on a machine. It is read from three
# layers, all optional except the first: manifest, personal/manifest, hosts/<host>/manifest.
#
#   link       TARGET [SOURCE]    ~/TARGET becomes a symlink to SOURCE (default home/TARGET)
#   group      NAME               packages/NAME.list is installed
#   unit       NAME               system unit that is enabled
#   user-unit  NAME               user unit that is enabled
#
# Any line can end in "if=FACT" (or "if=!FACT"); facts come from lib/hardware.sh (hw_facts), plus
# "host:NAME". SOURCE may contain {host}. Blank lines and "#" comments are ignored.

DRIFTLESS=${DRIFTLESS:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
# shellcheck disable=SC2034 # used by the other lib/ files
STATE=${DRIFTLESS_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/driftless}
# the machine's name: an override for tests, else the kernel's (works in chroots and live ISOs)
HOST=${DRIFTLESS_HOST:-$(cat /etc/hostname 2> /dev/null || uname -n)}

# shellcheck source=lib/hardware.sh
source "$DRIFTLESS/lib/hardware.sh"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*" >&2; }
die() {
  printf '\033[1;31mxx\033[0m  %s\n' "$*" >&2
  exit 1
}

# personal settings (personal/config, not in the public template): plain shell variables
load_config() {
  # shellcheck source=/dev/null
  [[ -r $DRIFTLESS/personal/config ]] && source "$DRIFTLESS/personal/config"
  return 0
}

# FACTS: space separated, filled once per process (the manifest and package groups need them)
FACTS=""
facts() {
  if [[ -z $FACTS ]]; then
    hw_detect
    FACTS=" $(hw_facts | tr '\n' ' ') host:$HOST "
  fi
  printf '%s\n' "$FACTS"
}

has_fact() {
  local want=${1#!}
  facts > /dev/null
  if [[ $1 == !* ]]; then [[ $FACTS != *" $want "* ]]; else [[ $FACTS == *" $want "* ]]; fi
}

manifest_files() {
  local f
  for f in "$DRIFTLESS/manifest" "$DRIFTLESS/personal/manifest" "$DRIFTLESS/hosts/$HOST/manifest"; do
    [[ -r $f ]] && echo "$f"
  done
  return 0
}

# manifest KIND: the arguments of every KIND line that applies to this machine, one line each
manifest() {
  local kind=$1 f line word args cond
  facts > /dev/null
  while IFS= read -r f; do
    while IFS= read -r line || [[ -n $line ]]; do
      line=${line%%#*}
      read -ra args <<< "$line"
      if ((${#args[@]} == 0)) || [[ ${args[0]} != "$kind" ]]; then continue; fi
      cond=""
      if [[ ${args[-1]} == if=* ]]; then
        cond=${args[-1]#if=}
        unset 'args[-1]'
      fi
      [[ -z $cond ]] || has_fact "$cond" || continue
      word="${args[*]:1}"
      echo "${word//\{host\}/$HOST}"
    done < "$f"
  done < <(manifest_files)
}

# notify URGENCY TEXT: a desktop notification when there is a desktop, the log in any case
notify() {
  echo "driftless: $2"
  notify-send -u "$1" -a driftless "driftless" "$2" 2> /dev/null || true
}

# refresh the sync pill in waybar
poke_bar() { pkill -RTMIN+11 -x waybar 2> /dev/null || true; }
