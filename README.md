# desu.re NixOS configuration

NixOS host configurations: `desu` serves `chat.desu.re`, `overleaf.desu.re` and
`ttml.desu.re`; `laptop` and `desktop` are skeletons for future machines. This is a
migration scaffold, **not a tested production deployment**. `PLACEHOLDER` markers in
`hosts/desu` must be replaced first; `scripts/preflight.py` enforces that.
No server data or secret values belong in this repository.

## Layout and choices

- `hosts/<name>`: one machine per directory. `hosts/README.md` documents adding a host;
  `flake.nix` builds each one through `mkHost` (shared baseline + generated hardware +
  host policy). `hosts/laptop` and `hosts/desktop` stay commented out in the flake until
  their `hardware-configuration.nix` exists.
- `modules/base.nix`: host-independent baseline every NixOS host imports through `mkHost`:
  flakes, `nh` with `NH_FLAKE=/etc/nixos`, fish as the login shell, and Home Manager
  wired to the universal home profile. So `sudo nh os switch` works from any directory.
- Nixpkgs channels: `desu` runs `nixos-26.05` (stable, `channel = "stable"`), while the
  laptop, desktop and disposable CI runners use `nixos-unstable` (the `mkHost` default).
  Home Manager is pinned per channel too (`master` vs `release-26.05`), because an HM
  release only supports its matching nixpkgs release.
- `modules/cachyos.nix` (laptop + desktop only): Chaotic-Nyx (`nyxpkgs-unstable`) with
  `boot.kernelPackages = pkgs.linuxPackages_cachyos` - the CachyOS kernel with kconfig
  parity to upstream (LTO + BORE), plus its binary cache. Other variants are listed in
  the module (`cachyos-lts`, `-hardened`, `-rc`, `-server`) as are the matching
  `nvidia_cachyos`/`zfs_cachyos` packages. The module pulls the unstable-flavoured
  `chaotic.nixosModules.default`, so the stable server must not import it - and does not.
- `home/shared.nix`: the universal user profile (fish, starship, zoxide, eza/bat/dust,
  pfetch, git, `$EDITOR`) imported by `modules/base.nix` on every host, server included.
  `home/files/` holds the dotfiles kept verbatim (starship.toml, ghostty shader).
- `modules/graphical.nix`: what only machines with a display get - `home/graphical.nix`
  (ghostty + shader) and a Nerd Font as the default monospace. The server never imports it.
- `hosts/desu`: x86_64 host, UEFI boot assumption, OAuth-based Tailscale SSH, local settings.
- `modules/edge.nix`: Caddy, Cloudflare-only IPv4/IPv6 web ingress, Origin CA TLS.
- `modules/apps.nix`: rootful Podman OCI containers for Overleaf/TTML, systemd-managed
  Docker Compose for Fluxer. Fluxer's existing health checks and initialization dependency
  graph are retained. No users are added to Docker's root-equivalent group.
- `services/fluxer`: original non-secret configuration; runtime environment file supplies secrets.
- `modules/ci-runners.nix`, `ci/`: implemented disposable KVM controller and guest image.
  `hosts/mac/configuration.nix` is the nix-darwin trusted-runner service. See `ci/README.md`
  for local test results and deployment gates. `local.nix` enables one repository runner;
  replace the placeholder origin IP and token before deployment.
- `modules/backup.nix`: restic backups. Off by default; set `desu.backup.repository` (or a
  credential `environmentFile`) and it stops the writer services, snapshots, then restarts.
- `modules/maintenance.nix`: weekly store GC (on by default, 30d) and opt-in flake
  auto-upgrade (`desu.maintenance.autoUpgrade.enable`, no automatic reboot).
- `docs/runner-plan.md`: CI threat model and authorization requirements.
- `.github/workflows/check.yml`: evaluation-only CI (flake check + cheap gates).
- TTML (`blockgameentity/ttml-fixer`) and SPAR (`O-Blocken/tilbuds-bot`) are **flake inputs**;
  the server imports their `nixosModules.default` and sets only image/cookie options, so
  container/env/volume contracts live in the applications, not duplicated here.

Nixpkgs is locked. Container tags inherited from the export are NOT immutable. Before
production, record currently running image digests and replace tags (including Fluxer)
with digests. Do not combine OS migration with database or application upgrades.

## Before wiping the disk

1. Inventory current `docker ps`, `docker inspect`, Compose project names, image digests,
   volume inspect output, systemd units, cron jobs, firewall rules, DNS, SSH keys, certificates,
   runner registrations and other services. Save the inventory privately off-server.
2. Stop writers for a consistent final backup. Make and test logical PostgreSQL and MongoDB
   dumps and also preserve offline physical data and exact database image versions.
3. Copy **off-server**: Fluxer PostgreSQL/NATS/Meilisearch/SeaweedFS volumes and ALL runtime
   secrets (including VAPID, encryption/auth keys), Overleaf project data AND MongoDB AND Redis,
   TTML env/cookies and caches as desired, SPAR config/database/data, and certificates.
   A project directory or old Fluxer tarball alone is not proof of a recoverable backup.
