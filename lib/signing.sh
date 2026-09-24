#!/usr/bin/env bash
# Signed kit commits: a push to GitHub alone cannot hand this machine anything.
# Every machine signs its commits with its own SSH key (~/.ssh/rebuild-signing, no passphrase: the
# timer signs unattended) and publishes the public half as signers/<host>.pub. The sync
# (auto-snapshot.sh) only takes over commits signed by a key in $STATE/allowed_signers, a local list
# that never travels with the kit: a stolen GitHub token or login can push, but it cannot sign.
#
#   lib/signing.sh setup [--no-sync]   once per machine (restore.sh runs it with --no-sync on new
#                  installs): key, git config, signers/<host>.pub, and trust for this machine and
#                  every machine already in signers/. Without --no-sync it first takes over the
#                  current GitHub state (a last unverified sync) and pushes the key afterwards.
#   lib/signing.sh trust FINGERPRINT   trust the machine whose signers/*.pub on GitHub has this
#                  fingerprint, after you compared it on that machine (sync menu: Trust new machine)
#   lib/signing.sh check RANGE   every commit in RANGE not signed by a trusted machine, one per line:
#                  "<sha> <%G?> <key fingerprint or -> <host from signers/ or ->"
# Stop trusting a machine: delete its line from ~/.local/state/rebuild/allowed_signers.
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$(readlink -f "$0")")/.."
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/rebuild"
ALLOWED=$STATE/allowed_signers
KEY=$HOME/.ssh/rebuild-signing

fingerprint() { ssh-keygen -lf - 2> /dev/null | awk '{ print $2 }'; } # public key on stdin

# host_of FINGERPRINT: the machine whose signers/<host>.pub on GitHub (origin/main) has this key.
# Nothing for a name this machine already trusts: a trusted machine never gets a second key this
# way, so such a file is someone claiming to be it (drop the old line by hand for a real new key).
host_of() {
  local f signer
  [[ -n $1 && $1 != - ]] || return 0
  for f in $(git ls-tree --name-only origin/main signers/ 2> /dev/null); do
    [[ $(git show "origin/main:$f" | fingerprint) == "$1" ]] || continue
    signer=$(basename "$f" .pub)
    awk -v h="$signer" '$1 == h { found = 1 } END { exit !found }' "$ALLOWED" 2> /dev/null || echo "$signer"
    return 0
  done
  return 0
}

# add_signer HOST PUBKEY_FILE: one allowed_signers line, unless this key is in there already
add_signer() {
  local key
  key=$(awk '{ print $1, $2 }' "$2")
  mkdir -p "$STATE"
  touch "$ALLOWED"
  grep -qF "$key" "$ALLOWED" || echo "$1 namespaces=\"git\" $key" >> "$ALLOWED"
}

check() {
  local sha st fp
  git -c gpg.ssh.allowedSignersFile="$ALLOWED" log --format='%H %G? %GK' "$1" | while read -r sha st fp; do
    [[ $st == G ]] && continue
    echo "$sha $st ${fp:--} $(host_of "${fp:--}" | grep . || echo -)"
  done
}

setup() {
  local host f signer
  host=$(< /etc/hostname)
  # a fresh install has no git identity: name the machine (only for this repository, no real address)
  git config user.name > /dev/null || git config user.name "rebuild-kit $host"
  git config user.email > /dev/null || git config user.email "rebuild-kit@$host.invalid"
  if [[ ! -f $KEY ]]; then
    [[ -d $HOME/.ssh ]] || mkdir -m700 "$HOME/.ssh"
    ssh-keygen -q -t ed25519 -N '' -C "rebuild-kit $host" -f "$KEY"
  fi
  git config gpg.format ssh
  git config user.signingkey "$KEY.pub"
  git config commit.gpgsign true
  git config gpg.ssh.allowedSignersFile "$ALLOWED"
  # a machine that is not verifying yet takes over what GitHub has now, as it did so far
  if [[ ${1:-} != --no-sync && ! -e $ALLOWED ]]; then
    echo "==> taking over the current GitHub state (the last sync without signature check)"
    ./auto-snapshot.sh --now
  fi
  install -Dm644 "$KEY.pub" "signers/$host.pub"
  add_signer "$host" "$KEY.pub"
  echo "==> trusted on this machine:"
  for f in signers/*.pub; do
    signer=$(basename "$f" .pub)
    [[ $signer == "$host" ]] || add_signer "$signer" "$f"
    echo "    $signer  $(fingerprint < "$f")"
  done
  git add "signers/$host.pub"
  git diff --cached --quiet -- "signers/$host.pub" || git commit -q -m "Signing key of $host" -- "signers/$host.pub"
  [[ ${1:-} == --no-sync ]] || ./auto-snapshot.sh --now
  echo "==> $host signs its kit commits now. Your other machines hold them back until you trust it"
  echo "    there (sync pill menu: Trust new machine). Its fingerprint: $(fingerprint < "$KEY.pub")"
}

trust() {
  local fp=${1:?usage: signing.sh trust FINGERPRINT} host answer tmp
  host=$(host_of "$fp")
  [[ -n $host ]] || {
    echo "No new machine on GitHub has the key $fp (no signers/*.pub with it, or its name is trusted here already with another key)." >&2
    exit 1
  }
  echo "The machine \"$host\" wants this one to take over its kit changes."
  echo "Only trust it if it really is yours. On $host, run:"
  echo
  echo "    ssh-keygen -lf ~/.ssh/rebuild-signing.pub"
  echo
  echo "It must show exactly: $fp"
  read -rp "Same fingerprint? Then type yes: " answer
  [[ $answer == yes ]] || {
    echo "Not trusted."
    exit 1
  }
  tmp=$(mktemp)
  git show "origin/main:signers/$host.pub" > "$tmp"
  add_signer "$host" "$tmp"
  rm -f "$tmp"
  echo "Trusted: $host. The next sync takes over its changes."
}

case ${1:-} in
  setup) setup "${2:-}" ;;
  trust) trust "${2:-}" ;;
  check) check "${2:?usage: signing.sh check RANGE}" ;;
  *)
    echo "usage: $0 setup [--no-sync] | trust FINGERPRINT | check RANGE" >&2
    exit 2
    ;;
esac
