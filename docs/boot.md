# Boot: unified kernel images

A new install (`install/install-base.sh`) boots with unified kernel images (UKI): mkinitcpio packs
kernel, initramfs, microcode and the command line into `/boot/EFI/Linux/arch-<kernel>.efi`, and
systemd-boot lists every file there on its own. Nothing to write per kernel: installing `linux-lts`
or `linux-surface` adds a boot entry, removing it removes the entry.

| File | What it holds |
|---|---|
| `/etc/kernel/cmdline` | the kernel command line baked into every image |
| `/etc/mkinitcpio.d/<kernel>.preset` | `default_uki=...` instead of `default_image=` (`uki_presets` in `lib/boot.sh`) |
| `/etc/mkinitcpio.conf.d/driftless.conf` | the hooks (driftless-system) |
| `/etc/mkinitcpio.conf.d/10-gpu.conf` | early KMS modules for this machine's GPU (bootstrap) |
| `/boot/loader/loader.conf` | default entry, no menu (hold Space at power-on), `editor no` |

A kernel installed later gets a fresh preset from its package. `bootstrap.sh` converts all presets;
after installing another kernel by hand, run it again or `source lib/boot.sh && uki_presets &&
mkinitcpio -P` as root.

## Moving an existing machine (classic entries) to UKIs

`install/switch-to-uki.sh` does it and keeps the old entries in the menu as a fallback:

1. writes `/etc/kernel/cmdline` from the `options` line of `/boot/loader/entries/arch.conf`
   (and adds the splash options if missing)
2. converts every preset and rebuilds the images
3. checks that an `.efi` exists for every installed kernel, then makes `arch-linux.efi` the default

Reboot. If it does not come up, hold Space at power-on and pick an old entry. Once the new one has
booted a few times, delete the old entries (`/boot/loader/entries/*.conf`) and the old
`/boot/initramfs-*.img`.

## Secure Boot, later

With UKIs, Secure Boot is `sbctl create-keys`, `sbctl enroll-keys -m` (keeps Microsoft's keys for
firmware option ROMs), and `sbctl sign -s` for `systemd-bootx64.efi` and each UKI; sbctl's pacman
hook re-signs after updates. Not automated here: enrolling keys is a firmware step you should watch.
