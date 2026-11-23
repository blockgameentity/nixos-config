# Fluxer on the server

Fluxer is the one service in this repository that is **not** written from Nix: it is the
upstream self-hosting Docker Compose stack, vendored verbatim under `services/fluxer/` and
started by one systemd unit (`modules/apps.nix`). This file records where those files came
from, what they change compared to the hand-rolled file this branch used before, and the
upgrade/restore order that keeps a migration from turning into an unrecoverable jump.

## Provenance

| | |
| --- | --- |
| Bundle | `https://fluxer.dev/compose/latest` (stable alias, moves with each release) |
| Fetched | 2026-11-20 bundle, vendored 2026-11-23 |
| Images | `ghcr.io/fluxerapp/fluxer-*` **pinned by digest** inside `docker-compose.yml` |
| Upstream docs | <https://docs.fluxer.com/operator/docker-compose/> |

Files, all copied unmodified:

- `docker-compose.yml` — the stack (21 services).
- `docker-compose.proxy.yml` — the upstream overlay for "another web server owns 80/443".
  `modules/edge.nix` terminates TLS with the Cloudflare Origin CA certificate and forwards
  to the address in `desu.fluxer.edgeBind` (`127.0.0.1:42295`), exactly as it did for the
  old in-compose Caddy.
- `Caddyfile` — upstream edge configuration (the container is Caddy, the *service* is `edge`).
- `.env.example` — upstream's own environment reference, 2700+ lines. It is vendored because
  it is the only complete description of the contract; the compose file alone no longer lists
  what is required.
- `caddy.d/sites/`, `certs/`, `ca/` — empty mount points upstream's `edge` service expects.

## Why vendored and not rexctl

Upstream moved self-hosting to `rexctl` (`deploy/self-hosting/README.md` in the Fluxer repo is
now a one-line pointer). `rexctl` installs Docker itself, owns `/opt/fluxer`, writes its own
systemd units and runs its own backup/upgrade timers. On this host all four of those are
already owned by something else (NixOS, `/var/lib/secrets`, restic, `nh os switch`), so the
compose bundle — which upstream still publishes and documents as the manual path — is the
right fit. `rexctl takeover --dir <folder>` is the escape hatch if that ever changes; it adopts
an existing compose instance without downtime.

The consequence of this choice: **upgrades are manual**. Nothing pulls a new `v1` tag behind
your back, and no timer upgrades Fluxer at 04:00. See "Updating" below.

## What changed against the previous file

The old `compose.yaml` + `Caddyfile` + `livekit.yaml` tripped several upstream changes at once:

| Old | New | Why it matters |
| --- | --- | --- |
| `caddy` service, `FLUXER_CADDY_SITE_ADDRESS` | `edge` service, `FLUXER_EDGE_*` | Caddyfile rewritten: `trusted_proxies_strict`, `header_up X-Forwarded-For {client_ip}`, `/.well-known/webfinger`, `/_health`, `/_edge`, `import /etc/caddy/conf.d/*.caddy`. `/fonts/*` and `/embeds/*` are no longer static-proxy paths. |
| 5 extra `*-shard` containers | gone; `FLUXER_SVC_MODE: combined` | The service containers are now Rust binaries that serve router and shard in one process. 25 containers became 21 while adding the push service. |
| — | `push` | New FCM/APNs relay. Harmless unconfigured (a bundled relay is used by default). |
| `livekit.yaml` (mounted file) | `LIVEKIT_CONFIG` env block | The voice config now lives in the compose file; `livekit.yaml` is deleted. Keys and ports are unchanged, so `modules/edge.nix`'s TCP 7881 / UDP 7882 stay correct. |
| `image: ghcr.io/...:v1` | `image: ghcr.io/...@sha256:...` | Previously the default tag was the moving `v1`, so a `docker compose pull` could jump an arbitrary number of releases. Now the repo pins what it runs, and an upgrade is a visible digest diff in git. |
| valkey 8.1, meilisearch 1.12, seaweedfs 4.34, caddy 2.10 | valkey 9.1, meilisearch 1.53, seaweedfs 4.52, caddy 2.11 | Cache, search index and object store are all cross-version jumps. See "Updating". |
| no memory limits | `deploy.resources.limits` per service | Compose v2 honours these outside Swarm. `modules/memory.nix` sizes zswap for the host; these are per-container ceilings. |
| `${VAR:?set …}` for 16 secrets | one gate: `FLUXER_SETTINGS_LOADED` | Compose no longer fails on a missing secret; the API does, later and less clearly. The unit sets the gate (see below). |
| `FLUXER_SVC_SHARD_ID`, `FLUXER_S3_BUCKET_DOWNLOADS`, `FLUXER_LIVEKIT_WEBHOOK_URL`, `FLUXER_INTERNAL_GATEWAY_ENDPOINT`, `FLUXER_ADMIN_HOST`, `FLUXER_APP_PROXY_HOST`, `FLUXER_MEDIA_PROXY_HOST`, `FLUXER_S3_BUCKET_DOWNLOADS`, `NODE_ENV`, `AWS_*` | removed | Leftovers in `fluxer.env` are ignored, not rejected. |

