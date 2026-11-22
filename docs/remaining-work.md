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
- **Session**: autologin on both workstations (LUKS asked for the password already), Danish
  keyboard everywhere including the initrd LUKS prompt, English language, DKK + `DD-MM-YYYY` +
  24h dates, Wayland-only environment variables, PipeWire/rtkit audio.
- **Desktop GPU**: RTX 4090 forced as the primary GPU (no PRIME offload or sync, NVIDIA vendor
  libraries via session variables).
- **Laptop hardware**: AMD microcode, MT7921 wifi + MediaTek Bluetooth, libinput, upower,
  power-profiles-daemon, fwupd; PRIME offload with the real bus IDs (`PCI:5:0:0`, `PCI:1:0:0`).
- **Remote access**: password SSH over `tailscale0` only on the workstations; Tailscale SSH
  (`--ssh`) removed there because it intercepts port 22 and would bypass sshd.
- **CI gates**: `checks.config-eval` now evaluates all three hosts, plus the preflight and runner
  unit tests.
- **Security scaffolding** (unchanged, still valid): nft policy with public HTTP/Cloudflare-only
  ingress, disposable KVM runners, `scripts/preflight.py` secret/permission checks, nix-darwin
  runner config.

## Blocking the server deploy (needs the machine and the secrets)

1. `hosts/desu/local.nix` still has PLACEHOLDER markers: password-hash path, `desu.images.*` not
   pinned by digest, `blockedIPv4` real origin IPs, `ci-token`. `scripts/preflight.py` refuses to
   pass until they are real.
2. Provision `/var/lib/secrets`: `fluxer.env`, `ttml.env`, `cloudflare/origin.pem` + key,
   `tailscale-auth-key`, `ci-token`, `desu-password-hash`, `restic.env`. Services fail closed.
3. Before wiping: inventory, verified off-host backups and a restore rehearsal (README
   "Before wiping the disk").
4. Install, then the restore runbook: Overleaf (Mongo FCV, bind mounts), Fluxer volumes, TTML
   SQLite/spool, SPAR data.
5. **SSH model on the server is undecided**: the repo currently disables OpenSSH there and relies
   on Tailscale SSH (`--ssh`), while the workstations now use password SSH over the tailnet. Pick
   one for the server and make all three match.

## Blocking the workstation installs (needs the machines)

1. Partition + LUKS passphrase + `nixos-install` on each machine (README has the exact commands
   per host). Desktop: the ESP is shared with Windows and must not be reformatted.
2. Accounts need a password hash for password SSH to work (`users.users.desu.hashedPasswordFile`,
   same pattern as `hosts/desu/local.nix`). Without it the account is locked.
3. Laptop: verify `systemctl hibernate` ends in a real resume, not a cold boot.
4. Desktop: after a Windows update, confirm `Windows Boot Manager` is still in the boot order
   (Windows rewrites it; fix with `efibootmgr -o`, do not delete the entry).
5. First boot on each machine per README "Acceptance tests / backups".

## Open by choice

- **Desktop environment / compositor**: not chosen yet. The repo configures none, so the
  workstations boot to a TTY with fish. Autologin and the Wayland variables are already in place
  for whichever lands (Hyprland, Sway, Niri, Plasma 6).
- **Secure Boot**: off everywhere. Needed only for Windows anticheats on the dual-boot desktop;
  Limine's module has the sbctl path when that day comes.
- **Snapshots**: snapper deliberately not configured; restic is the off-site copy and NixOS
  generations handle the system. Adding it later needs an `@snapshots` subvolume and a rollback
  runbook.
- **Server LUKS**: decided against (headless box must come back after a power cut); the reasoning
  is in the README.
- **Hibernation on desktop/server**: not configured (btrfs swap file); laptop only.
- `nixos-generate-config` aborts on the CachyOS installs because `/nix/store` is a btrfs bind
  mount there. It works from a NixOS ISO or with `--root /mnt`; the committed hardware files are
  the reference to diff against either way.
