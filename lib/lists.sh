# shellcheck shell=bash
# Shared package / extension lists. packages/*.txt are shared by all machines, so a snapshot must
# not simply overwrite them with "what this machine has" (the machines would keep undoing each
# other). Instead every machine only adds what it installed and drops what it removed since its
# own last snapshot; entries that only another machine has stay untouched.

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
