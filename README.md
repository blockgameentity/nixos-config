# desu.re NixOS migration

NixOS host configuration for `chat.desu.re`, `overleaf.desu.re`, and `ttml.desu.re`.
This is a migration scaffold, **not a tested production deployment**. Two intentional
assertions prevent installation until hardware and local access settings are supplied.
No server data or secret values belong in this repository.

## Layout and choices

- `hosts/desu`: x86_64 host, UEFI boot assumption, SSH keys only, installation-specific settings.
- `modules/edge.nix`: Caddy, Cloudflare-only IPv4/IPv6 web ingress, Origin CA TLS.
- `modules/apps.nix`: rootful Podman OCI containers for Overleaf/TTML, systemd-managed
  Docker Compose for Fluxer. Fluxer's existing health checks and initialization dependency
  graph are retained. No users are added to Docker's root-equivalent group.
- `services/fluxer`: original non-secret configuration; runtime environment file supplies secrets.
- `modules/ci-runners.nix`, `ci/`: implemented disposable KVM controller and guest image.
  `hosts/mac/configuration.nix` is the nix-darwin trusted-runner service. See `ci/README.md`
  for local test results and deployment gates. `local.nix` enables one repository runner;
  replace the placeholder origin IP and token before deployment.
- `docs/runner-plan.md`: CI threat model and authorization requirements.
- SPAR's independent flake is in the sibling extracted `spar-tilbuds-bot-v2` directory;
  push its flake and lockfile to the real upstream repo, then import its NixOS module.

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
Edit `local.nix`: add your real SSH public key, provision the password-hash file for sudo,
set application image references, and remove the local assertion only after reviewing it.
Set timezone/networking to match your actual provider. Stage new files before flake evaluation.

```
git add hosts/desu
nix flake check
nix build .#nixosConfigurations.desu.config.system.build.toplevel
sudo nixos-install --flake .#desu
```

Provision runtime secrets under `/mnt/var/lib/secrets` before first boot, or under
`/var/lib/secrets` on the installed host. Root-only files, not Nix paths/strings containing
secret values. Missing secrets intentionally make affected services fail closed.

- `fluxer.env`: recover the ORIGINAL Fluxer `.env`, do not regenerate its keys.
  Set `FLUXER_DOMAIN=chat.desu.re`, `FLUXER_CADDY_SITE_ADDRESS=:80`, and keep the original
  image version. `LIVEKIT_API_KEY` must match `webhook.api_key` in `livekit.yaml` (currently
  `fluxer`), or update that non-secret identifier. The compose file documents required variables.
- `ttml.env`: original `ttml-fixer/backend/.env`, even if empty.
- `youtube-cookies.txt`: original cookie file, root-readable.
- `desu-password-hash`: a password HASH for the administrator, root-readable.
- `cloudflare/origin.pem` and `cloudflare/origin-key.pem`: Origin CA certificate covering all
  three hostnames and its key. This subdirectory must be traversable by Caddy (root:caddy 0750),
  files root:caddy 0640. The parent `/var/lib/secrets` is root:caddy 0710 (traverse only
  for Caddy). All OTHER secret files must be root:root 0600; Caddy must not read them.
- `tailscale-auth-key`: one-off Tailscale auth key for a persistent, preauthorized server
  node, root:root 0600. Use appropriate tailnet ACL/tagging. Enrollment preserves your
  existing OpenSSH key workflow; SSH is allowed only on tailscale0, not the public Internet.
- `ci-token`: repository-scoped fine-grained GitHub token with Administration:write for
  runner management, root-readable only. `local.nix` currently enables ExamWatcher/desktop.
  Replace `blockedIPv4` with the server's real origin IP(s) before deploying. Read `ci/README.md`.

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

TTML backend: build the original `ttml-fixer/backend/Dockerfile` with its original build context
on a build machine, publish with a digest or `podman save`/rootful `podman load` on the server.
Set `desu.images.ttml` accordingly. A local image is not automatically built by NixOS.
Rootless and rootful Podman have different image stores. Persist cache at `/srv/ttml/cache`.
No GPU is configured; inspect CPU inference RAM/latency before adding CI workloads.

The existing Overleaf image enables shell escape: keep registration restricted and treat
LaTeX compilation as untrusted execution inside the application container. This setup is
not a safe public multi-tenant compilation sandbox. Mongo 6 and Redis 6 are retained only
for migration compatibility; plan supported-version upgrades separately after backup testing.

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
Check LiveKit's advertised external IP, NAT forwarding and real two-client calls. SSH remains
public key-only on 22 but is allowed only on tailscale0. Provision the auth key before first
boot for headless enrollment; public SSH is not available as a fallback. Confirm tailnet SSH
from a second device before disconnecting rescue access. CI already blocks 100.64.0.0/10.

## Acceptance tests / backups

- `nixos-rebuild build --flake .#desu`, then test in a restore VM before switching production.
- `systemctl --failed`, `journalctl -u fluxer -u caddy`, container health and Mongo primary.
- Off-network direct origin HTTP/HTTPS (IPv4 AND IPv6) denied; Cloudflare URLs work.
- WebSocket chat/gateway, upload/download, voice, Overleaf editing and PDF compilation,
  TTML health and one complete transcription, bot state if enabled.
- Confirm ports 1337/8000/42295 and all DB ports are inaccessible remotely.
- Reboot and repeat. Confirm restored data survives container restart.
- Establish scheduled, encrypted off-host backups with tested retention and restore drills.
  Restic is installed but no backup timer is enabled: destination/credentials/consistency
  policy have not been supplied. NixOS rollback does NOT roll back databases or container images.

## SPAR module integration (after pushing)

Add an input `spar.url = "github:YOUR-OWNER/YOUR-REPO/REV"`, import
`spar.nixosModules.default`, set `services.sparBot.enable = true` and `.image` to the built
digest. Restore data/config.toml to `/srv/spar`, and env to `/var/lib/secrets/spar.env`.
The bot flake wraps the existing Dockerfile; it is not a native/reproducible PaddleOCR package.
Run it from a clean Git checkout after pushing, NEVER directly from this extracted directory:
Nix can copy untracked runtime files/secrets into its world-readable store for non-Git flakes.
The image build context itself explicitly includes only source/build files.