`FLUXER_S3_ACCESS_KEY`, `MEILI_MASTER_KEY`, `POSTGRES_PASSWORD`, `LIVEKIT_API_KEY` and
`LIVEKIT_API_SECRET` kept their names, so the secrets recovered from the old instance still
feed the right variables.

The gateway is now a BEAM application: it authenticates nodes with `FLUXER_ERLANG_COOKIE` and
requires `ulimits` for file descriptors. That secret did not exist before and has no
"correct" historical value — it only has to be the same for every gateway node, so generate
a fresh one.

## Environment file

`/var/lib/secrets/fluxer.env` is `--env-file` for Compose and holds **secrets only**. The
non-secret settings live in Nix (`modules/apps.nix`), because Compose gives the process
environment precedence over `--env-file`:

| Set by the unit | Value |
| --- | --- |
| `FLUXER_SETTINGS_LOADED` | `true` — the gate the bundle refuses to start without |
| `FLUXER_DOMAIN` | `desu.fluxer.domain` (`chat.desu.re`) |
| `FLUXER_PUBLIC_SCHEME` / `FLUXER_PUBLIC_PORT` | `https` / `443` |
| `FLUXER_EDGE_BIND` | `desu.fluxer.edgeBind` (`127.0.0.1:42295`) |
| `FLUXER_EDGE_PROTOCOLS` | `h1 h2` — h3 would need UDP/443 published, which the host proxy does not do |

So a stale `FLUXER_DOMAIN=` or `FLUXER_CADDY_SITE_ADDRESS=` line left in `fluxer.env` from the
old install is ignored, not a surprise 404 later.

Required in `fluxer.env` (all of these are in `services/fluxer/.env.example`, with the
description of what breaks if they change):

```console
POSTGRES_PASSWORD=            # openssl rand -hex 32
MEILI_MASTER_KEY=
FLUXER_S3_ACCESS_KEY=fluxer   # fixed for the bundled object store
FLUXER_S3_SECRET_KEY=         # letters and digits only
LIVEKIT_API_KEY=fluxer
LIVEKIT_API_SECRET=           # >= 32 chars
FLUXER_SUDO_MODE_SECRET=
FLUXER_CONNECTION_INITIATION_SECRET=
FLUXER_PROFILE_PSEUDONYM_SECRET=
FLUXER_GATEWAY_RPC_AUTH_TOKEN=
FLUXER_ERLANG_COOKIE=
FLUXER_MEDIA_PROXY_SECRET_KEY=
FLUXER_ADMIN_SECRET_KEY_BASE=
FLUXER_ADMIN_OAUTH_CLIENT_SECRET=
FLUXER_MEDIA_PROXY_UPLOAD_RELAY_SECRET_BASE64=   # openssl rand -base64 32
FLUXER_VAPID_PUBLIC_KEY=
FLUXER_VAPID_PRIVATE_KEY=
FLUXER_SETUP_TOKEN=           # only needed to create the first admin in a browser
FLUXER_ACTIVITYPUB_SIGNING_KEY_BASE64=           # may be empty: fediverse unfurls go unsigned
```

Recovered from the old instance, unchanged: `FLUXER_SUDO_MODE_SECRET`,
`FLUXER_CONNECTION_INITIATION_SECRET`, `FLUXER_GATEWAY_RPC_AUTH_TOKEN`,
`FLUXER_MEDIA_PROXY_SECRET_KEY`, `FLUXER_ADMIN_SECRET_KEY_BASE`,
`FLUXER_ADMIN_OAUTH_CLIENT_SECRET`, `FLUXER_MEDIA_PROXY_UPLOAD_RELAY_SECRET_BASE64`, the
`FLUXER_VAPID_*` pair and the two LiveKit values. Regenerating any of them logs users out or
invalidates stored material; `docs/secrets.md` has the policy.

