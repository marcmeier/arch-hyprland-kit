#!/usr/bin/env bash
# All static checks, run by CI and by hand: shellcheck and shfmt on every shell script (found by
# shebang), ruff on every Python file. Needs shellcheck, shfmt and ruff in PATH.
set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")/.." || exit

mapfile -t shell < <(git ls-files -co --exclude-standard | while read -r f; do
  [[ -f $f ]] && head -c 80 "$f" | grep -qE '^#!.*\b(ba)?sh\b|^# shellcheck shell=' && echo "$f"
done)
mapfile -t python < <(git ls-files -co --exclude-standard '*.py')

rc=0
step() {
  echo "==> $*"
  "$@" || rc=1
}
step shellcheck "${shell[@]}"
step shfmt -d "${shell[@]}"
step ruff check --no-cache "${python[@]}"
step ruff format --check "${python[@]}"
echo "${#shell[@]} shell scripts, ${#python[@]} Python files: $( ((rc)) && echo FAILED || echo ok)"
exit "$rc"
