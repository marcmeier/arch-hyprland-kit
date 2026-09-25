# shellcheck shell=bash
# shellcheck disable=SC2153 # HOST and STATE come from lib/common.sh
# Signed commits: a push to GitHub alone cannot hand a machine anything.
#
# Every machine signs its commits with its own SSH key (~/.ssh/driftless-signing, no passphrase: the
# timer signs unattended) and publishes the public half as signers/<host>.pub. The sync only takes
# over commits signed by a key in $STATE/allowed_signers, a list that exists only on the machine and
# never travels with the repository. A stolen GitHub token or login can push, but it cannot sign.
# Not covered: a compromised machine of yours, since its key signs.

SIGNING_KEY=${DRIFTLESS_SIGNING_KEY:-$HOME/.ssh/driftless-signing}
ALLOWED=$STATE/allowed_signers

fingerprint() { ssh-keygen -lf - 2> /dev/null | awk '{ print $2 }'; } # public key on stdin

# host_of FINGERPRINT: the machine whose signers/<host>.pub on origin/main has this key. Nothing for a
# name this machine already trusts: a trusted machine never gets a second key this way, so such a
# file is someone claiming to be it (drop the old line by hand for a real new key).
host_of() {
  local f signer
  [[ -n $1 && $1 != - ]] || return 0
  for f in $(git -C "$DRIFTLESS" ls-tree --name-only origin/main signers/ 2> /dev/null); do
    [[ $(git -C "$DRIFTLESS" show "origin/main:$f" | fingerprint) == "$1" ]] || continue
    signer=$(basename "$f" .pub)
    awk -v h="$signer" '$1 == h { found = 1 } END { exit !found }' "$ALLOWED" 2> /dev/null || echo "$signer"
    return 0
  done
  return 0
}

add_signer() { # add_signer HOST PUBKEY_FILE
  local key
  key=$(awk '{ print $1, $2 }' "$2")
  mkdir -p "$STATE"
  touch "$ALLOWED"
  grep -qF "$key" "$ALLOWED" || echo "$1 namespaces=\"git\" $key" >> "$ALLOWED"
}

# signing_check RANGE: every commit in RANGE not signed by a trusted machine, one per line:
#   "<sha> <%G?> <key fingerprint or -> <host from signers/ or ->"
signing_check() {
  local sha st fp
  git -C "$DRIFTLESS" -c gpg.ssh.allowedSignersFile="$ALLOWED" log --format='%H %G? %GK' "$1" |
    while read -r sha st fp; do
      [[ $st == G ]] && continue
      echo "$sha $st ${fp:--} $(host_of "${fp:--}" | grep . || echo -)"
    done
}

# signing_setup: key, git config, signers/<host>.pub, and trust for every machine in signers/.
# A machine coming from the old rebuild kit keeps its key and its list of trusted machines.
signing_setup() {
  local f signer old_state=${XDG_STATE_HOME:-$HOME/.local/state}/rebuild
  git -C "$DRIFTLESS" config user.name > /dev/null || git -C "$DRIFTLESS" config user.name "driftless $HOST"
  git -C "$DRIFTLESS" config user.email > /dev/null || git -C "$DRIFTLESS" config user.email "driftless@$HOST.invalid"
  if [[ ! -f $SIGNING_KEY && -f $HOME/.ssh/rebuild-signing ]]; then
    cp -a "$HOME/.ssh/rebuild-signing" "$SIGNING_KEY"
    cp -a "$HOME/.ssh/rebuild-signing.pub" "$SIGNING_KEY.pub"
  fi
  if [[ ! -f $SIGNING_KEY ]]; then
    [[ -d $HOME/.ssh ]] || mkdir -m700 "$HOME/.ssh"
    ssh-keygen -q -t ed25519 -N '' -C "driftless $HOST" -f "$SIGNING_KEY"
  fi
  if [[ ! -e $ALLOWED && -s $old_state/allowed_signers ]]; then
    mkdir -p "$STATE"
    cp "$old_state/allowed_signers" "$ALLOWED"
  fi
  git -C "$DRIFTLESS" config gpg.format ssh
  git -C "$DRIFTLESS" config user.signingkey "$SIGNING_KEY.pub"
  git -C "$DRIFTLESS" config commit.gpgsign true
  git -C "$DRIFTLESS" config gpg.ssh.allowedSignersFile "$ALLOWED"
  install -Dm644 "$SIGNING_KEY.pub" "$DRIFTLESS/signers/$HOST.pub"
  add_signer "$HOST" "$SIGNING_KEY.pub"
  echo "trusted on this machine:"
  for f in "$DRIFTLESS"/signers/*.pub; do
    signer=$(basename "$f" .pub)
    [[ $signer == "$HOST" ]] || add_signer "$signer" "$f"
    echo "  $signer  $(fingerprint < "$f")"
  done
  git -C "$DRIFTLESS" add "signers/$HOST.pub"
  git -C "$DRIFTLESS" diff --cached --quiet -- "signers/$HOST.pub" ||
    git -C "$DRIFTLESS" commit -q -m "$HOST: signing key" -- "signers/$HOST.pub"
  echo "$HOST signs its commits. Its fingerprint: $(fingerprint < "$SIGNING_KEY.pub")"
}

# signing_trust FINGERPRINT: trust a new machine after comparing the fingerprint on it
signing_trust() {
  local fp=${1:?usage: driftless trust FINGERPRINT} host answer tmp
  host=$(host_of "$fp")
  [[ -n $host ]] || die "no new machine on GitHub has the key $fp"
  echo "The machine \"$host\" wants this one to take over its changes."
  echo "Only trust it if it really is yours. On $host, run:"
  echo
  echo "    ssh-keygen -lf ~/.ssh/driftless-signing.pub"
  echo
  echo "It must show exactly: $fp"
  read -rp "Same fingerprint? Then type yes: " answer
  [[ $answer == yes ]] || die "not trusted"
  tmp=$(mktemp)
  git -C "$DRIFTLESS" show "origin/main:signers/$host.pub" > "$tmp"
  add_signer "$host" "$tmp"
  rm -f "$tmp"
  echo "Trusted: $host. The next sync takes over its changes."
}