4. Preserve numeric ownership, modes, ACLs and symlinks. Verify backup hashes and test restore
   into isolated containers with no production integrations. Open representative projects,
   attachments, messages and bot database entries. Store backups on at least two other devices.
5. Keep an Arch recovery image and a written restoration plan. Confirm rescue-console access.
   Only wipe after successful restore rehearsal and inventory sign-off.

## Installation

Boot the NixOS installer, partition/mount deliberately (no destructive disk script is included).
This scaffold assumes UEFI with the Limine bootloader; adapt it if the server uses legacy BIOS.
Edit `local.nix`: provision the password-hash file for local console/sudo authentication,
set application image references, and replace the `PLACEHOLDER` markers. Set timezone and
networking to match your actual provider. Stage new files before flake evaluation.

### Partitioning with btrfs subvolumes

All hosts use one vfat ESP and one btrfs pool split by purpose. The server gets the most
subvolumes because it runs containers; the workstations keep eight:

| Host | Subvolumes |
| --- | --- |
| `desu` (server) | `@ @nix @home @root @srv @cache @log @tmp @docker @lib` |
| `desktop` | `@ @nix @home @root @srv @cache @log @tmp` (dual boot, ESP shared with Windows, all inside LUKS) |
| `laptop` | same eight as the desktop, all inside LUKS (`cryptroot`) |

`@docker` (`/var/lib/docker`) and `@lib` (`/var/lib/containers`) exist only on the server:
they keep container state out of a root rollback, and nothing else runs containers.

#### Server (`hosts/desu/hardware-configuration.nix`)

```console
sgdisk -n1:0:+1G -t1:ef00 -c1:boot /dev/nvme0n1     # ESP
sgdisk -n2:0:0    -t2:8300 -c2:nixos /dev/nvme0n1     # everything else
mkfs.vfat -F32 -n boot /dev/nvme0n1p1
mkfs.btrfs -L nixos /dev/nvme0n1p2

# Subvolumes live at the top level (subvolid=5), never inside a mounted root.
mount -o subvolid=5 /dev/disk/by-label/nixos /mnt
for sv in @ @nix @home @root @srv @cache @log @tmp @docker @lib; do
  btrfs subvolume create /mnt/$sv
done
umount /mnt

OPTS=noatime,compress=zstd:1
mount -o "$OPTS",subvol=@ /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/{nix,home,root,srv,var/{cache,log,tmp},var/lib/{docker,containers},boot}
mount -o "$OPTS",subvol=@nix   /dev/disk/by-label/nixos /mnt/nix
mount -o "$OPTS",subvol=@home  /dev/disk/by-label/nixos /mnt/home
mount -o "$OPTS",subvol=@root  /dev/disk/by-label/nixos /mnt/root
mount -o "$OPTS",subvol=@srv   /dev/disk/by-label/nixos /mnt/srv
mount -o "$OPTS",subvol=@cache /dev/disk/by-label/nixos /mnt/var/cache
mount -o "$OPTS",subvol=@log   /dev/disk/by-label/nixos /mnt/var/log
mount -o "$OPTS",subvol=@tmp   /dev/disk/by-label/nixos /mnt/var/tmp
mount -o noatime,subvol=@docker /dev/disk/by-label/nixos /mnt/var/lib/docker
mount -o noatime,subvol=@lib    /dev/disk/by-label/nixos /mnt/var/lib/containers
mount -o fmask=0077,dmask=0077 /dev/disk/by-label/boot /mnt/boot

nixos-generate-config --root /mnt   # then compare with hosts/desu/hardware-configuration.nix
```

#### Desktop (`hosts/desktop/hardware-configuration.nix`)

This machine dual-boots, so the ESP is **shared with Windows Boot Manager and is not
reformatted**. NixOS only ever owns `nvme0n1p2`; the committed config addresses the ESP by
UUID (`226E-1C60`), which survives a reinstall as long as the partition is kept. Windows
itself lives on the other NVMe and is untouched by any of this.

```console
# Do NOT touch nvme0n1p1 - Windows Boot Manager and Limine both live on it.
cryptsetup luksFormat --label cryptroot /dev/nvme0n1p2   # destroys the old CachyOS root only
cryptsetup open /dev/disk/by-label/cryptroot cryptroot
mkfs.btrfs -L nixos /dev/mapper/cryptroot

mount -o subvolid=5 /dev/mapper/cryptroot /mnt
for sv in @ @nix @home @root @srv @cache @log @tmp; do
  btrfs subvolume create /mnt/$sv
done
umount /mnt

OPTS=noatime,compress=zstd:1
mount -o "$OPTS",subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{nix,home,root,srv,var/{cache,log,tmp},boot}
mount -o "$OPTS",subvol=@nix   /dev/mapper/cryptroot /mnt/nix
mount -o "$OPTS",subvol=@home  /dev/mapper/cryptroot /mnt/home
mount -o "$OPTS",subvol=@root  /dev/mapper/cryptroot /mnt/root
mount -o "$OPTS",subvol=@srv   /dev/mapper/cryptroot /mnt/srv
mount -o "$OPTS",subvol=@cache /dev/mapper/cryptroot /mnt/var/cache
mount -o "$OPTS",subvol=@log   /dev/mapper/cryptroot /mnt/var/log
mount -o "$OPTS",subvol=@tmp   /dev/mapper/cryptroot /mnt/var/tmp
mount -o fmask=0077,dmask=0077 /dev/disk/by-uuid/226E-1C60 /mnt/boot
```

