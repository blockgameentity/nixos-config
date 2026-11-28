# What remains

Written against the current repository state: three NixOS hosts (server `desu`, workstations
`desktop` + `laptop`) on Limine with btrfs subvolumes, zswap, and LUKS on both workstations.

## Done

- **Bootloader**: Limine on all three hosts (`maxGenerations = 10`), systemd-boot removed. The
  migration/cleanup path for a machine that still boots systemd-boot is in the README.
- **Disk layouts**: server `@ @nix @home @root @srv @cache @log @tmp @docker @lib`; desktop and
  laptop the same set without `@docker`/`@lib`. LUKS2 on both workstations, with LVM only on the
  laptop so it gets a swap block device for hibernation. Mount tables are committed per host and
  are meant to be diffed against `nixos-generate-config`, not replaced by it.
- **Memory**: `modules/memory.nix` - zswap (zstd, 25% pool, shrinker), zram banned as a hard
  assignment, swap file per host except the laptop's swap LV. Sizes: desktop 64 GiB, server
  32 GiB, laptop 32 GiB LV.
- **Session**: Ly -> Wayfire on both workstations with the account password at the greeter (no
  autologin: it is what lets `pam_gnome_keyring` unlock the login keyring), Danish
  keyboard everywhere including the initrd LUKS prompt, English language, DKK + `DD-MM-YYYY` +
  24h dates, Wayland-only environment variables, PipeWire/rtkit audio.
- **Desktop GPU**: RTX 4090 forced as the primary GPU (no PRIME offload or sync, NVIDIA vendor
  libraries via session variables).
- **Laptop hardware**: AMD microcode, MT7921 wifi + MediaTek Bluetooth, libinput, upower,
  power-profiles-daemon, fwupd; PRIME offload with the real bus IDs (`PCI:5:0:0`, `PCI:1:0:0`).
- **Remote access**: OpenSSH servers are disabled on the workstations; their clients remain.
  The server accepts only Tailscale SSH, subject to tailnet policy.
- **CI gates**: `checks.config-eval` now evaluates all three hosts, plus the preflight and runner
  unit tests.
- **Security scaffolding** (unchanged, still valid): nft policy with public HTTP/Cloudflare-only
  ingress, disposable KVM runners, `scripts/preflight.py` secret/permission checks, nix-darwin
  runner config.

## Server migration gates

- TTML and SPAR image references are pinned in `hosts/desu/local.nix`; no placeholder remains.
- Four CI pools use separate root-only tokens. Organization groups must explicitly exclude public
  repositories and untrusted fork workflows. Public `nixos-config` checks use GitHub-hosted runners.
- Provision the files required by `scripts/preflight.py`, outside Git. Automatic restic backups are
  disabled, so `restic.env` is not required and there is no automatic server backup.
- Verify a fresh quiesced off-host Overleaf/SPAR backup immediately before the destructive install.
  Fluxer starts fresh; do not restore its old database or volumes. Do not migrate the reseed identity
  or write its old/new endpoint ID into this public repository.
- Workstations have no SSH server; only the server accepts Tailscale SSH. Verify that from a second
  device before removing rescue access. The server's Intel/NVMe/Realtek hardware report matches the
  committed configuration; the final NixOS target still needs a post-partition hardware diff.
- Four CI VMs use 8 GiB each on the 48 GiB host. Build the complete server closure, pass preflight,
  run the acceptance checks, and repeat them after reboot.
- The private cheesetool flake needs a narrow read-only token on trusted local and CI builds. Public
  untrusted fork builds must not receive that token.

## Blocking the workstation installs (needs the machines)

1. Partition + LUKS passphrase + `nixos-install` on each machine (README has the exact commands
   per host). Desktop: the ESP is shared with Windows and must not be reformatted.
2. Accounts need a password hash for the greeter and sudo to work (`users.users.desu.hashedPasswordFile`,
   same pattern as `hosts/desu/local.nix`). Without it the account is locked. It is the **only**
   secret either workstation needs: write it to `/mnt/var/lib/secrets/desu-password-hash`
   (root:root 0600) while the target is still mounted at `/mnt`.
3. Commit (or at least `git add`) before installing. The flake copies the git tree, not the
   working directory: anything ignored by `.gitignore` never reaches the store, and a clean
   clone obviously has no uncommitted work. A half-committed `services/` or `hosts/` change is
   the easiest way to install something different from what you reviewed.
4. Laptop: verify `systemctl hibernate` ends in a real resume, not a cold boot.
5. Desktop: after a Windows update, confirm `Windows Boot Manager` is still in the boot order
   (Windows rewrites it; fix with `efibootmgr -o`, do not delete the entry).
6. First boot on each machine per README "Acceptance tests / backups", and walk
   `docs/wayfire.md`'s checklist once on real hardware: the session, ironbar, the OLED mode
   staging, voice/screenshare and one Steam launch.

## Open by choice

- **Desktop environment / compositor**: Wayfire 0.11, packaged in `packages/wayfire.nix` and
  imported by both workstations. nixpkgs still ships 0.10.1, so the pin and its upstream patch
  are local; `docs/wayfire.md` carries the defect list, the display-ownership model and the
  acceptance checklist. Plasma is no longer configured anywhere.
- **Secure Boot**: off everywhere. Needed only for Windows anticheats on the dual-boot desktop;
  Limine's module has the sbctl path when that day comes.
- **Backups**: automatic restic backups are currently disabled; the migration archive is not
  a continuing backup policy. NixOS generations do not protect application data. Choose a local,
  SFTP, or other destination before enabling `desu.backup`.
- **Server LUKS**: decided against (headless box must come back after a power cut); the reasoning
  is in the README.
- **Hibernation on desktop/server**: not configured (btrfs swap file); laptop only.
- `nixos-generate-config` aborts on the CachyOS installs because `/nix/store` is a btrfs bind
  mount there. It works from a NixOS ISO or with `--root /mnt`; the committed hardware files are
  the reference to diff against either way.
