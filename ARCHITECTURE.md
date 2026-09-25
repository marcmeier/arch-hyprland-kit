# Architecture

driftless is the second version of a kit that kept several Arch + Hyprland machines in step. The
first version worked and was well tested, but most of its code fought the consequences of one early
decision. This file explains the decisions of the second version, each against what it replaced.

## 1. The repository is the source, the home is linked

**Before:** the live home was the truth. Every hour a snapshot deleted the kit's copy of the dotfiles
and copied whole folders in again; the sync copied changed files back out. From that came:
deletion guessing (a file missing on one machine: deleted there, or never had?), a list of per machine
files to put back after every snapshot, backups before every copy, a dozen state files, auto commits
of everything that appeared in a copied folder (tokens included), and hourly "Automatic snapshot"
and merge commits.

**Now:** `~/.config/hypr` is a symlink to `home/.config/hypr`. There is nothing to copy, so there is
nothing to guess: git sees an edit or a deletion the moment it happens. The sync commits only files
the repository already tracks (`git add -u`), so a new file never goes to GitHub by accident, and it
refuses a commit that looks like a credential. Old versions are in git, so no backup folders.

Whole folders are linked where the folder belongs to the setup (hypr, waybar, theme, ...), single
files where programs keep their own files next to ours (applications, gtk-3.0). A program that saves
by replacing a file breaks a file link; the sync then takes the new content into the repository and
links again (`heal` in `lib/link.sh`).

*Considered:* chezmoi (templates, source state). It is the common answer, but editing then means
`chezmoi edit` or `re-add`, and the setup is edited live all the time. The places where files differ
per machine are handled by the programs' own include mechanisms (next section), which needs no
template engine for the dotfiles.

## 2. One mechanism for "differs per machine / per person"

**Before:** three: a list of per machine files, `sed` patches in the restore script (network
interface, battery module, NVIDIA variables, paths, the greeter's hostname), and an export script
with rewrite rules and `PRIVATE-BEGIN` blocks to make a public copy.

**Now:** layers, loaded by the programs themselves:

- `hosts/<hostname>/` is linked as `~/.config/driftless/host`, `personal/` as
  `~/.config/driftless/personal`. `hyprland.lua` loads `host/hyprland.lua` and `personal/hyprland.lua`
  last; `~/.config/uwsm/env` sources `host/env`; Waybar reads `host/waybar.json`; scripts read
  `personal/config`.
- Values that the system knows are read from it: the user's name for the bar comes from the account,
  the hostname for the login screen from `/etc/hostname`, NVIDIA-only machines are detected at login.
- Paths are relative (`@import url("../theme/colors.css")`) or rendered with `@home@`.
- The manifest has layers too: `manifest`, `personal/manifest`, `hosts/<host>/manifest`.

Publishing is then leaving `personal/`, `signers/` and the real hosts out. The personal terms list is
only a last guard; nothing needs rewriting.

## 3. Package lists are written, not recorded

**Before:** `pacman -Qqen` of every machine was merged into one list. Anything tried out on one
machine landed on all of them, and since the sync never uninstalls, the list only grew.

**Now:** `packages/<group>.list`, by hand or with `driftless packages add`. The manifest picks the
groups, hardware groups by fact. `driftless packages` shows what is installed but in no list, so
drift is visible and you decide. Hardware packages need no filter any more: they are just groups.

## 4. System files are a package

**Before:** `/etc` files were recorded from the machines but never applied (that needs root); only a
new install copied them. Vendor files were edited with `sed` (mkinitcpio HOOKS, a PAM file), and the
list of system files existed three times (restore, snapshot, verify).

**Now:** `system/` is the `driftless-system` package. pacman installs, updates and removes its files.
Everything is a drop-in (`/usr/lib/sysctl.d`, `*.service.d`, `zram-generator.conf.d`,
`mkinitcpio.conf.d`, `NetworkManager/conf.d`), so no file of another package is touched. greetd and
smartd get their configuration through a service drop-in instead of replacing `/etc/greetd/config.toml`
and `/etc/smartd.conf`. The one edit that is left, two keyring lines in `/etc/pam.d/greetd`, is done
by the package's install script. Lists of units live in the manifest, read by bootstrap and verify.

## 5. Boot: unified kernel images

**Before:** boot entries were derived from each other with `sed` (LTS, Surface), microcode `initrd`
lines added or removed, splash options appended.

**Now:** mkinitcpio builds one EFI file per kernel with the command line from `/etc/kernel/cmdline`,
and systemd-boot finds them by itself. A new kernel is a new entry without any code. `editor no`
keeps the command line from being changed at the boot menu. It is also the base for Secure Boot.

## 6. Encryption

The old kit protected against a stolen GitHub token (signed commits, kept here), but notebooks had
no disk encryption, and a stolen notebook is the likelier loss. `install-base.sh --encrypt` puts the
btrfs into LUKS2; `driftless verify` warns on a notebook without it.

## 7. The session is systemd

**Before:** Hyprland started the bar, the notification daemon and the rest itself, and a watcher
process restarted Waybar whenever monitors changed. Restarting any of it from the sync needed tricks
(own scopes, a closed lock descriptor, the locale reset).

**Now:** uwsm runs the session; Waybar, mako, hypridle, the polkit agent, cliphist, swaybg, elephant
and the bar feeds are user units bound to `graphical-session.target`. The sync restarts one with
`systemctl --user try-restart`. Waybar gets one bar per output from its own `output` rules
(`["eDP-1"]` compact, `["!eDP-1", "*"]` spacious), so no watcher is needed.

The workspace buttons, the window title and the media pill were eleven Python processes (one per
button). They are one now: `feeds.py` follows Hyprland and playerctl and writes each module's line to
a file; the modules `cat` it when signalled. (The buttons are custom because Waybar 0.15's workspace
module still dispatches in the syntax Hyprland 0.56 rejects.)

## What stayed

Hardware detection from sysfs. Review mode as the default for incoming changes. Signed commits with
per machine SSH keys and a local list of trusted machines. Package installs only after a password
dialog, AUR builds only in a terminal. The theme generated from the wallpaper. Per machine settings
in `~/.local/state`. Real tests of the sync between two machines.