The installer adds a `Limine` firmware entry next to `Windows Boot Manager`; it does not
remove it. `time.hardwareClockInLocalTime = true` is set for this host so Windows' clock does
not jump two hours every time you boot it.

#### Laptop (`hosts/laptop/hardware-configuration.nix`)

Everything except the ESP sits inside LUKS2, and LVM sits inside the LUKS container so the
laptop gets a swap **block device** (needed for hibernation) without a second passphrase.
Labels are used throughout, so a re-partition only has to keep the labels.

```console
sgdisk -n1:0:+1G -t1:ef00 -c1:boot /dev/nvme0n1
sgdisk -n2:0:0    -t2:8309 -c2:cryptroot /dev/nvme0n1
mkfs.vfat -F32 -n boot /dev/nvme0n1p1
cryptsetup luksFormat --label cryptroot /dev/nvme0n1p2
cryptsetup open /dev/disk/by-label/cryptroot cryptroot

# LVM inside LUKS: one volume group, a swap LV for hibernation, a root LV for btrfs.
pvcreate /dev/mapper/cryptroot
vgcreate vg0 /dev/mapper/cryptroot
lvcreate -L 32G -n swap vg0        # MUST be >= RAM + 2 GiB, see "Hibernation" below
lvcreate -l 100%FREE -n root vg0
mkfs.btrfs -L nixos /dev/vg0/root
mkswap /dev/vg0/swap

mount -o subvolid=5 /dev/vg0/root /mnt
for sv in @ @nix @home @root @srv @cache @log @tmp; do
  btrfs subvolume create /mnt/$sv
done
umount /mnt

OPTS=noatime,compress=zstd:1
mount -o "$OPTS",subvol=@ /dev/vg0/root /mnt
mkdir -p /mnt/{nix,home,root,srv,var/{cache,log,tmp},boot}
mount -o "$OPTS",subvol=@nix   /dev/vg0/root /mnt/nix
mount -o "$OPTS",subvol=@home  /dev/vg0/root /mnt/home
mount -o "$OPTS",subvol=@root  /dev/vg0/root /mnt/root
mount -o "$OPTS",subvol=@srv   /dev/vg0/root /mnt/srv
mount -o "$OPTS",subvol=@cache /dev/vg0/root /mnt/var/cache
mount -o "$OPTS",subvol=@log   /dev/vg0/root /mnt/var/log
mount -o "$OPTS",subvol=@tmp   /dev/vg0/root /mnt/var/tmp
mount -o fmask=0077,dmask=0077 /dev/disk/by-label/boot /mnt/boot
swapon /dev/vg0/swap               # so nixos-generate-config sees it
```

`allowDiscards = true` is set on the LUKS device so the weekly `fstrim` reaches the SSD. That
reveals which blocks are free to someone reading the raw device (not their contents); on a
laptop that is the usual tradeoff.

Measured on the actual machine: Ryzen (`AuthenticAMD` -> AMD microcode), Radeon iGPU at
`05:00.0`, RTX 3060 Mobile, MT7921 wifi, MediaTek Bluetooth, **13 GiB usable RAM** (so the
32 GiB swap LV clears the RAM + 2 GiB rule for hibernation). The existing 4 GiB ESP is reused -
`mkfs.vfat -F32 -n boot /dev/nvme0n1p1` relabels it for the by-label mount - and the current LUKS
partition is exactly where the new one goes; only the LVM layer inside it is new.

`hosts/laptop/configuration.nix` also enables the hardware that was missing entirely:
NetworkManager (`mt7921e` wifi, `r8169` ethernet), Bluetooth, libinput, upower and
power-profiles-daemon (not TLP - the two conflict).

#### Why these boundaries

`@nix` keeps the store out of a root rollback, `@srv` holds mutable service data (`/srv/overleaf`,
`/srv/spar`), and `@log`/`@cache`/`@tmp` keep churn and cache away from everything else.
`/nix` and `/var/log` carry `neededForBoot = true` - without it they would be mounted in
stage 2, after the store and journald are already in use on the root subvolume.

Compression stays `zstd:1` and TRIM is a weekly `fstrim` timer (`modules/btrfs.nix`), not the
`discard` mount option. Monthly scrub is enabled there too: one mountpoint per filesystem,
since scrub runs on devices and every subvolume shares them. `overlay2` remains Docker's
storage driver on btrfs (supported as an overlayfs lower layer since kernel 4.15) - do not
add `nodatacow` to `@docker` to "fix" it.

