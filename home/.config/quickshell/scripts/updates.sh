#!/usr/bin/env bash
# The bar: pending pacman + AUR updates as {"repo": N, "aur": N} (the pill hides itself at 0).
repo=$(checkupdates 2> /dev/null | wc -l)
aur=$(yay -Qua 2> /dev/null | wc -l)
printf '{"repo":%d,"aur":%d}\n' "$repo" "$aur"
