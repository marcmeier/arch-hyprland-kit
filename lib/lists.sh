# shellcheck shell=bash
# Shared kit state. The kit is shared by all machines, so a snapshot must not simply overwrite it
# with "what this machine has" (the machines would keep undoing each other). Instead every machine
# only adds what it got and drops what it removed since its own last snapshot; entries that only
# another machine has stay untouched.

# merge_list LIST NOW BASE
#   LIST  the kit's list (rewritten in place, sorted)
#   NOW   what this machine has right now, one name per line (becomes the new BASE)
#   BASE  what this machine had at its last snapshot (state file). Missing on the first run:
#         then nothing counts as removed and everything not yet listed counts as added.
merge_list() {
  local list=$1 now=$2 base=$3 tmp
  tmp=$(mktemp)
  sort -u "$now" -o "$now"
  touch "$list"
  if [[ -f $base ]]; then sort -u "$base" > "$tmp.base"; else comm -12 "$now" <(sort -u "$list") > "$tmp.base"; fi
  {
    comm -23 <(sort -u "$list") <(comm -23 "$tmp.base" "$now")   # list minus what was removed here
    comm -23 "$now" "$tmp.base"                                  # plus what was installed here
  } | sort -u > "$tmp"
  mv "$tmp" "$list"
  mv "$now" "$base"
  rm -f "$tmp.base"
}

# guard_deletions BASE DIR...
#   The same for files. snapshot.sh rebuilds each DIR (e.g. files/home) from this machine's live
#   files, so a kit file this machine never had would look deleted and the sync would delete it on
#   every other machine. A missing file only counts as deleted if it is in BASE (the kit files this
#   machine had at its last snapshot, or got from the sync since); any other one is put back from
#   the index. BASE then becomes what the DIRs hold now. Missing BASE: nothing counts as deleted.
guard_deletions() {
  local base=$1 now f
  shift
  now=$(mktemp)
  find "$@" \( -type f -o -type l \) 2> /dev/null | sort -u > "$now"
  while IFS= read -r -d '' f; do
    if ! grep -qxF -- "$f" "$base" 2> /dev/null; then
      git checkout -q -- "$f"
    fi
  done < <(git ls-files -z --deleted -- "$@")
  mv "$now" "$base"
}

# filter_dconf: "dconf dump /" on stdin, minus window geometry and similar per machine UI state.
# It differs between screens and changes on every resize, so it only caused commits nobody cares
# about and merge conflicts. Sections left without keys are dropped.
DCONF_SKIP='^(window-(size|position|width|height|state|maximized)|is-maximized|maximized|initial-size|sidebar-width|name-column-width|vm-window-size|manager-window-(width|height))$'
filter_dconf() {
  awk -v skip="$DCONF_SKIP" '
    /^\[/ { header = $0; shown = 0; next }
    /^$/  { next }
    {
      key = $0; sub(/=.*/, "", key)
      if (key ~ skip) next
      if (!shown) { if (printed) print ""; print header; shown = printed = 1 }
      print
    }'
}