`nixos-generate-config` does not know about `neededForBoot`, the subvolume set or `compress=`:
review the generated file against the committed one instead of overwriting it.

### Swap and memory: zswap, never zram

`modules/memory.nix` is imported by every host and encodes two rules:

- **zswap only.** Compressed page cache in front of a real swap device, `zstd`, pool capped
  at 25% of RAM, shrinker on. `zramSwap.enable = false` is a plain assignment, not a default,
  so a host that tries to turn zram on fails evaluation instead of stacking two compressors.
- **One swap file on the root subvolume**, `/swap`, created by the NixOS swap unit with
  `btrfs filesystem mkswapfile` (NOCOW, uncompressed - compulsory for swap on btrfs).
  Sizes: desktop 64 GiB, server 32 GiB, via `desu.memory.swapSizeMiB`. Changing the number
  recreates the file on the next switch (`resume_offset` would change with it - see below,
  which is exactly why the laptop does not use a swap file).
  The laptop sets `desu.memory.swapFile = null` and swaps on its `vg0/swap` LV instead.

`vm.swappiness = 100` and `vm.page-cluster = 0`: with zswap, swapped pages are still in RAM
(compressed), so spilling early is cheap and the file only holds the overflow.

### Hibernation (laptop only)

The laptop hibernates with `systemctl hibernate`; the desktop and server do not (`/swap` is a
btrfs swap file there). Two hard requirements:

1. **The swap device must be a block device.** Hibernating into a btrfs swap *file* needs
   `resume_offset`, a physical offset that changes every time the file is recreated - fragile.
   Hence `vg0/swap`.
2. **Swap must be at least RAM + a couple of GiB**, or `systemctl hibernate` refuses with
   "Not enough swap space". The 32 GiB LV above assumes a 16 GiB laptop; resize with
   `lvextend`/`lvresize -L` if the machine has more RAM.

Resume works with LUKS because stage 1 unlocks `cryptroot` and activates `vg0` before
`systemd-hibernate-resume` reads `resume=/dev/vg0/swap`. zswap sits in front of normal swap
pages, not in front of the hibernation image (swsusp writes that directly to the block
device), so the compression pool does not have to be drained first.

Suspend-to-RAM works on all three hosts without touching any of this.

### Snapshots vs NixOS generations

Two different rollback mechanisms; only the second is enabled anywhere.

| | NixOS generation | btrfs snapshot |
| --- | --- | --- |
| Covers | system profile, kernel, initrd, services config | every file on that subvolume, including `/var/lib`, `/srv`, `/home` |
| Granularity | per `nixos-rebuild` | whenever a snapshot is taken |
| Undoes | a bad config or package change | a bad *data* change: failed DB upgrade, deleted files, corrupted container state |
| Boot entry | yes, `nh os rollback` or an older Limine entry | only if you add entries yourself |

A NixOS rollback does **not** restore `/var/lib/docker`, the Overleaf Mongo data or anything
else under `/srv`: those are mutable data, not store paths. That is the gap `services.snapper`
(or the existing restic backups in `modules/backup.nix`) covers. Snapshots are not backups
either - they share the disk - so restic stays the off-site copy. Enabling snapper later needs
one more subvolume (`@snapshots`, mounted at `/.snapshots`) and its own rollback runbook;
do not mount it on top of an existing layout without redoing this partitioning.

```console
# Keep the checkout where NH_FLAKE points (modules/base.nix): /etc/nixos.
git clone https://github.com/blockgameentity/nixos-config.git /etc/nixos
cd /etc/nixos
git add hosts/desu
nix flake check
nix build .#nixosConfigurations.desu.config.system.build.toplevel
sudo nixos-install --flake .#desu
```

After first boot, rebuilds use `nh` (installed by `modules/base.nix`):

```console
sudo nh os switch           # build and activate /etc/nixos for this host
sudo nh os boot             # same, but only for the next boot
nh search <query>           # package search; queries search.nixos.org, not nix-index
```

`nh` derives the host from the flake, so `nh os switch` activates whichever
`nixosConfigurations.<hostname>` matches the machine. Pass a path explicitly
(`nh os switch /some/other/checkout`) or override `NH_OS_FLAKE` per command.

### Encryption (LUKS): the verdict per machine

Decision taken, so it does not get re-litigated every time a disk is touched:

| Host | LUKS | Why |
| --- | --- | --- |
| laptop | **yes** (configured) | Leaves the house. Full disk encryption is the difference between "stolen laptop" and "someone reading `/home/desu/.ssh` and every saved session". |
| desktop | **yes** (configured) | Stays at home, but it holds the same secrets plus a Windows partition. AES-NI on a 14700K makes the I/O overhead a rounding error, and deciding later means reformatting. |
| server | **no** | A headless box that must come back after a power cut cannot ask for a passphrase. Adding LUKS there means initrd SSH (`boot.initrd.network.ssh`) or TPM2 unlock, and with Secure Boot off a TPM2-bound key can be replayed by booting a custom kernel - so the protection is thin for the operational cost. |

