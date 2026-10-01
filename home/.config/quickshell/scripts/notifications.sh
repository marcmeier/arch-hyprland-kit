#!/usr/bin/env bash
# The bar: mako's state as {"count": N, "dnd": true|false} (notifications waiting, do not disturb).
n=$(makoctl list 2> /dev/null | grep -c '^Notification')
dnd=false
makoctl mode 2> /dev/null | grep -qx dnd && dnd=true
printf '{"count":%d,"dnd":%s}\n' "$n" "$dnd"
