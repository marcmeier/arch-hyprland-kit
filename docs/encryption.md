# Disk encryption

`install/install-base.sh --encrypt` formats the system partition as LUKS2 and puts the btrfs inside
(`/dev/mapper/cryptroot`). The initramfs unlocks it with `sd-encrypt`; the command line says which
partition: `rd.luks.name=<UUID>=cryptroot root=/dev/mapper/cryptroot` in `/etc/kernel/cmdline`.
The ESP stays unencrypted, it only holds the signed-or-not boot files.

Without encryption, anyone holding the disk reads everything on it: SSH keys, browser sessions, the
signing key that lets this machine change your other machines. On a notebook, `driftless verify`
warns about it.

## Unlocking without typing the password

The TPM can hold a key that it only releases when the machine boots as expected:

```bash
sudo pacman -S --needed tpm2-tss
sudo systemd-cryptenroll --recovery-key /dev/disk/by-partlabel/archroot   # write it down, offline
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-with-pin=yes --tpm2-pcrs=7 /dev/disk/by-partlabel/archroot
```

- `--tpm2-with-pin=yes` asks for a short PIN instead of the long password. Without a PIN the disk
  unlocks for anyone who can power the machine on, which only makes sense together with Secure Boot
  (see `docs/boot.md`), since PCR 7 measures the Secure Boot state.
- The password slot stays; it is the way in if the TPM refuses (firmware update, changed Secure Boot
  keys). Re-enroll then with `systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto ...`.

## An existing machine

Encrypting in place is possible (`cryptsetup reencrypt --encrypt`) but slow and risky without a
backup. The clean way is a new install with `--encrypt`: the setup comes back from the repository,
the personal data from your backup.