New, generated once: `FLUXER_PROFILE_PSEUDONYM_SECRET` and `FLUXER_ERLANG_COOKIE`. Both are
`openssl rand -hex 32` and must never change after the first start.

## Updating

The bundle is pinned, so an update is a deliberate four-step:

```console
curl -fsSL https://fluxer.dev/compose/latest -o /tmp/fluxer-compose.tar.gz
mkdir -p /tmp/fluxer-bundle && tar -xzf /tmp/fluxer-compose.tar.gz -C /tmp/fluxer-bundle
diff -u services/fluxer/docker-compose.yml /tmp/fluxer-bundle/docker-compose.yml
diff -u services/fluxer/docker-compose.proxy.yml /tmp/fluxer-bundle/docker-compose.proxy.yml
diff -u services/fluxer/Caddyfile /tmp/fluxer-bundle/Caddyfile
```

Then copy the changed files, re-read the digest diff (that is the actual version change), take
a restic backup, and `sudo systemctl restart fluxer`. Two things in the diff to read rather
than skim:

- **Image digests.** A base-image jump (Postgres major, Meilisearch, SeaweedFS) is a database
  upgrade, not a restart. Take a backup that you have restored once before you accept it.
- **New required keys.** Grep the new bundle for `${FLUXER_…:?` and for
  `services/fluxer/.env.example`'s uncommented `KEY=` lines; anything new goes into
  `fluxer.env` before the restart.

Upstream's own upgrade notes (`https://docs.fluxer.com/operator/running/`) describe what
`rexctl upgrade` does automatically: back up, upgrade, roll back to the previous version if
the new one does not start. With compose that is manual, which is why the backup in
`modules/backup.nix` stops Fluxer first.

### Database steps baked into this bundle

- **Meilisearch 1.12 → 1.53.** The compose file sets `MEILI_UPGRADE_DB=true`, which is the
  supported path (v1.12 is the oldest version Meilisearch can still migrate). If it refuses,
  the index is disposable: `docker compose rm -sf meilisearch`, delete the
  `fluxer_meilisearch-data` volume, start it again and rebuild the indexes from the admin
  panel's Jobs → Search indexes page.
- **SeaweedFS 4.34 → 4.52.** Buckets are created by `seaweedfs-init` on every start, so an
  existing store just keeps its data; no migration step.
- **Valkey 8.1 → 9.1.** Configured with `--save "" --appendonly no`: it is a cache, so a
  restart empties it by design. Rate limits and presence start over.
- **Postgres 16 → 16.** No dump/restore needed between releases; schema migrations run when
  the API starts.

### Migrating the old instance into this stack

Do not combine that with the OS migration. The order that can be retried:

1. Restore the old volumes/dump while the *old* digests are still what the repo pins (or, in a
   throwaway VM, while the old `compose.yaml` from git history is used).
2. Confirm the instance serves, then take a fresh backup of *that*.
3. Only then move to the current bundle and let the API run its migrations, watching
   `journalctl -u fluxer -f` and `docker compose logs -f api`.

The old `.env` was recovered, not regenerated — that is what keeps attachments and sessions
valid. A dump taken with a much older schema restored straight into the current API is the one
step that must be rehearsed, not assumed: `pg_restore` first, then start `api` and read its
migration output before exposing the instance.

## Validating without starting anything

```console
docker compose --project-name fluxer --env-file /tmp/fluxer-test.env \
  -f services/fluxer/docker-compose.yml -f services/fluxer/docker-compose.proxy.yml config --quiet
```

With any synthetic values for the secrets, this proves the file, the overlay and every
interpolation resolve. It is what `docs/validation.md` records. The overlay's `!override` tag
is valid Compose but unknown to yaml-language-server, which reports it as an unresolved tag;
that is a tool limitation, and the reason `services/fluxer/` is exempted in `.yamllint.yml`
rather than reformatted.

To see what the stack would publish, drop `--quiet` and read `services.edge.ports` (one
loopback mapping: `127.0.0.1:42295 → 8080`) and `services.livekit.ports` (7881/tcp, 7882/udp —
the only deliberately public ports, matched in `modules/edge.nix`).
