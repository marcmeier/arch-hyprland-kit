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

Whole folders are linked where the folder belongs to the setup (hypr, quickshell, theme, ...), single
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
  last; `~/.config/uwsm/env` sources `host/env`; the bar reads `host/bar.json`; scripts read
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

Root is reached through two polkit actions, each a single helper in `/usr/lib/driftless`. Installing
packages asks for the password every time: it changes the system. Updating the login screen
(`greeter-update`) does not, so a new wallpaper, by hand or by the daily timer, reaches it at once.
That is safe because the helper reads the theme files with the caller's rights (`setpriv` to
`PKEXEC_UID`), not root's: a program in the session can only show on the login screen what it could
read anyway, and no symlink swapped in between a check and the copy makes root read `/etc/shadow`.

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

**Now:** uwsm runs the session; the desktop shell (which is also the polkit agent), hypridle, cliphist,
awww and elephant are user units bound to `graphical-session.target`. The sync restarts one with
`systemctl --user try-restart`. A unit the kit drops is listed as `user-unit-retired` in the
manifest, and the sync switches it off on every machine.

## 8. The bar is a Quickshell shell

**Before:** Waybar, styled with CSS, plus a Python process (`feeds.py`) that followed Hyprland and
playerctl and wrote one JSON file per button, which the modules `cat` when signalled; custom
workspace buttons because Waybar 0.15 dispatched in the syntax Hyprland 0.56 rejects; a second
Quickshell instance just for the Claude bubble; a rendered config per machine and a restart of Waybar
after every change of widgets, bar size or wallpaper; tooltips as the only place for details.

**Now:** one Quickshell process (`driftless-shell.service`, `home/.config/quickshell`) draws a bar per
screen, its tooltips and popups, and the Claude bubble. Workspaces, the window, sound, media, battery,
network, Bluetooth and the tray come from Quickshell's own services (Hyprland IPC, PipeWire, MPRIS,
UPower, NetworkManager, BlueZ, StatusNotifierItem), so they follow events without a helper process.
Scripts remain for what has no service (Claude usage, the sync, weather, calendar, updates) and print
plain JSON; a script that changes something tells the bar with `scripts/poke NAME` (IPC), where Waybar
needed a signal number per module. The theme comes from `theme/colors.json` and the widget layout from
`layout.json`, both followed live: no restarts. The QML applies on save.

The widget layout keeps Waybar's names (`group/status`, `custom/sync`, ...), so the saved layouts of
both machines carried over, and `bar.jsonc` lists the widgets as `config.jsonc` did.

*Considered:* keeping Waybar and only moving the popups to Quickshell. Two toolkits would have drawn
one bar, with two theme systems and the signal plumbing left in place. *Considered:* a ready-made
Quickshell config (end-4, Caelestia, DankMaterialShell): far more than the bar needs, and they bring
their own launcher and settings, which this setup has.

## 9. Notifications, lock screen, power menu and password dialog are the shell too

**Before:** mako for notifications (its own config format, rendered from a template; the bell polled
`makoctl` every five seconds), hyprlock for the lock screen, wlogout for the power menu (CSS, PNG icons
recoloured per wallpaper, a script to centre it). Three more programs and three more theme files, and
none of them knew the others or the bar.

**Now:** the shell is the notification server (`services/Notifs.qml`, Quickshell's
`NotificationServer`), and draws the lock screen (`lock/`, `WlSessionLock` and PAM), the power menu
(`power/`), an on-screen display for volume and brightness (`osd/`) and, as the session's polkit agent,
the password dialog (`polkit/`, hyprpolkitagent before), with the same cards, colours and motion as the
bar; the lock screen and the password dialog share one password field (`bar/PasswordField.qml`). They
share state instead of polling: the bell reads the list itself, the lock screen and a fullscreen
window hold the popups, suspend waits until the lock is drawn. One file
(`services/Session.qml`) is where lock, log out and suspend happen, whoever asks.

Three things keep it safe:

- **Who answers notifications:** a D-Bus activation file in the home
  (`~/.local/share/dbus-1/services/org.freedesktop.Notifications.service`) comes before mako's, so a
  notification sent while the shell is down starts the shell. mako is a retired unit.
- **A lock that never opens by itself:** the lock state outlives a reload of the QML (the sync brings
  new files every hour), a marker in `$XDG_RUNTIME_DIR` tells a restarted shell to lock again, and
  Hyprland's `allow_session_lock_restore` lets it. hypridle's `lock_cmd` (`scripts/lock`) falls back to
  hyprlock when the shell does not answer "locked".
- **The password check** uses its own PAM file with `pam_unix` only: the `login` stack's faillock would
  shut you out of your own screen for ten minutes after three typos.

The settings are a popup of the bar too (`bar/SettingsPopup.qml`, walker menus before); the scripts
behind them stay (`settings-menu.sh`, `bar_layout.py`), so the walker menus remain for what needs more
room (moving widgets, the wallpaper folder with a preview) and as the way in without the shell. The
notification list outlives a restart in `~/.local/state/driftless-shell/notifications.json`: per
machine, in a folder only the user can read, seven days at most. A token per run of the shell tells a
restart (everything comes back from the file) from a reload (the live ones come back from the server
and keep their time).

*Considered:* keeping mako, wlogout, hyprlock and hyprpolkitagent and only theming them better. They
were themed; what was missing was that they work together. walker, hypridle and awww stay: they work
unseen or already match, and replacing them would add code without adding anything you notice. blueman
stays for its pairing agent and settings; the bar hides its tray icon, it shows Bluetooth itself.

The polkit agent registers once, when the shell starts, and polkit allows one per session: the sync
restarts the shell when the agent's files change, after the retired hyprpolkitagent let go. The lock
screen checks the password with `pam_unix` alone; the password dialog cannot choose, polkit runs its
own PAM stack (`polkit-1`, with faillock, which also counts a cancelled request).

## What stayed

Hardware detection from sysfs. Review mode as the default for incoming changes. Signed commits with
per machine SSH keys and a local list of trusted machines. Package installs only after a password
dialog, AUR builds only in a terminal. The theme generated from the wallpaper. Per machine settings
in `~/.local/state`. Real tests of the sync between two machines.
