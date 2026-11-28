# cheesetool reseed node

The server runs `services.cheesetool-reseed` from the private `cheesetool` flake
(`nixosModules.reseed`). It is a relay-only Iroh endpoint: outbound connections only, so
nothing is opened in the firewall. State lives in `/var/lib/cheesetool-reseed` (0700,
user `cheesetool-reseed`).

## Fresh identity (decided: nothing is migrated from the old server)

The old Docker volume (~350 GB archive, fjall DB, blobs, identity key) is **not** backed up
or restored. The archive is re-downloaded: the first run starts `bootDelaySecs` (300 s)
after boot. The service creates a new `iroh-endpoint.key` on first start, so the endpoint
id changes. Never record the old or new endpoint ID in this public repository; keep it
only in the private cheesetool configuration and your password manager.

After the first start, read the new id and update the pinned destination in the helper
(`crates/cheesetool-p2p/src/p2p/reseed.rs`, `DEFAULT_RESEED_DESTINATIONS`), then rebuild
and redistribute the helper. Until then clients dial the dead old id:

```console
journalctl -u cheesetool-reseed | grep -i 'endpoint id'
```

From then on the key is the identity; the module never regenerates it while the file
exists. It is deliberately not in `modules/backup.nix`.

## Operator API

Bound to `127.0.0.1:8080` with a bearer token (`/var/lib/secrets/cheesetool-reseed-token`,
`openssl rand -hex 32`, root-only). Reach it with
`ssh -L 8080:127.0.0.1:8080 desu` or over Tailscale SSH, then open `http://127.0.0.1:8080/`.

## Private flake input

The input is `github:blockgameentity/cheesetool?ref=plan/vapor-forge-windows-host` because
`flake.nix` is not on `main` yet. Every machine that evaluates this flake needs a GitHub
token in Nix's `access-tokens` (`~/.config/nix/nix.conf`, mode 0600 - never in the Nix
store or this repository):

```console
access-tokens = github.com=<fine-grained token, read-only Contents, cheesetool only>
```

Use a separate narrowly scoped token on each machine; never use the broad GitHub CLI login token.
During `nixos-install` export it first:
`export NIX_CONFIG='access-tokens = github.com=<token>'`. CI reads it from the Actions
secret `NIX_ACCESS_TOKEN`.
