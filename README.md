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
This scaffold assumes UEFI/systemd-boot; adapt it if the server uses legacy BIOS. Generate
`hardware-configuration.nix` using `nixos-generate-config --root /mnt` and replace the placeholder.
Edit `local.nix`: provision the password-hash file for local console/sudo authentication,
set application image references, and replace the `PLACEHOLDER` markers. Set timezone and
networking to match your actual provider. Stage new files before flake evaluation.

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
