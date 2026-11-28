# Secrets

This is a **public repository**. Commit only configuration and paths to secrets. Never commit token
values, password hashes, cookies, private keys, reseed endpoint IDs, origin IP addresses, backup
archives, or recovered application configuration. Nix and container content digests are not secrets.

Keep required deployment files on encrypted removable media while provisioning, then under
`/var/lib/secrets` with mode `0600`. The directory is `root:caddy 0710`. The TTML cookie file is
owned by UID/GID 10001 with mode `0400` or `0600`; all other files are root-owned. Never copy these
files into the repository or a Nix expression: the Nix store is readable by local users.

## Bitwarden

Keep independent vault copies of the server password, LUKS passphrases, recovered Fluxer/SPAR
secrets, GitHub tokens, and any future backup encryption password. Store an offline Bitwarden
recovery code. Automatic restic backups are currently disabled; there are no restic credentials.

The reseed identity is newly generated on the server. Its endpoint ID and private key stay out of
this repository. Record operational identifiers only in the private cheesetool configuration and
an access-controlled vault entry, not in migration notes or command transcripts.

## Server files

The exact required filenames are enforced by `scripts/preflight.py`: the password hash, recovered
Fluxer and SPAR environment files, the GHCR read-only token, a fresh reseed bearer token, four CI
tokens, the origin IPv4 deny-list file, and a reusable preauthorized non-ephemeral Tailscale key.
The optional TTML cookie file is mounted only into the worker.

Use separate GitHub credentials for each role. The two organization CI tokens have organization
Administration write; the two private-repository CI tokens have repository Administration write.
The Nix flake token has Contents read on cheesetool only. The GHCR token has `read:packages` only.
Do not use the broad GitHub CLI login token for server or workstation Nix access.

Copy the staged files while the installer target is mounted at `/mnt`, then run preflight. It checks
presence, modes, the cookie owner, CIDR syntax, and image pins without printing secret contents.
Run `scripts/check-public-secrets.py` before every public commit; it also rejects common credential
formats and reseed endpoint IDs.

## Workstations

The account password hash is required for the greeter and sudo. Workstations run no SSH server;
their OpenSSH clients remain available. Only the server accepts Tailscale SSH, subject to tailnet
policy. Confirm access from another authorized device before removing rescue access.
