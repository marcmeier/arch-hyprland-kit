#!/usr/bin/env python3
"""Adapt the Waybar "network" module to the machine it runs on (the kit ships the desktop PC's version).

- drop the fixed "interface": "eno1" when this machine has no such interface
- when a WiFi device exists, show it (icon + signal) instead of a permanent red "offline"
Idempotent. Usage: waybar-network.py ~/.config/waybar/config.jsonc
"""
import glob, os, re, sys

p = sys.argv[1]
s = open(p).read()
orig = s

# the desktop PC has a fixed ethernet interface name; other machines don't, so drop that line
if not os.path.exists("/sys/class/net/eno1"):
    s = re.sub(r'\n[ \t]*"interface": "eno1",', "", s, count=1)

# any network device with a "wireless" subdirectory in sysfs is a WiFi adapter
has_wifi = any(os.path.isdir(d + "/wireless") for d in glob.glob("/sys/class/net/*"))
if has_wifi and '"format-wifi"' not in s:
    # insert the WiFi format right after the existing ethernet format, so it's only added once
    s = re.sub(
        r'([ \t]*"format-ethernet": "",[^\n]*\n)',
        lambda m: m.group(1)
        + '        "format-wifi": "\\uf1eb {signalStrength}%",\n'
        + '        "tooltip-format-wifi": "{essid}\\n{ipaddr}/{cidr}",\n',
        s,
        count=1,
    )

if s != orig:
    open(p, "w").write(s)
    print("waybar network module adapted")
else:
    print("waybar network module unchanged")