What LUKS does not do: it protects data at rest, not a running system. Anyone with five
minutes and a USB stick reads an unlocked machine, and a stolen *server* is compromised even
with FDE unless it was powered off. So the server compensates differently: secrets under
`/var/lib/secrets` are rotatable (Tailscale key, Cloudflare origin cert, restic credentials,
CI token), restic sends encrypted backups off-site, and `swapDevices.*.randomEncryption`
can be turned on to keep plaintext out of the swap file if you want that extra step.

LUKS is unrelated to the Windows anticheat/Secure Boot question: Linux FDE does not touch the
firmware, so it neither enables nor breaks Secure Boot for Windows.

## Bootloader (Limine)

Every NixOS host enables `boot.loader.limine` (`hosts/{desu,desktop,laptop}/configuration.nix`);
`boot.loader.systemd-boot` is not enabled anywhere. Limine loads kernels and initrds directly
from `/boot` and keeps its menu in `/boot/limine.conf`, so `maxGenerations = 10` only bounds
how many generations appear in the menu - there are no per-generation EFI binaries to pile up.
`boot.loader.efi.canTouchEfiVariables` stays `true` so the installer writes the `Boot####`
entry itself. The boot entry editor is left off: an editable command line allows
`init=/bin/sh`, i.e. root without the disk password.

Switching a machine that currently boots systemd-boot:

```console
sudo nh os boot          # install Limine as the active loader for the next boot
sudo reboot              # boot it before touching anything else; keep rescue media ready
# after confirming the menu and a successful boot:
sudo rm -rf /boot/EFI/systemd /boot/loader   # stale systemd-boot instance and entries
sudo efibootmgr -v                           # find the leftover "Linux Boot Manager" entry
sudo efibootmgr -b <NNNN> -B                 # delete it, or keep it as a fallback
sudo nh os switch        # make this generation the running one
```

`nixos-install --flake .#desu` on a fresh disk does this in one step and needs no cleanup.
Rebuilds after that never touch the firmware entry again unless the EFI partition is replaced.

On the dual-boot desktop, **never delete the `Windows Boot Manager` entry** while cleaning
the list, and never `rm -rf` anything on the ESP beyond `EFI/systemd` and `loader`. Windows
and Limine share that partition; the Linux loader lives in `EFI/limine`, Windows in
`EFI/Microsoft`. If Windows disappears from the boot menu after a Windows update, it is
Windows rewriting the boot order, not this repo - fix it with `efibootmgr -o`.

## Keyboard, language, currency

| What | Setting | Where |
| --- | --- | --- |
| Keyboard, TTYs and the LUKS prompt | `console.keyMap = "dk"` + `console.earlySetup = true` | `modules/base.nix` |
| Keyboard, X11 / GTK / Qt / Wayland | `services.xserver.xkb.layout = "dk"`, `XKB_DEFAULT_LAYOUT=dk` | `modules/graphical.nix` |
| Language | `i18n.defaultLocale = "en_US.UTF-8"` | `modules/base.nix` |
| Currency | `LC_MONETARY = "da_DK.UTF-8"` (DKK) | `modules/base.nix` |
| Dates and clock | `LC_TIME = "da_DK.UTF-8"` -> `DD-MM-YYYY`, 24h `HH:MM` | `modules/base.nix` |
| Units / paper | `LC_MEASUREMENT`/`LC_PAPER = da_DK` (metric, A4) | `modules/base.nix` |
| Time zone | `Europe/Copenhagen` | each `hosts/<name>/configuration.nix` |

`console.earlySetup` is the part that is easy to miss: without it the keymap only applies once
stage 2 starts, so the **LUKS passphrase would be typed on a US layout** while everything after
it is Danish. `LC_NUMERIC` and `LC_COLLATE` stay English on purpose: a comma decimal separator
breaks more scripts than it fixes by hand. `LC_TIME=da_DK` is the only glibc locale that formats
exactly as wanted (`d_fmt "%d-%m-%Y"`, `t_fmt "%T"`, no AM/PM) - en_GB gives `31//12//24`,
en_DK gives ISO, nl_NL a two-digit year. Side effect: weekday/month names in date output are
Danish while the program's own text stays English.

Both workstations are **Wayland-only**: `NIXOS_OZONE_WL=1` and `MOZ_ENABLE_WAYLAND=1` stop
Chromium/Electron apps and Firefox from silently falling back to XWayland, and the keyboard layout
is exported as `XKB_DEFAULT_LAYOUT=dk` for compositors that do not read the xkb option. The
bootloader menu itself uses the firmware's keyboard handling and cannot be changed from NixOS.

## Login: LUKS asks once

The desktop and laptop import `modules/graphical.nix`, which sets
`services.getty.autologinUser` and `services.displayManager.autoLogin` for `desu`. The disk
passphrase is the only thing typed at boot; the console (and any display manager added later)
logs straight in.

