# shellcheck shell=bash
# driftless publish OUT [--push]: the public template, from this repository.
#
# Personal things live in their own places, so publishing is leaving them out, not rewriting files:
# personal/ (your layer: manifest, config, notes, calendar), hosts/* except hosts/example, signers/.
# As a last guard every published file is searched for the terms in personal/forbidden (one extended
# regex per line); a hit aborts before anything is written to OUT's history.

PUBLIC_EXCLUDE=(':!personal' ':!signers' ':!hosts')

cmd_publish() {
  local out=${1:?usage: driftless publish OUT [--push]} push=${2:-} files hits msg
  [[ -d $out/.git ]] || die "$out is not a git clone of the public repository"
  [[ -z $(git -C "$DRIFTLESS" status --porcelain) ]] || die "commit first: the export takes the committed state"
  mapfile -t files < <(
    git -C "$DRIFTLESS" ls-files -- . "${PUBLIC_EXCLUDE[@]}"
    git -C "$DRIFTLESS" ls-files -- hosts/example
  )
  # the published tree is exactly the listed files: remove everything else first (not .git)
  find "$out" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
  (cd "$DRIFTLESS" && printf '%s\0' "${files[@]}" | xargs -0 cp --parents -a -t "$out")
  if [[ -s $DRIFTLESS/personal/forbidden ]]; then
    hits=$(grep -rnIE -f <(grep -v '^\s*\(#\|$\)' "$DRIFTLESS/personal/forbidden") "$out" --exclude-dir=.git | head -20 || true)
    [[ -z $hits ]] || die "personal terms in the export, nothing committed:
$hits"
  fi
  git -C "$out" add -A
  if git -C "$out" diff --cached --quiet; then
    echo "public template already up to date"
    return 0
  fi
  git -C "$out" diff --cached --stat | tail -1
  msg="Update from $(git -C "$DRIFTLESS" rev-parse --short HEAD)"
  [[ $push == --push ]] || {
    echo "staged in $out; commit and push with: driftless publish $out --push"
    return 0
  }
  git -C "$out" commit -q -m "$msg"
  git -C "$out" push -q
  echo "published: $msg"
}
