# desu.re NixOS configuration

One flake, three machines:

| Host | Channel | Role | Status |
| --- | --- | --- | --- |
| `desu` | `nixos-26.05` (stable) | Always-on server: `chat.desu.re` (Fluxer), `overleaf.desu.re`, `ttml.desu.re`, the cheesetool reseed node, SPAR bot, disposable CI runners | Being migrated from an Arch + Docker Compose box (see [Migrating the old server](#migrating-the-old-server)). Not yet a tested production deployment. |
| `desktop` | `nixos-unstable` | Workstation, dual boot with Windows, RTX 4090, Wayfire | Installed; this repository is its `/etc/nixos`. |
| `laptop` | `nixos-unstable` | Workstation, LUKS + LVM, hibernation, PRIME offload | See `docs/remaining-work.md`. |

Rules for this repository, because it is **public**:

- **No secret values and no server data.** Git holds only *paths* to secrets
  (`/var/lib/secrets/...`). `.gitignore` blocks `*.env`, `*.pem`, `*.key`, `secrets/`.
- **The server's public origin IP is a secret too.** It lives in `/var/lib/secrets/ci-blocked-ipv4`
  and is read at runtime; it must not appear in any file here (`scripts/preflight.py` fails if
  `hosts/desu/local.nix` contains an IP address).
- `PLACEHOLDER` markers in `hosts/desu` must be replaced before the server install;
  `scripts/preflight.py` enforces that.

## Contents

1. [Repository layout](#repository-layout)
2. [Design choices](#design-choices)
3. [The server (`desu`)](#the-server-desu)
4. [Secrets](#secrets)
5. [Migrating the old server](#migrating-the-old-server)
6. [Installing a machine](#installing-a-machine)
7. [Storage: partitioning, swap, hibernation, snapshots, encryption](#storage)
8. [Bootloader (Limine)](#bootloader-limine)
9. [Workstation details](#workstation-details)
10. [Day-to-day operations](#day-to-day-operations)
11. [Acceptance tests](#acceptance-tests)

## Repository layout

```
flake.nix                  inputs, mkHost, hosts, CI checks
hosts/<name>/              one machine per directory (hosts/README.md: adding a host)
  desu/local.nix           deployment values for the server (digests, secret paths; no secrets)
modules/                   base, btrfs, memory (every host); graphical, desktop, wayfire, cachyos (workstations)
                           edge, apps, backup, ci-runners, maintenance (server)
home/                      Home Manager profiles: shared, graphical, desktop, wayfire (+ files/ dotfiles)
services/fluxer/           upstream Fluxer compose bundle, vendored verbatim
packages/                  local packages: limusic, wayfire 0.11, invokeai (own flake)
patches/                   ironbar and wayfire patches
ci/                        disposable KVM runner controller, guest image, firewall tests
scripts/                   preflight.py (install gate), publish-image.sh (GHCR images)
docs/                      see the table below
.github/workflows/         check.yml: evaluation-only CI
```

| Document | What it covers |
| --- | --- |
| `docs/secrets.md` | Storage, reuse and rotation policy for every secret; the one-passphrase decision |
| `docs/fluxer.md` | Vendored Fluxer bundle: provenance, digests, env keys, upgrade and restore order |
| `docs/overleaf-upgrade.md` | Mongo 6.0 to 7.0 and Redis 6.2 to 7.4: dump-first rule, no downgrade |
| `docs/ttml-clients.md` | Who may use `ttml.desu.re`, bearer tokens, CORS, creating the first token |
| `docs/cheesetool-reseed.md` | The reseed node: fresh identity, operator API, the private flake input |
| `docs/runner-plan.md`, `ci/README.md` | CI threat model, authorization, enabling the runners |
| `docs/wayfire.md` | The Wayfire session for both workstations |
| `docs/remaining-work.md` | What is done and what still blocks each machine |
| `docs/validation.md`, `docs/api-runner-inventory.md` | Recorded validation runs and runner inventory |

## Design choices

- **`mkHost`** (`flake.nix`) builds every host from a shared baseline (`modules/base.nix`),
  the committed `hardware-configuration.nix` and the host policy. `modules/base.nix` gives every
  host flakes, `nh` with `NH_FLAKE=/etc/nixos`, fish as the login shell, Tailscale, a Danish
  keymap (also in the initrd) and Home Manager wired to the universal profile.
  `nh os switch` works from any directory. Run it as your user, **not** with `sudo`: `nh` calls
  sudo itself and refuses to run as root.
- **Channels.** The server runs `nixos-26.05` and `home-manager` `release-26.05`; everything else
  runs `nixos-unstable` and Home Manager `master`. An HM release only supports its matching
  nixpkgs release. The CachyOS kernel (`modules/cachyos.nix`, Chaotic-Nyx) is workstation-only:
  its module is the unstable flavour, so the stable server must not import it and does not.
- **Application flakes own their contract.** TTML (`github:blockgameentity/ttml-fixer`) and SPAR
  (`github:O-Blocken/tilbuds-bot`) export `nixosModules.default`; the server sets only image,
  cookie and a few tuning options, so container/env/volume definitions live in the applications,
  not here. The cheesetool reseed node (`github:blockgameentity/cheesetool`,
  `nixosModules.reseed`) is a native systemd service. InvokeAI is a path flake in
  `packages/invokeai` imported by `modules/desktop.nix` only.
- **Private flake input.** `cheesetool` is a private repository, and its `flake.nix` currently
  exists only on the branch `plan/vapor-forge-windows-host` (the input uses `?ref=` for that
  until it is merged to `main`). Every machine that evaluates this flake (desktop, laptop,
  server, CI) needs a GitHub token in Nix's `access-tokens`, even though only the server
  uses the module. Put it in `~/.config/nix/nix.conf` (mode 0600), never in the Nix store or
  this repository:

  ```console
  access-tokens = github.com=<fine-grained token, read-only Contents, cheesetool only>
  ```

  The workstations can use `gh auth token`; the server should have its own narrow token. During
  `nixos-install` export `NIX_CONFIG='access-tokens = github.com=<token>'` first. CI reads the
  Actions secret `NIX_ACCESS_TOKEN`. Details in `docs/cheesetool-reseed.md`.
- **Images are pinned by digest.** Fluxer's images are pinned inside
  `services/fluxer/docker-compose.yml`; Overleaf is pinned in `hosts/desu/local.nix`; TTML and SPAR
  come from a **private GHCR** (`ghcr.io/blockgameentity/ttml-fixer`, `.../spar-bot`) and are pinned
  by digest in `local.nix` after `scripts/publish-image.sh` publishes them. Local tags are not
  used. The server pulls with a `read:packages` token (see [Secrets](#secrets)).
- **Do not combine the OS migration with application upgrades.** The one deliberate exception is
  MongoDB/Redis (7.0 and 7.4), which is migrated through a logical dump, never by opening old
  physical files with a new major version (`docs/overleaf-upgrade.md`).
- Nixpkgs, Home Manager and every input are locked in `flake.lock`; updating is a deliberate
  `nix flake update <input>` (see [Day-to-day operations](#day-to-day-operations)).

## The server (`desu`)

### What runs where

| Public name | Backend | Container / unit | Data |
| --- | --- | --- | --- |
| `chat.desu.re` | `127.0.0.1:42295` (Fluxer edge) | `fluxer.service` (Docker Compose, project `fluxer`) | Docker volumes `fluxer_*` |
| `overleaf.desu.re` | `127.0.0.1:1337` | `podman-overleaf` + `-mongo` + `-redis` | `/srv/overleaf/{data,mongo,redis}` |
| `ttml.desu.re` | `127.0.0.1:8000` | `podman-ttml-fixer-api` + `-worker` | `/var/lib/ttml-fixer`, `/var/cache/ttml-fixer` |
| (none, outbound only) | operator API `127.0.0.1:8080` | `cheesetool-reseed.service` (native) | `/var/lib/cheesetool-reseed` |
| (none) | no ports | `podman-spar-bot` | `/srv/spar` |
| (none) | no ports | `ci-runner-N` + `ci-network` (KVM guests) | `/var/lib/ci-runner-N` |

Voice for Fluxer needs **TCP 7881 and UDP 7882** reachable directly (LiveKit); those two are the
only ports that are public without going through Cloudflare.

### Edge: Cloudflare, Caddy and the firewall (`modules/edge.nix`)

- Records are **orange-cloud** (proxied) and Cloudflare SSL mode is **Full (strict)**.
- **Caddy obtains Let's Encrypt certificates itself** (ACME), as the old server did. Because the
  records are proxied, the HTTP-01 challenge arrives from Cloudflare addresses and passes the
  firewall; a DNS-only (grey cloud) record could not be validated. HTTP/3 is off (no UDP/443).
- Each site returns 403 to any peer outside the Cloudflare ranges and passes the client address on
  from `CF-Connecting-IP`. The ranges are hard-coded in `modules/edge.nix`; review them against
  <https://www.cloudflare.com/ips-v4> and `/ips-v6` manually. Nothing fetches them at boot.
- **Firewall** (`networking.firewall`, default-deny): ports 80/443 are accepted only from the
  Cloudflare ranges; 7881/tcp and 7882/udp are public; `tailscale0` accepts 22; ping is allowed;
  nothing else is open. Do not add global allows for 80/443.
- **Docker and Podman publications bypass the host INPUT firewall.** Every published port is
  therefore bound to `127.0.0.1` (Overleaf, TTML API, the Fluxer edge) or is one of the two
  deliberate LiveKit ports; databases publish nothing. Never change these to `0.0.0.0`; verify
  from outside the network after every change (see [Acceptance tests](#acceptance-tests)).
- Cloudflare source-IP allowlisting blocks ordinary direct-origin bypass but is not proof that
  traffic came through *your* zone. For that, add zone-specific Authenticated Origin Pulls or use
  a Cloudflare Tunnel. Shared Cloudflare AOP certificates alone are not zone-specific.

### Services always come back (`modules/apps.nix`)

A power cut or a reboot must bring every service back without anyone logging in.

- Every Podman container unit is wanted by `multi-user.target` and runs with `Restart=always`,
  `RestartSec=5` and no systemd start-rate limit, so a crash loop or a clean exit never leaves a
  container down.
- Fluxer is a systemd-managed Compose stack (`fluxer.service`, `Type=oneshot`,
  `RemainAfterExit`, `Restart=on-failure`). `up -d` runs on every boot; once up, Compose's own
  `restart: unless-stopped` covers crashes. Docker is enabled on boot.
- The Overleaf Mongo replica set (`overleaf`, member `mongo:27017`) is initialised on first start;
  an existing replica set is never rewritten.

### Applications

**Overleaf.** The existing `rigon/sharelatex-full:latest-shell-escape` image, pinned by digest.
Shell escape is enabled: keep registration restricted and treat LaTeX compilation as untrusted
execution inside the application container. This is not a safe public multi-tenant sandbox.
MongoDB is `mongo:7.0` and Redis is `redis:7.4-alpine` (`desu.images.mongo` / `.redis`). Redis is a
cache and is not restored. MongoDB 7.0 has **no in-place downgrade**: restore a logical dump into a
fresh 7.0 (`docs/overleaf-upgrade.md`).

**Fluxer.** The upstream self-hosting bundle in `services/fluxer`, vendored verbatim, with its
behind-a-proxy overlay. Secrets come from `/var/lib/secrets/fluxer.env`; non-secret settings
(`FLUXER_DOMAIN`, scheme/port, edge bind, protocols) are set by the unit in `modules/apps.nix`,
because Compose gives the process environment precedence over `--env-file`. A stale
`FLUXER_DOMAIN` in the env file is therefore ignored. Provenance, digests and the upgrade
procedure are in `docs/fluxer.md`. The bundle's images are newer than the ones the old server ran
(Meilisearch, SeaweedFS, Valkey), so restoring old *data* means restoring with the old images first
and upgrading afterwards; a fresh start has no such constraint.

**TTML.** Two containers from the application flake: an enqueue-only API (1 GiB / 1 CPU) and a
worker (24 GiB / 8 CPU) that owns model download and inference. They share the SQLite job store,
spool and result cache; only the worker mounts the model cache and the optional cookie file. The
image runs as **UID 10001**, so `/var/lib/ttml-fixer` and `/var/cache/ttml-fixer/*` are created
with that ownership. **CPU only** (`TTML_FIXER_PROFILE=homelab-cpu`); no GPU is configured.
It is a public instance with bearer tokens: `TTML_FIXER_PUBLIC_INSTANCE=true`,
`TTML_FIXER_CORS_ORIGINS=https://xpui.app.spotify.com` (the Spicy Lyrics extension; Limusic is native
code and needs no CORS), `TRUSTED_PROXY_CIDRS=127.0.0.1/32` (Caddy is local). Settings live in
`modules/apps.nix`; there is no `ttml.env`. **Tokens are the access control**, one per client;
`docs/ttml-clients.md` explains this and the one-off command that creates the first token
(`podman exec` cannot, because the API refuses to start without a token).

**SPAR.** The `spar` flake's read-only container. State goes in `/srv/spar` (owned by UID 10001):
`config.toml` and `bot.db` (wants, price history, caches). `DISCORD_BOT_TOKEN` and
`DISCORD_GUILD_ID` come from `/var/lib/secrets/spar.env`. The bot flake wraps the repository's
Dockerfile; it is a networked image build, not a reproducible PaddleOCR package.

**cheesetool reseed.** `services.cheesetool-reseed` (native, hardened systemd unit): a relay-only
Iroh endpoint with outbound connections only. The operator API/dashboard binds
`127.0.0.1:8080` behind a bearer token (`/var/lib/secrets/cheesetool-reseed-token`); reach it with
`ssh -L 8080:127.0.0.1:8080 desu` or Tailscale SSH. The migration starts a **fresh identity** and
re-downloads the archive; the helper's pinned endpoint id must be updated after the first start
(`docs/cheesetool-reseed.md`). The identity key is not in the backups.

### Images from the private GHCR

`scripts/publish-image.sh ttml|spar [tag]` builds the image at the revision locked in
`flake.lock` (`nix run <flake> -- <name:tag>`, a podman build of the application's Dockerfile),
pushes it to `ghcr.io/blockgameentity/...` and prints the `repo@sha256:...` reference to paste
into `hosts/desu/local.nix`. It needs rootless podman (`virtualisation.podman.enable` is set on the
desktop) and a login that may write packages:

```console
gh auth refresh -h github.com -s write:packages
gh auth token | podman login ghcr.io -u blockgameentity --password-stdin
```

Check afterwards that the packages are private. The server logs in with the `read:packages`
token at `/var/lib/secrets/ghcr-token` (`modules/apps.nix`). Build from a clean Git checkout only:
Nix can copy untracked runtime files into its world-readable store for non-Git trees.

### CI runners (`modules/ci-runners.nix`, `ci/`)

Disposable single-job KVM GitHub runners for the two private organizations and the two selected
private `blockgameentity` repositories. Each pool has a distinct token and workflow label; public
repositories must not be admitted to either organization runner group. A per-guest nft policy
(`table inet ci_isolation`) denies private ranges, `100.64.0.0/10`, IPv6 and the production origin
to guests. The origin address is **loaded at start from `/var/lib/secrets/ci-blocked-ipv4`** (one
IPv4 CIDR per line) into an nft set, so it never reaches git or the Nix store. If the file is
missing or empty, `ci-network.service` fails and no guest network comes up. Each pool uses a
separate fine-grained Administration:write token, scoped to its organization or repository and
root-only. Read `ci/README.md` before enabling jobs. `hosts/mac/configuration.nix` is the
nix-darwin trusted-runner service.

### Backups and maintenance

- `modules/backup.nix`: restic, nightly at 03:30. It stops Fluxer, Overleaf, TTML and SPAR, takes
  the snapshot, then restarts them even if the snapshot failed. Paths: `/var/lib/secrets`,
  `/srv/overleaf`, `/srv/spar`, `/var/lib/ttml-fixer` and the Fluxer database volumes. The
  repository and credentials come from `/var/lib/secrets/restic.env`. Snapshots are not backups
  (`docs/remaining-work.md`, "Snapshots"); NixOS rollback does **not** roll back databases or
  container images.
- `modules/maintenance.nix`: weekly store GC (30 days) and an opt-in flake auto-upgrade
  (`desu.maintenance.autoUpgrade.enable`, off, no automatic reboot).

### Remote access

The server runs **Tailscale SSH** (`--ssh`, OAuth through the tailnet) with OpenSSH disabled.
Workstations also disable `sshd`; their OpenSSH clients remain available for other remote servers.
Connect to the server with `ssh desu@desu` from a Tailscale-authorized device, subject to the
tailnet's SSH policy. Confirm this from a second device before disconnecting rescue access.

## Secrets

Runtime secrets are root-only files under `/var/lib/secrets` (on the target: `/mnt/var/lib/secrets`
before first boot). Git holds paths, never values. Missing secrets make the affected service fail
closed. Files are `root:root 0600`, except `youtube-cookies.txt`, which is UID/GID 10001 with mode
`0400` or `0600`. `/var/lib/secrets` itself is `root:caddy 0710` (traverse only), and Caddy reads
nothing in it. Storage, reuse and rotation policy: `docs/secrets.md`.

| File | Used by | Notes |
| --- | --- | --- |
| `desu-password-hash` | every host | A yescrypt hash (`mkpasswd -m yescrypt`), required on **all three** hosts: without it the account is locked and `sudo` / the greeter reject every password. Activation fails if the option points at a missing file. |
| `fluxer.env` | Fluxer | Secrets only. Key list and what breaks if each changes: `services/fluxer/.env.example`, `docs/fluxer.md`. New in the current bundle: `FLUXER_PROFILE_PSEUDONYM_SECRET`, `FLUXER_ERLANG_COOKIE` (generate once, never change), `FLUXER_SETUP_TOKEN` (first admin), optional `FLUXER_ACTIVITYPUB_SIGNING_KEY_BASE64`. Reusing the old instance's keys keeps its sessions and attachments valid; a fresh start can generate everything. |
| `spar.env` | SPAR | `DISCORD_BOT_TOKEN`, `DISCORD_GUILD_ID` |
| `youtube-cookies.txt` | TTML worker | Optional cookie export, mounted read-only into the worker only (`desu.ttmlCookies`) |
| `ghcr-token` | Podman | Classic PAT with only `read:packages` (fine-grained tokens cannot read packages) |
| `cheesetool-reseed-token` | reseed node | Operator API bearer token, `openssl rand -hex 32` |
| `ci-desu-renai-token`, `ci-examwatcher-token` | CI organization pools | Fine-grained organization Administration:write; ExamWatcher uses `Self-hosted CI`, desu-renai uses `Default` |
| `ci-cheesetool-token`, `ci-pawchive-downloader-token` | CI repository pools | Fine-grained, restricted to that repository, Administration:write |
| `ci-blocked-ipv4` | CI runners | The server's public origin IPv4 CIDR(s), one per line. **Secret; never commit.** |
| `tailscale-auth-key` | Tailscale | One-off, preauthorized, non-ephemeral key for headless enrolment |
| `restic.env` (or `restic-password`) | backups | Repository URL, password and S3/R2 credentials; needed once `desu.backup.enable = true` |

Not used any more: `ttml.env` (settings are in `modules/apps.nix`) and the Cloudflare Origin CA
files (`cloudflare/origin*.pem`; Caddy uses ACME).

`scripts/preflight.py` checks that the required files exist, are non-empty and have the right
mode, that `ci-blocked-ipv4` holds public IPv4 CIDRs, that `local.nix` has no `PLACEHOLDER`, no
`:latest`/`:migration` image tag and no IP address, and that the working tree is committed. It
never prints secret contents:

```console
nix run nixpkgs#python3 -- scripts/preflight.py   # as root (it reads /var/lib/secrets); --secrets DIR, --skip-git
```

One strong passphrase is shared by the Bitwarden master, LUKS and restic (a documented, accepted
tradeoff); everything never typed by hand is a random string that lives only in the vault.

## Migrating the old server

The old server was an Arch box running Docker Compose projects (Fluxer via `rexctl`, Overleaf,
TTML, SPAR, the reseed container) behind a host Caddy. The order below is what was actually used;
keep every step, because the wipe is the point of no return.

### 1. Prepare (nothing on the server changes)

1. Inventory, read-only, saved off the server: `docker ps -a`, `docker inspect` (never paste
   environment *values*), image digests, volumes with sizes, systemd units and timers, cron,
   firewall, listening ports, SSH and Tailscale state, certificates, and **unpushed or dirty git
   work** in every repository under the home directory.
2. Decide what is *not* migrated (large re-downloadable data, unrelated projects). For this
   migration: the reseed archive, the Fluxer data, game servers, old CI checkouts and the old
   runner. Keep only what is irreplaceable.
3. Create the tokens: the read-only Nix token, the `read:packages` token, the Tailscale auth key,
   the CI token; store them in Bitwarden. Reserve the server's DHCP lease in the router and keep the
   port-forwards for 80, 443, 7881 and 7882.
4. Publish the TTML and SPAR images and pin their digests ([Images from the private
   GHCR](#images-from-the-private-ghcr)).

### 2. Back up (re-run both steps right before the wipe)

What matters: the Overleaf Mongo dump and data, the SPAR config and its database, TTML's cookies,
the Fluxer secrets, and the Caddy configuration. Pitfalls found the hard way:

- **GNU tar's flag is `--numeric-owner`**, not `--numeric-ids`. Use
  `tar --numeric-owner --xattrs --acls -czf out.tgz -C <dir> <name>` so ownership survives.
- **Dump Mongo online**: `docker exec mongo mongodump --archive --gzip --oplog > dump.archive.gz`
  (replica set, so it is consistent). Do not copy a live `/data/db`.
- **SPAR's `bot.db` is not next to `config.toml`** on the old layout: it lived in the work volume.
  Stop the container briefly and copy the whole volume (`docker run --rm -v <vol>:/v:ro -v
  <dir>:/o busybox tar -czf /o/spar-vol.tgz -C /v .`).
- **Fluxer secrets live in the containers' environment**, not in a `.env` file, on the
  `rexctl`-managed install. Read them with `docker inspect -f '{{range .Config.Env}}...'` into a
  root-only file; map `FLUXER_S3_ACCESS_KEY_ID`/`..._SECRET_ACCESS_KEY` to
  `FLUXER_S3_ACCESS_KEY`/`..._SECRET_KEY` and `FLUXER_LIVEKIT_API_KEY`/`..._SECRET` to
  `LIVEKIT_API_KEY`/`..._SECRET`; never print the values.
- **Do not carry over the old TTML `.env`.** It pins GPU-era runtime values that override the
  `homelab-cpu` profile; only the cookie file is kept.
- **`sudo` swallows pasted input.** Run `sudo -v` on its own line first, then paste the script, or
  the password prompt eats the first lines.
- Copy the backup to **your own disk**, not to the partition that will be wiped, and treat it as
  secret material (encrypted disk or encrypted archive). Verify with `sha256sum -c SHA256SUMS`
  from inside the copy and `gzip -t` on every archive.

### 3. Install

Follow [Installing a machine](#installing-a-machine) with `.#desu` and the server partitioning
block. Before `nixos-install`:

```console
export NIX_CONFIG='access-tokens = github.com=<read-only token>'
# provision /mnt/var/lib/secrets (see Secrets), then:
nix run nixpkgs#python3 -- scripts/preflight.py --secrets /mnt/var/lib/secrets
```

The nixos-config repository itself is public, so `git clone` needs no login.

### 4. Restore (keep services stopped until every restore is done)

- **Overleaf:** once the fresh Mongo 7.0 has initiated the replica set, restore the logical dump
  into it, restoring only the application database (the dump's `admin` database holds the old 6.0
  feature-compatibility document and must not be applied):
  ```console
  sudo podman exec -i overleaf-mongo mongorestore --archive --gzip --nsInclude 'sharelatex.*' \
    < mongo-sharelatex.archive.gz
  ```
  Copy `sharelatex_data` to `/srv/overleaf/data` preserving ownership, and leave Redis empty.
  Validate `rs.status()` (PRIMARY), log in, open a project and compile a PDF.
- **SPAR:** extract `config.toml` and `bot.db` into `/srv/spar`, owned by UID/GID 10001
  (`install -d -o 10001 -g 10001 -m 0700 /srv/spar`). Never run the old and the new bot at the same
  time: they would both post.
- **TTML:** state is new and its caches are rebuilt. Put the cookie file in place and create one
  bearer token per client (`docs/ttml-clients.md`).
- **Fluxer:** a fresh start needs no restore. To keep an existing instance, restore its volumes
  with the *old* image digests first, confirm it serves, then move to the vendored bundle and watch
  the migrations (`docs/fluxer.md`, "Migrating the old instance").
- **Reseed node:** nothing to restore; read the new endpoint id from the journal and update the
  helper (`docs/cheesetool-reseed.md`).
- Restore into the **new** volumes. Never copy Docker's whole runtime storage between
  installations.

### 5. Cut over and clean up

Tailscale joins as a new node named `desu`; delete the stale old node in the admin console. Set
Cloudflare SSL to Full (strict). Create `/var/lib/secrets/ci-blocked-ipv4`. Then run the
[acceptance tests](#acceptance-tests), reboot, and repeat them.

## Installing a machine

Boot the NixOS installer and partition deliberately: no destructive disk script is included. The
repository assumes UEFI with Limine; adapt it if a machine uses legacy BIOS. Stage new files
before flake evaluation: the flake copies the git tree, not the working directory, so anything
ignored by `.gitignore` never reaches the store and an uncommitted change is not installed.

### Step by step (desktop / laptop; the server uses `.#desu` and its own partitioning block)

0. **Before booting the installer** (desktop): everything on `nvme0n1p2` is destroyed, which is the
   old CachyOS `/` *and* `/home`. Copy `~` (SSH/GPG keys, browser profiles, `~/.local/share`, game
   saves, anything not in git) to one of the data disks or off the machine, and `git push` this
   repository: the working copy under `~` goes with the partition.
1. Boot the NixOS ISO (graphical or minimal; the installer's own channel does not matter, the flake
   pins everything). Get online: ethernet is plug-and-play; for wifi use the graphical ISO's
   network menu or `nmtui` on the minimal one.
2. `sudo -i`, then `loadkeys dk`: the LUKS passphrase and the account password are typed in the
   installer, while the installed system boots with a Danish keymap.
3. Partition and mount: the per-host block under [Storage](#storage).
4. Clone the repository **into the target**, where `NH_FLAKE` will point after boot:
   ```console
   nix-shell -p git --run 'git clone https://github.com/blockgameentity/nixos-config.git /mnt/etc/nixos'
   ```
   Optionally diff the hardware description (`nixos-generate-config --root /mnt --dir /tmp/hw`, see
   `hosts/README.md`); never let it overwrite the committed file.
5. Provision the password hash. Without it the Ly greeter, `sudo` and sshd reject every password
   (the graphical hosts have **no autologin**):
   ```console
   install -d -m 0700 /mnt/var/lib/secrets
   nix-shell -p mkpasswd --run 'mkpasswd -m yescrypt' > /mnt/var/lib/secrets/desu-password-hash
   chmod 600 /mnt/var/lib/secrets/desu-password-hash
   ```
   (`/var/lib/secrets` is `0710 root:caddy` on the server; create it that way there.)
6. Install. The CachyOS kernel (and the NVIDIA module built against it) comes from the Chaotic-Nyx
   cache, but the *installer's* nix only knows cache.nixos.org: without the two `--option` flags it
   compiles that kernel with LTO from source, which takes hours:
   ```console
   cd /mnt/etc/nixos
   nixos-install --flake .#desktop --no-root-passwd \
     --option extra-substituters https://nyx-cache.chaotic.cx/ \
     --option extra-trusted-public-keys nyx-cache.chaotic.cx:dJxTrgMC3V3cFfyIiBQDQorG6k1LsqurH/srpMSq7qk=
   ```
   (`.#laptop` for the laptop; the desktop also downloads several GB of CUDA toolkit.)
   `--no-root-passwd` leaves root locked on purpose; `sudo` uses the `desu` password. Export
   `NIX_CONFIG` with the access token first (see [Design choices](#design-choices)).
7. Hand the checkout to the user, so `nh` (which builds as the user) and git can work on it:
   ```console
   nixos-enter --root /mnt -c 'chown -R desu:users /etc/nixos'
   reboot
   ```
8. First boot: LUKS passphrase, then `desu` and the password at Ly, which starts Wayfire. Then:
   - wifi: `nm-applet` in the bar, or `nmcli device wifi connect <SSID> --ask`;
   - Bluetooth: `blueman-applet` in the bar, or `bluetoothctl` (`scan on`, `pair`, `trust`, `connect`);
   - Tailscale: `sudo tailscale up` (no `--ssh` on the workstations, see
     [Remote access](#remote-access));
   - Windows: the `Windows` entry in the Limine menu (chainloads `EFI/Microsoft/Boot/bootmgfw.efi`
     from the shared ESP), see [Bootloader](#bootloader-limine);
   - later rebuilds: `nh os switch` as `desu`.

Server install, after its partitioning block (same pattern):

```console
# Clone into the target: NH_FLAKE (modules/base.nix) is /etc/nixos on the INSTALLED system.
nix-shell -p git --run 'git clone https://github.com/blockgameentity/nixos-config.git /mnt/etc/nixos'
cd /mnt/etc/nixos
git add hosts/desu
nix flake check
nix build .#nixosConfigurations.desu.config.system.build.toplevel
nixos-install --flake .#desu --no-root-passwd
nixos-enter --root /mnt -c 'chown -R desu:users /etc/nixos'
```

After first boot, rebuilds use `nh`:

```console
nh os switch           # build and activate /etc/nixos for this host
nh os boot             # same, but only for the next boot
nh search <query>      # package search; queries search.nixos.org, not nix-index
```

`nh` derives the host from the flake, so `nh os switch` activates whichever
`nixosConfigurations.<hostname>` matches the machine. Pass a path explicitly
(`nh os switch /some/other/checkout`) or override `NH_OS_FLAKE` per command.

## Storage

All hosts use one vfat ESP and one btrfs pool split by purpose. The server gets the most
subvolumes because it runs containers; the workstations keep eight:

| Host | Subvolumes |
| --- | --- |
| `desu` (server) | `@ @nix @home @root @srv @cache @log @tmp @docker @lib` |
| `desktop` | `@ @nix @home @root @srv @cache @log @tmp` (dual boot, ESP shared with Windows, all inside LUKS) |
| `laptop` | same eight as the desktop, all inside LUKS (`cryptroot`) |

`@docker` (`/var/lib/docker`) and `@lib` (`/var/lib/containers`) exist only on the server: they keep
container state out of a root rollback, and nothing else runs containers.

Every block below addresses the disk by **device node** (`/dev/nvme0n1p2`, `/dev/mapper/vg0-root`,
`/dev/mapper/cryptroot`), not by `/dev/disk/by-label/...`. The labels are still required and still
set (`mkfs.btrfs -L nixos`, `mkfs.vfat -n boot`, `luksFormat --label cryptroot`), because
`hardware-configuration.nix` mounts everything by label at boot. The install-time commands avoid the
label paths on purpose: those symlinks are created by udev asynchronously, so
`cryptsetup open /dev/disk/by-label/cryptroot` issued right after `luksFormat --label cryptroot`
can fail with *"device ... does not exist or access denied"* while the header is perfectly fine. If
you prefer the label form anyway, run `udevadm settle` (or `blkid`) between formatting and mounting.

### Server (`hosts/desu/hardware-configuration.nix`)

```console
sgdisk -n1:0:+1G -t1:ef00 -c1:boot /dev/nvme0n1     # ESP
sgdisk -n2:0:0    -t2:8300 -c2:nixos /dev/nvme0n1     # everything else
mkfs.vfat -F32 -n boot /dev/nvme0n1p1
mkfs.btrfs -L nixos /dev/nvme0n1p2

# Subvolumes live at the top level (subvolid=5), never inside a mounted root.
mount -o subvolid=5 /dev/nvme0n1p2 /mnt
for sv in @ @nix @home @root @srv @cache @log @tmp @docker @lib; do
  btrfs subvolume create /mnt/$sv
done
umount /mnt

OPTS=noatime,compress=zstd:1
mount -o "$OPTS",subvol=@ /dev/nvme0n1p2 /mnt
mkdir -p /mnt/{nix,home,root,srv,var/{cache,log,tmp},var/lib/{docker,containers},boot}
mount -o "$OPTS",subvol=@nix   /dev/nvme0n1p2 /mnt/nix
mount -o "$OPTS",subvol=@home  /dev/nvme0n1p2 /mnt/home
mount -o "$OPTS",subvol=@root  /dev/nvme0n1p2 /mnt/root
mount -o "$OPTS",subvol=@srv   /dev/nvme0n1p2 /mnt/srv
mount -o "$OPTS",subvol=@cache /dev/nvme0n1p2 /mnt/var/cache
mount -o "$OPTS",subvol=@log   /dev/nvme0n1p2 /mnt/var/log
mount -o "$OPTS",subvol=@tmp   /dev/nvme0n1p2 /mnt/var/tmp
mount -o noatime,subvol=@docker /dev/nvme0n1p2 /mnt/var/lib/docker
mount -o noatime,subvol=@lib    /dev/nvme0n1p2 /mnt/var/lib/containers
mount -o fmask=0077,dmask=0077 /dev/nvme0n1p1 /mnt/boot

nixos-generate-config --root /mnt   # then compare with hosts/desu/hardware-configuration.nix
```

### Desktop (`hosts/desktop/hardware-configuration.nix`)

This machine dual-boots, so the ESP is **shared with Windows Boot Manager and is not reformatted**.
NixOS only ever owns `nvme0n1p2`; the committed config addresses the ESP by UUID (`226E-1C60`),
which survives a reinstall as long as the partition is kept. Windows itself lives on the other NVMe
and is untouched by any of this.

```console
# Do NOT touch nvme0n1p1 - Windows Boot Manager and Limine both live on it.
cryptsetup luksFormat --label cryptroot /dev/nvme0n1p2   # destroys ALL of CachyOS: / and /home
cryptsetup open /dev/nvme0n1p2 cryptroot
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

The installer adds a `Limine` firmware entry next to `Windows Boot Manager`; it does not remove it.
`time.hardwareClockInLocalTime = true` is set for this host so Windows' clock does not jump two
hours every time you boot it. NetworkManager (ethernet + Intel wifi) and Bluetooth are enabled in
`hosts/desktop/configuration.nix`; their firmware comes from `hardware.enableRedistributableFirmware`
in `modules/graphical.nix`. Other drives are not touched by the install and are not in
`fileSystems`; udisks2 mounts them under `/run/media/desu/<label>` on demand.

### Laptop (`hosts/laptop/hardware-configuration.nix`)

Everything except the ESP sits inside LUKS2, and LVM sits inside the LUKS container so the laptop
gets a swap **block device** (needed for hibernation) without a second passphrase. Labels are used
throughout, so a re-partition only has to keep the labels.

```console
sgdisk -n1:0:+1G -t1:ef00 -c1:boot /dev/nvme0n1
sgdisk -n2:0:0    -t2:8309 -c2:cryptroot /dev/nvme0n1
mkfs.vfat -F32 -n boot /dev/nvme0n1p1
cryptsetup luksFormat --label cryptroot /dev/nvme0n1p2
cryptsetup open /dev/nvme0n1p2 cryptroot

# LVM inside LUKS: one volume group, a swap LV for hibernation, a root LV for btrfs.
pvcreate /dev/mapper/cryptroot
vgcreate vg0 /dev/mapper/cryptroot
lvcreate -L 32G -n swap vg0        # MUST be >= RAM + 2 GiB, see "Hibernation" below
lvcreate -l 100%FREE -n root vg0
mkfs.btrfs -L nixos /dev/mapper/vg0-root
mkswap /dev/mapper/vg0-swap

mount -o subvolid=5 /dev/mapper/vg0-root /mnt
for sv in @ @nix @home @root @srv @cache @log @tmp; do
  btrfs subvolume create /mnt/$sv
done
umount /mnt

OPTS=noatime,compress=zstd:1
mount -o "$OPTS",subvol=@ /dev/mapper/vg0-root /mnt
mkdir -p /mnt/{nix,home,root,srv,var/{cache,log,tmp},boot}
mount -o "$OPTS",subvol=@nix   /dev/mapper/vg0-root /mnt/nix
mount -o "$OPTS",subvol=@home  /dev/mapper/vg0-root /mnt/home
mount -o "$OPTS",subvol=@root  /dev/mapper/vg0-root /mnt/root
mount -o "$OPTS",subvol=@srv   /dev/mapper/vg0-root /mnt/srv
mount -o "$OPTS",subvol=@cache /dev/mapper/vg0-root /mnt/var/cache
mount -o "$OPTS",subvol=@log   /dev/mapper/vg0-root /mnt/var/log
mount -o "$OPTS",subvol=@tmp   /dev/mapper/vg0-root /mnt/var/tmp
mount -o fmask=0077,dmask=0077 /dev/nvme0n1p1 /mnt/boot
swapon /dev/mapper/vg0-swap               # so nixos-generate-config sees it
```

`allowDiscards = true` is set on the LUKS device so the weekly `fstrim` reaches the SSD. That
reveals which blocks are free to someone reading the raw device (not their contents); on a laptop
that is the usual tradeoff.

Measured on the actual machine: Ryzen (`AuthenticAMD` so AMD microcode), Radeon iGPU at `05:00.0`,
RTX 3060 Mobile (`PCI:1:0:0`), MT7921 wifi, MediaTek Bluetooth, **13 GiB usable RAM** (so the 32 GiB
swap LV clears the RAM + 2 GiB rule for hibernation). The ESP is recreated at 1 GiB by the `sgdisk`
line above and relabelled `boot` by `mkfs.vfat -n boot`; nothing on this machine shares it. The
laptop also enables NetworkManager (`mt7921e` wifi, `r8169` ethernet), Bluetooth, libinput, upower,
power-profiles-daemon (not TLP: the two conflict), fwupd and PRIME offload.

### Why these boundaries

`@nix` keeps the store out of a root rollback, `@srv` holds mutable service data (`/srv/overleaf`,
`/srv/spar`), and `@log`/`@cache`/`@tmp` keep churn and cache away from everything else. `/nix` and
`/var/log` carry `neededForBoot = true`: without it they would be mounted in stage 2, after the
store and journald are already in use on the root subvolume.

Compression stays `zstd:1` and TRIM is a weekly `fstrim` timer (`modules/btrfs.nix`), not the
`discard` mount option. A monthly scrub is enabled there too: one mountpoint per filesystem, since
scrub runs on devices and every subvolume shares them. `overlay2` remains Docker's storage driver on
btrfs (supported as an overlayfs lower layer since kernel 4.15); do not add `nodatacow` to `@docker`
to "fix" it. `nixos-generate-config` does not know about `neededForBoot`, the subvolume set or
`compress=`: review its output against the committed file instead of overwriting it.

### Swap and memory: zswap, never zram

`modules/memory.nix` is imported by every host and encodes two rules:

- **zswap only.** Compressed page cache in front of a real swap device, `zstd`, pool capped at 25%
  of RAM, shrinker on. `zramSwap.enable = false` is a plain assignment, not a default, so a host
  that tries to turn zram on fails evaluation instead of stacking two compressors.
- **One swap file on the root subvolume**, `/swap`, created by the NixOS swap unit with
  `btrfs filesystem mkswapfile` (NOCOW, uncompressed: compulsory for swap on btrfs). Sizes: desktop
  64 GiB, server 32 GiB, via `desu.memory.swapSizeMiB`. Changing the number recreates the file on
  the next switch. The laptop sets `desu.memory.swapFile = null` and swaps on its `vg0/swap` LV.

`vm.swappiness = 100` and `vm.page-cluster = 0`: with zswap, swapped pages are still in RAM
(compressed), so spilling early is cheap and the file only holds the overflow.

### Hibernation (laptop only)

The laptop hibernates with `systemctl hibernate`; the desktop and server do not (`/swap` is a btrfs
swap file there). Two hard requirements:

1. **The swap device must be a block device.** Hibernating into a btrfs swap *file* needs
   `resume_offset`, a physical offset that changes every time the file is recreated: fragile. Hence
   `vg0/swap`.
2. **Swap must be at least RAM + a couple of GiB**, or `systemctl hibernate` refuses with "Not
   enough swap space". The 32 GiB LV covers anything up to about 30 GiB of RAM; resize with
   `lvextend`/`lvresize -L` if the machine changes.

Resume works with LUKS because stage 1 unlocks `cryptroot` and activates `vg0` before
`systemd-hibernate-resume` reads `resume=/dev/mapper/vg0-swap`. zswap sits in front of normal swap
pages, not in front of the hibernation image (swsusp writes that directly to the block device), so
the pool does not have to be drained first. Suspend-to-RAM works on all three hosts without any of
this. Verify on the laptop that `systemctl hibernate` ends in a real resume, not a cold boot.

### Snapshots vs NixOS generations

Two different rollback mechanisms; only the second is enabled anywhere.

| | NixOS generation | btrfs snapshot |
| --- | --- | --- |
| Covers | system profile, kernel, initrd, services config | every file on that subvolume, including `/var/lib`, `/srv`, `/home` |
| Granularity | per `nixos-rebuild` | whenever a snapshot is taken |
| Undoes | a bad config or package change | a bad *data* change: failed DB upgrade, deleted files, corrupted container state |
| Boot entry | yes, `nh os rollback` or an older Limine entry | only if you add entries yourself |

A NixOS rollback does **not** restore `/var/lib/docker`, the Overleaf Mongo data or anything else
under `/srv`: those are mutable data, not store paths. That gap is what `services.snapper` or the
restic backups cover. Snapshots are not backups either (they share the disk), so restic stays the
off-site copy. Enabling snapper later needs one more subvolume (`@snapshots` at `/.snapshots`) and
its own rollback runbook; do not mount it on top of an existing layout without redoing the
partitioning.

### Encryption (LUKS): the verdict per machine

Decision taken, so it does not get re-litigated every time a disk is touched:

| Host | LUKS | Why |
| --- | --- | --- |
| laptop | **yes** (configured) | Leaves the house. Full disk encryption is the difference between "stolen laptop" and "someone reading `/home/desu/.ssh` and every saved session". |
| desktop | **yes** (configured) | Stays at home, but it holds the same secrets plus a Windows partition. AES-NI on a 14700K makes the I/O overhead a rounding error, and deciding later means reformatting. |
| server | **no** | A headless box that must come back after a power cut cannot ask for a passphrase. Adding LUKS there means initrd SSH (`boot.initrd.network.ssh`) or TPM2 unlock, and with Secure Boot off a TPM2-bound key can be replayed by booting a custom kernel, so the protection is thin for the operational cost. |

LUKS protects data at rest, not a running system: anyone with five minutes and a USB stick reads an
unlocked machine, and a stolen *server* is compromised even with FDE unless it was powered off. So
the server compensates differently: secrets under `/var/lib/secrets` are rotatable (Tailscale key,
restic credentials, CI and registry tokens), restic sends encrypted backups off-site, and
`swapDevices.*.randomEncryption` can be turned on to keep plaintext out of the swap file. LUKS is
unrelated to the Windows anticheat/Secure Boot question: Linux FDE does not touch the firmware.

## Bootloader (Limine)

Every NixOS host enables `boot.loader.limine`; `boot.loader.systemd-boot` is not enabled anywhere.
Limine loads kernels and initrds directly from `/boot` and keeps its menu in `/boot/limine.conf`, so
`maxGenerations = 10` only bounds how many generations appear in the menu: there are no
per-generation EFI binaries to pile up. `boot.loader.efi.canTouchEfiVariables` stays `true` so the
installer writes the `Boot####` entry itself. The boot entry editor is left off: an editable command
line allows `init=/bin/sh`, i.e. root without the disk password. Secure Boot is off everywhere; it
would only be needed for Windows anticheats on the dual-boot desktop, and Limine's module has the
`sbctl` path when that day comes.

Switching a machine that currently boots systemd-boot:

```console
nh os boot          # install Limine as the active loader for the next boot
sudo reboot              # boot it before touching anything else; keep rescue media ready
# after confirming the menu and a successful boot:
sudo rm -rf /boot/EFI/systemd /boot/loader   # stale systemd-boot instance and entries
sudo efibootmgr -v                           # find the leftover "Linux Boot Manager" entry
sudo efibootmgr -b <NNNN> -B                 # delete it, or keep it as a fallback
nh os switch        # make this generation the running one
```

`nixos-install --flake .#<host>` on a fresh disk does this in one step and needs no cleanup. On the
dual-boot desktop, **never delete the `Windows Boot Manager` entry** while cleaning the list, and
never `rm -rf` anything on the ESP beyond `EFI/systemd` and `loader`. Windows and Limine share that
partition (Linux in `EFI/limine`, Windows in `EFI/Microsoft`). If Windows disappears from the boot
menu after a Windows update, it is Windows rewriting the boot order, not this repo: fix it with
`efibootmgr -o`.

## Workstation details

### Keyboard, language, currency

| What | Setting | Where |
| --- | --- | --- |
| Keyboard, TTYs and the LUKS prompt | `console.keyMap = "dk"` + `console.earlySetup = true` | `modules/base.nix` |
| Keyboard, X11 / GTK / Qt / Wayland | `services.xserver.xkb.layout = "dk"`, `XKB_DEFAULT_LAYOUT=dk` | `modules/graphical.nix` |
| Language | `i18n.defaultLocale = "en_US.UTF-8"` | `modules/base.nix` |
| Currency | `LC_MONETARY = "da_DK.UTF-8"` (DKK) | `modules/base.nix` |
| Dates and clock | `LC_TIME = "da_DK.UTF-8"`: `DD-MM-YYYY`, 24h `HH:MM` | `modules/base.nix` |
| Units / paper | `LC_MEASUREMENT`/`LC_PAPER = da_DK` (metric, A4) | `modules/base.nix` |
| Time zone | `Europe/Copenhagen` | each `hosts/<name>/configuration.nix` |
| GTK / Qt theme | GTK 3: `adw-gtk3-dark` ([adw-gtk3](https://github.com/lassekongo83/adw-gtk3)); GTK 4 / libadwaita untouched; Qt: `gtk3` platform theme + `adwaita-dark` style | `home/graphical.nix` |

`console.earlySetup` is the part that is easy to miss: without it the keymap only applies once
stage 2 starts, so the **LUKS passphrase would be typed on a US layout** while everything after it
is Danish. `LC_NUMERIC` and `LC_COLLATE` stay English on purpose: a comma decimal separator breaks
more scripts than it fixes by hand. `LC_TIME=da_DK` is the only glibc locale that formats exactly as
wanted (`d_fmt "%d-%m-%Y"`, `t_fmt "%T"`, no AM/PM); en_GB gives `31//12//24`, en_DK gives ISO,
nl_NL a two-digit year. Side effect: weekday and month names in date output are Danish while the
program's own text stays English.

Both workstations are **Wayland-only**: `NIXOS_OZONE_WL=1` and `MOZ_ENABLE_WAYLAND=1` stop
Chromium/Electron apps and Firefox from silently falling back to XWayland, and the layout is
exported as `XKB_DEFAULT_LAYOUT=dk` for compositors that do not read the xkb option. The bootloader
menu uses the firmware's keyboard handling and cannot be changed from NixOS. The Wayfire session
(Ly greeter, ironbar, OLED mode staging) is documented in `docs/wayfire.md`; Wayfire 0.11 is
packaged in `packages/wayfire.nix` because nixpkgs still ships 0.10.1.

### Login: LUKS, then the account password

The desktop and laptop import `modules/graphical.nix`, which deliberately does **not** set
`services.getty.autologinUser` or `services.displayManager.autoLogin`. Boot asks for two things: the
LUKS passphrase, then the `desu` password at the Ly greeter. Autologin is not just a convenience
question: `pam_gnome_keyring` unlocks the login keyring from the password that crosses PAM at login.
With autologin there is no such password, so the choice would be one unlock prompt per boot or an
unencrypted keyring. Typing it once buys an encrypted keyring that unlocks itself, and a powered-on
machine with the disk already unlocked is no longer a logged-in session. The server has no display
manager and only a console login.

### Audio

`modules/graphical.nix` enables PipeWire with the ALSA and PulseAudio compatibility layers
(`alsa.support32Bit` for Steam titles) plus `security.rtkit`. The desktop adds the per-device EQ
modules (`modules/gigaworks-eq.nix`, `modules/bathys-eq.nix`). The server imports none of this.

### Home profile (shell, prompt, terminal)

Home Manager is a NixOS module (`modules/base.nix`), so one user profile is built for every host:

| Profile | File | Hosts |
| --- | --- | --- |
| universal | `home/shared.nix` | server, laptop, desktop |
| graphical | `home/graphical.nix` (via `modules/graphical.nix`) | laptop, desktop |
| desktop | `home/desktop.nix` (via `modules/desktop.nix`) | desktop only (CUDA, NVIDIA, alcom, Unity Hub, InvokeAI) |

The universal profile carries fish (login shell), `starship` with the original
`~/.config/starship.toml`, `zoxide`, `fzf`, eza/bat/dust aliases, `pfetch-rs`, `helix` (`hx`,
`$EDITOR`/`$VISUAL`, Gruvbox Dark Hard) as the only terminal editor, `delta` as the git pager,
`lazygit` (`lg`), `direnv` with `nix-direnv`, `btop`, git identity plus the `gh auth` credential
helper, and the `cargo`/`ruff`/`bun`/`uv`/`go` toolchains. Cargo is configured for speed on every
host (`~/.cargo/config.toml`): `sccache` as `rustc-wrapper` and `mold` as the linker.

SSH aliases live in the same profile (`programs.ssh.settings`): `github`/`gist` map to `git@`
endpoints and `Host *` sets keepalives, agent key loading and ControlMaster multiplexing. No key
material or machine addresses are in the repository, and `~/.ssh/config` is generated (an existing
file is moved to `config.hm-backup`). Shared CLI tools: `act pandoc adb scrcpy croc dog imagemagick
ipinfo iperf3 fend yazi yt-dlp typst zstd kondo ffmpeg radare2` plus the basics.

The graphical profile adds ghostty (Gruvbox Dark Hard, bar cursor, `cursor_warp` shader),
JetBrains Mono Nerd Font as the default monospace, Noto Color Emoji and the applications used on
both machines: firefox, libreoffice, filezilla, obsidian, bitwarden, celluloid, imhex, signal,
insomnia, qbittorrent, prismlauncher, ayugram, obs-studio, ktailctl, kalker, qalculate-gtk, zed and
`claude-code`. GTK and Qt are pinned dark (`adw-gtk3-dark`; the `prefer-dark` gsettings key that
libadwaita apps read), so no app opens in a light theme. Steam and the sched_ext scheduler
(`services.scx-loader`, `scx_bpfland`) live in `modules/graphical.nix` because both are NixOS
services, not packages. `czkawka` is graphical-only so the server does not pull a GTK closure. On
the laptop, Steam and Obsidian are the only unfree packages, allowed by name.

The desktop adds `modules/desktop.nix` / `home/desktop.nix`: the CUDA toolkit, the NVIDIA driver
(open kernel modules, modesetting), alcom, Unity Hub and InvokeAI (`programs.invokeai`, web UI on
`127.0.0.1:9090`, from `packages/invokeai`). `nixpkgs.config.cudaSupport` is deliberately **not**
set globally: no binary cache builds packages with it, so it made firefox, obs-studio, onnxruntime,
opencv and TensorRT compile locally for hours. CUDA is enabled per package instead
(`.override { cudaSupport = true; }`, currently only btop for its GPU panel). Because the toolkit
ships a family of EULA packages whose names move between releases, the desktop allows unfree
packages outright. Building the desktop configuration downloads several GB of CUDA toolkit. It also
enables rootless podman, used only by `scripts/publish-image.sh`.

The server imports `modules/base.nix` only: shell, prompt, editor, git, toolchains and CLI tools, but
no terminal emulator, font, GUI app or gaming package. Dotfiles that read better as-is (the starship
TOML, the ghostty shader) are copied verbatim under `home/files/` and referenced with `.source`; to
adopt another, copy it there and add an `xdg.configFile` entry (a pre-existing file at that path is
moved to `<name>.hm-backup` on first activation).

## Day-to-day operations

```console
nh os switch                              # apply this host's configuration (as your user, not sudo)
nix flake update ttml spar                # bump the application flakes; then re-run the image publish
nix flake update cheesetool               # needs the access token (see Design choices)
scripts/publish-image.sh ttml             # build, push to GHCR, print the digest to pin
scripts/publish-image.sh spar
nix run nixpkgs#python3 -- scripts/preflight.py   # server install gate (run as root)
nix flake check --no-build                # what CI runs
```

After bumping `ttml` or `spar`, rebuild and republish the image from the new revision and update the
digest in `hosts/desu/local.nix`; the module and the image must come from the same revision. The
Fluxer bundle is updated by diffing the upstream bundle against `services/fluxer` (`docs/fluxer.md`,
"Updating"), never by editing image tags in place. Rotate tokens per `docs/secrets.md`; a revoked or
expired `ghcr-token`, Nix token or Tailscale key shows up as a failed pull, fetch or login.

## Acceptance tests

Run these on the server after install and again after a reboot:

- `nixos-rebuild build --flake .#desu` (or `nh os test`, then `nh os switch`), tested in a restore
  VM before switching production if the data is precious.
- `systemctl --failed`; `journalctl -u fluxer -u caddy`; container health; Mongo reports PRIMARY.
- From **outside** the network: direct origin HTTP/HTTPS (IPv4 **and** IPv6) is denied, and the
  Cloudflare URLs work. Ports 1337, 8000, 8080, 42295 and every database port are not reachable
  remotely. Only 80/443 (from Cloudflare ranges), 7881/tcp, 7882/udp and Tailscale answer.
- Fluxer: WebSocket chat and gateway, uploads and downloads, **voice with two real clients** (check
  LiveKit's advertised external IP and the NAT forwarding).
- Overleaf: log in, edit, compile a PDF. TTML: `/health`, an authenticated `/ready`, an
  unauthenticated request rejected, one complete transcription from each client. SPAR: it posts once
  and does not repost old items. Reseed: the journal shows its endpoint id; the dashboard answers
  through the SSH tunnel with the token.
- Containers return after a power-cut simulation: reboot (or `systemctl kill`) and confirm every
  unit above is back without logging in.
- Backups: `systemctl list-timers restic-backups-desu.timer`, then
  `systemctl start restic-backups-desu.service`, then an actual `restic restore` drill. Verify the
  Docker volume names with `docker volume ls` first.
- Workstations: walk `docs/wayfire.md`'s checklist once on real hardware (session, ironbar, OLED mode
  staging, voice/screenshare, one Steam launch). On the desktop, after a Windows update confirm
  `Windows Boot Manager` is still in the boot order (`efibootmgr -o` to fix, never delete the entry).