That is a deliberate tradeoff: whoever powers the machine on and knows the LUKS passphrase
gets a logged-in session. The server is unaffected - no autologin, no graphical module.

Note that this repo currently configures **no display manager and no compositor** for the
graphical hosts: they boot to a TTY with fish. That is a deliberate open item, not an omission -
the desktop environment / compositor choice (Hyprland, Sway, Niri, Plasma 6) is still being
decided. `services.displayManager.autoLogin` and the Wayland variables above are already in
place so that whichever option lands inherits autologin and the Danish layout instead of
re-introducing a second password prompt.

## Remote access

The workstations run `sshd` with password authentication, reachable **only** over `tailscale0`:
`networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ]`, nothing opened on the LAN
or WAN. Tailscale SSH (`tailscale up --ssh`) is removed there on purpose - it intercepts port 22
on the tailnet and authenticates by tailnet identity, which would bypass sshd and the password
actually in use.

The account needs a password hash for this to work at all:
`users.users.desu.hashedPasswordFile = "/var/lib/secrets/desu-password-hash";` (the pattern
`hosts/desu/local.nix` uses). Without it the account is locked and password logins fail even
though sshd accepts them.

The server still uses the opposite model (OpenSSH disabled, Tailscale SSH with `--ssh`); that is
an open decision recorded in `docs/remaining-work.md`.

## Audio

`modules/graphical.nix` enables PipeWire with the ALSA and PulseAudio compatibility layers
(`alsa.support32Bit` for Steam titles) plus `security.rtkit` for realtime scheduling. The server
imports neither, so it stays silent and minimal.

## Home profile (shell, prompt, terminal)

Home Manager is a NixOS module (`modules/base.nix`), so the same user profile is
built for every host from one place:

| Profile | File | Hosts |
| --- | --- | --- |
| universal | `home/shared.nix` | server, laptop, desktop |
| graphical | `home/graphical.nix` (via `modules/graphical.nix`) | laptop, desktop only |
| desktop | `home/desktop.nix` (via `modules/desktop.nix`) | desktop only (CUDA, NVIDIA, alcom, Unity Hub) |

The universal profile carries fish (login shell), `starship` with the original
`~/.config/starship.toml`, `zoxide`, `fzf`, eza/bat/dust aliases, `pfetch-rs`
instead of catnap, `helix` (`hx`, `$EDITOR`/`$VISUAL`, Gruvbox Dark Hard) as the
only terminal editor, `delta` as the git pager, `lazygit` (`lg`), `direnv` with
`nix-direnv`, `btop`, git identity plus the `gh auth` credential helper, and the
`cargo`/`ruff`/`bun`/`uv`/`go` toolchains.

Cargo is configured for speed on every host (`~/.cargo/config.toml`):
`sccache` as `rustc-wrapper` and `mold` as the linker (`-fuse-ld=mold`).

SSH aliases live in the same profile (`programs.ssh.settings`): `github`/`gist`
map to `git@` endpoints, and `Host *` sets keepalives, agent key loading and
ControlMaster multiplexing. No key material or machine addresses are here, and
`~/.ssh/config` is generated - an existing file is moved to `config.hm-backup`.

CLI tools shared by every host: `act pandoc adb scrcpy croc dog imagemagick
ipinfo iperf3 fend yazi yt-dlp typst zstd kondo ffmpeg radare2` plus the basics
(`eza bat dust ripgrep fd jq pfetch-rs`). Tailscale is enabled by
`modules/base.nix` for every host.

The graphical profile adds ghostty (Gruvbox Dark Hard, bar cursor, `cursor_warp`
shader), JetBrains Mono in its Nerd Font variant as the default monospace,
Noto Color Emoji, and the both-machines applications: firefox, libreoffice,
filezilla, obsidian, bitwarden, celluloid, imhex, signal, insomnia, qbittorrent,
prismlauncher, ayugram, obs-studio, ktailctl (Tailscale GUI), kalker,
qalculate-gtk and zed. Steam and the sched_ext scheduler live in
`modules/graphical.nix` because both are NixOS services rather than packages:
`programs.steam.enable`, and `services.scx-loader` with `scx_bpfland` as the
default scheduler. `czkawka` is graphical-only even though it also ships
`czkawka_cli`, so the server does not pull a GTK closure for it.

On the laptop, Steam and Obsidian are the only unfree packages and are allowed
through `nixpkgs.config.allowUnfreePredicate` for those two names.

The desktop adds `modules/desktop.nix` / `home/desktop.nix` on top: CUDA
(`cudaSupport = true`, `cudatoolkit`), the NVIDIA driver (open kernel modules,
modesetting), and alcom + Unity Hub. Because CUDA ships a family of EULA
packages (cccl, cuDNN, cuBLAS, NCCL) whose names move between releases, the
desktop allows unfree packages outright instead of enumerating them.
**Building the desktop configuration downloads several GB of CUDA closure.**

The server imports `modules/base.nix` only: it gets the shell, prompt, editor,
git, toolchains and CLI tools, but no terminal emulator, font, GUI app or
gaming/desktop package. It runs `nixos-26.05` (stable), everything else runs
`nixos-unstable`.

