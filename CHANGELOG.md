# Changelog

Versions follow the [releases](../../releases), which have the full notes and upgrade steps.

## v1.4.1 (2026-09-24)

### Security
- `restore.sh` no longer writes a temporary `NOPASSWD: ALL` sudoers rule for the AUR step. If the script was killed at the wrong moment, that rule stayed and made the user root without a password. Now it asks for the user's password once at the start and keeps that sudo ticket alive until the AUR step is done; the keepalive stops at the latest a minute after the script ends. A leftover rule from an interrupted older run is removed, and `verify.sh` names it.

### Added
- `restore.sh --review-aur`: yay shows every PKGBUILD and asks before building. Without it, `restore.sh` says up front that the AUR packages are built without review.

### Fixed
- `restore.sh` reset `ufw` on every run, which deleted your own firewall rules. It now only sets the defaults while the firewall is not enabled yet.

## v1.4.0 (2026-09-24)

Changes after feedback on r/hyprland.

### Fixed
- A config file that one machine never had was deleted on all other machines. `snapshot.sh` rebuilt `files/home` from the machine's live files, so a folder missing there looked like a deletion, and the sync applied it everywhere. Now a missing file only counts as deleted if that machine had it before (`guard_deletions` in `lib/lists.sh`).
- `install-base.sh --help` printed two lines of code.

### Changed
- The default sync mode is now *review first*: a machine shows incoming changes and applies them only after *Sync now*. Machines that already have a mode keep it.
- Merge conflicts stop the sync. Before, the sync merged with `-X theirs`, so GitHub's side replaced local changes to the same lines without telling you. Now nothing is applied or pushed, and the sync pill and a notification name the files.
- `files/dconf.ini` leaves out window sizes and positions. They differ per screen and caused most of the noise and conflicts.
- Resuming a paused sync restores the previous mode instead of *automatic*.
- The README now says what the project is and isn't, compares it with alternatives and lists known limitations. Script comments are shorter.

### Added
- Before the sync replaces or deletes a file, it copies it to `~/.local/state/rebuild/backup/<time>/`. The last 10 runs are kept.

### Upgrade
Existing machines keep their current mode. To switch one to *review first*: sync pill menu → *Mode: review GitHub changes first*.

## v1.3.0 (2026-09-23)

### Security
- The sync only takes over commits signed by one of your machines (`lib/signing.sh`). A stolen GitHub token or login can still push, but nothing it pushes is applied. A compromised machine of yours is not covered, since its key signs.

## v1.2.0 (2026-09-23)

### Security
- The sync no longer runs pacman without a password. Missing packages come up in a polkit dialog (`pkexec rebuild-install`, package names only). The old sudoers rule let every process of the user run pacman as root.
- AUR packages are never built unattended; they wait until you install them in a terminal.

### Added
- Colour picker on `SUPER + K`.

## v1.1.2 (2026-09-23)

### Fixed
- The sync's pacman rule was overridden by the wheel rule, and the sync's failed sudo attempts could lock the account via pam_faillock.

## v1.1.1 (2026-09-23)

### Fixed
- After the sync restarted Waybar, every later run stopped with "already running": Waybar had inherited the sync's lock.

## v1.1.0 (2026-09-23)

### Added
- Sync pill in Waybar: state, incoming changes and new packages per machine; modes *automatic*, *review first* and *off*; a menu to control it.

## v1.0.2 (2026-09-23)

### Fixed
- The notifications module broke after the sync restarted Waybar (the sync's `LC_ALL=C` was inherited).

## v1.0.1 (2026-09-23)

### Fixed
- Waybar was killed when the sync restarted it, because it stayed in the sync service's cgroup.

## v1.0.0 (2026-09-23)

First public release: installer (`install-base.sh`, `restore.sh`, `verify.sh`), hourly sync between machines, hardware detection, Hyprland desktop with a wallpaper-based theme.

At that point the sync ran pacman without a password and built AUR packages unattended, so anyone who could push to the repository was root on every machine. v1.2.0 and v1.3.0 changed that.