Dotfiles that are easier to read as-is (the starship TOML, the ghostty shader)
are copied verbatim under `home/files/` and referenced with `.source` instead of
being translated into a Nix attrset. To adopt another dotfile, copy it into
`home/files/` and add an `xdg.configFile` entry; a pre-existing file at the same
path is moved to `<name>.hm-backup` on first activation.

Provision runtime secrets under `/mnt/var/lib/secrets` before first boot, or under
`/var/lib/secrets` on the installed host. Root-only files, not Nix paths/strings containing
secret values. Missing secrets intentionally make affected services fail closed.

The storage/reuse/rotation policy for all of this is in `docs/secrets.md`; the passwords
do not share a value and the ones that are never typed do not live on any machine.

`desu-password-hash` is required on **every** host, not just the server: all three set
`users.users.desu.hashedPasswordFile`, and `sudo` has nothing to check without it (the
workstations' autologin hides that until the first `sudo`, or the first SSH login). Generate one
hash and reuse it, or use a different password per machine:

```console
mkpasswd -m yescrypt > /mnt/var/lib/secrets/desu-password-hash
chmod 600 /mnt/var/lib/secrets/desu-password-hash   # root:root, nothing else readable
```

Activation fails if the option points at a missing file, so create it while the target is still
mounted at `/mnt`.

- `fluxer.env`: recover the ORIGINAL Fluxer `.env`, do not regenerate its keys.
  Set `FLUXER_DOMAIN=chat.desu.re`, `FLUXER_CADDY_SITE_ADDRESS=:80`, and keep the original
  image version. `LIVEKIT_API_KEY` must match `webhook.api_key` in `livekit.yaml` (currently
  `fluxer`), or update that non-secret identifier. The compose file documents required variables.
- `ttml.env`: original `ttml-fixer/backend/.env` (model tuning, `TTML_FIXER_PROFILE=homelab-cpu`).
  Cookie exports are optional and worker-only; if present, `youtube-cookies.txt` is mounted
  read-only only when the service sets it, otherwise remove the mount from `modules/apps.nix`.
- `youtube-cookies.txt`: original cookie file, root-readable.
- `desu-password-hash`: a password HASH for the administrator, root-readable.
- `cloudflare/origin.pem` and `cloudflare/origin-key.pem`: Origin CA certificate covering all
  three hostnames and its key. This subdirectory must be traversable by Caddy (root:caddy 0750),
  files root:caddy 0640. The parent `/var/lib/secrets` is root:caddy 0710 (traverse only
  for Caddy). All OTHER secret files must be root:root 0600; Caddy must not read them.
- `tailscale-auth-key`: one-off Tailscale auth key for a persistent, preauthorized server
  node, root:root 0600. Use appropriate tailnet ACL/tagging and permit Tailscale SSH to
  the `desu` account. Tailscale `--ssh` handles OAuth; OpenSSH is completely disabled.
- `ci-token`: repository-scoped fine-grained GitHub token with Administration:write for
  runner management, root-readable only. `local.nix` currently enables ExamWatcher/desktop.
  Replace `blockedIPv4` with the server's real origin IP(s) before deploying. Read `ci/README.md`.
- `restic.env` (or `restic-password`): repository URL/key and, for S3/R2, the credentials.
  Only needed once `desu.backup.enable = true`.

## Restore and start

Keep services stopped until restores finish. Fluxer keeps project name `fluxer`, hence
named volumes like `fluxer_postgres-data`. Verify original names using the old inventory;
do not assume they match. Restore to the NEW volumes, never copy Docker's whole runtime
storage directory between installations. Compose config files reside in the read-only Nix store.

Overleaf bind mounts move to `/srv/overleaf/{data,mongo,redis}`. Preserve ownership from the
source containers; the initial directory permissions are not a replacement for correct restored
UIDs. Restore Mongo using the same major version. Its replica set must be named `overleaf`,
with reachable member `mongo:27017`. Startup initializes only an uninitialized replica set and
waits for primary; it does NOT rewrite an existing replica set. Inspect/reconfigure deliberately
if the old member address differs. After restore, validate `rs.status()` and Overleaf login.

TTML backend: build the current `ttml-fixer/backend/Dockerfile` on a build machine
(`nix run . -- TAG` in the upstream repo's flake), publish by digest, or
`podman save`/`podman load` into root's store. Set `desu.images.ttml` accordingly; NixOS
does not build the image. The image runs as **UID 10001**, which is why the module creates
`/var/lib/ttml-fixer` and `/var/cache/ttml-fixer/{results,models}` with that ownership.

TTML now runs as **two containers** matching its compose contract: an enqueue-only
`ttml-fixer-api` on `127.0.0.1:8000` (1 GiB / 1 CPU) and `ttml-fixer-worker` (24 GiB /
8 CPU) that owns model download and inference. They share the SQLite job store, spool and
result cache; only the worker mounts the model cache and the optional cookies. Queue
state, results and tokens live in `/var/lib/ttml-fixer`; **back that up with the service
stopped**, or the SQLite DB and spool can be inconsistent.

Because `ttml.desu.re` is public behind Caddy and Cloudflare, set in `ttml.env`:
`TTML_FIXER_PUBLIC_INSTANCE=true` with an explicit HTTPS `TTML_FIXER_CORS_ORIGINS`. The
module already sets `TTML_FIXER_TRUSTED_PROXY_CIDRS=127.0.0.1/32` (Caddy is local) and the
loopback bind, so do not widen the trust to `0.0.0.0/0`. Before starting the API, provision
a token inside the container:

```console
podman exec ttml-fixer-api python -m ttml_fixer.admin \
  --api-token-db /var/lib/ttml-fixer/state/api-tokens.sqlite3 \
  token-provision --owner operator-name
```

Save the one-time token output; only its digest is stored. Startup fails closed if public
mode has no active token or invalid CORS/proxy settings. Cookie-based YouTube access is
optional and mounted read-only into the worker only; without it downloads still work for
non-authenticated requests when `TTML_FIXER_ENABLE_DOWNLOAD` is set. No GPU is configured.

MongoDB and Redis are now `mongo:7.0` and `redis:7.4-alpine` (`desu.images.mongo` /
`desu.images.redis`) instead of upstream's 6.0/6.2. Overleaf's node driver (mongodb 6.12)
and ioredis 4.27 support them, and the upgrade paths were tested with real containers —
see `docs/overleaf-upgrade.md` for the FCV step, the dump-first rule, and the fact that
MongoDB 7.0 has **no in-place downgrade**.

The existing Overleaf image enables shell escape: keep registration restricted and treat
LaTeX compilation as untrusted execution inside the application container. This setup is
not a safe public multi-tenant compilation sandbox.

## Cloudflare / security

Use orange-cloud DNS and **Full (strict)** TLS. Caddy only serves HTTPS using the provided
Origin CA certificate; there is no ACME challenge requirement. Port 80 redirects to HTTPS.
Cloudflare ranges are checked at the host firewall and Caddy's immediate-peer matcher.
Do not add global firewall allows for 80/443. UDP/443 is not enabled.
Caddy replaces forwarded client IP headers with CF-Connecting-IP only for accepted peers.

Sources: https://www.cloudflare.com/ips-v4 and https://www.cloudflare.com/ips-v6.
Review range changes manually before deployment; no network fetch mutates firewall rules at boot.
Cloudflare source-IP allowlisting blocks ordinary direct-origin bypass, but is NOT proof that
traffic came through YOUR Cloudflare zone. For that stronger property, add zone-specific
Authenticated Origin Pulls (custom client certificate), or use a Cloudflare Tunnel.
Shared Cloudflare AOP certificates alone are not zone-specific authentication.

Web backends bind only loopback; databases have no published ports. Docker publication can
bypass host INPUT firewall rules: never change these to 0.0.0.0. Verify actual exposure remotely.
Fluxer voice requires direct TCP 7881 / UDP 7882. These are deliberately public, not Cloudflare-only.
Check LiveKit's advertised external IP, NAT forwarding and real two-client calls. Tailscale
SSH uses OAuth and is allowed only on tailscale0; no OpenSSH daemon or SSH password login
is enabled. The local password is only for console/sudo authentication. Provision the auth
key before first boot for headless enrollment. Confirm Tailscale SSH from a second device
before disconnecting rescue access. CI already blocks 100.64.0.0/10.

## Acceptance tests / backups

- `nixos-rebuild build --flake .#desu` (or `sudo nh os test`, then `sudo nh os switch`), then
  test in a restore VM before switching production.
- `systemctl --failed`, `journalctl -u fluxer -u caddy`, container health and Mongo primary.
- Off-network direct origin HTTP/HTTPS (IPv4 AND IPv6) denied; Cloudflare URLs work.
- WebSocket chat/gateway, upload/download, voice, Overleaf editing and PDF compilation,
  TTML health and one complete transcription, bot state if enabled.
- Confirm ports 1337/8000/42295 and all DB ports are inaccessible remotely.
- Reboot and repeat. Confirm restored data survives container restart.
- Backups: `systemctl list-timers restic-backups-desu.timer`, `systemctl start
  restic-backups-desu.service`, then perform an actual `restic restore` drill. Verify the
  configured Docker volume names first with `docker volume ls`. NixOS rollback does NOT
  roll back databases or container images.

## SPAR image

SPAR is consumed as the `spar` flake input (`github:O-Blocken/tilbuds-bot`). Its service is
**disabled while `desu.images.spar = null`**; set it to a published digest to start it.
Restore data/config.toml to `/srv/spar`, and env to `/var/lib/secrets/spar.env`.
The bot flake wraps the existing Dockerfile; it is not a native/reproducible PaddleOCR package.
Build it from a clean Git checkout, never from an extracted tree: Nix can copy untracked
runtime files/secrets into its world-readable store for non-Git flakes.
