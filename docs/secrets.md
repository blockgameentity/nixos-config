# Secrets

How secrets for this repo are stored, copied between machines, and recovered. Written for one
person with three machines and a Bitwarden account - not for a team.

Nothing secret is ever in this repository. Git holds only *paths* to secrets
(`hashedPasswordFile`, `tokenFile`, `environmentFile`, `sops`-style references), and
`.gitignore` blocks `*.env`, `*.pem`, `*.key`, `secrets/`. `scripts/preflight.py` fails the
deploy if a placeholder is still there instead of a real path.

## The three tiers

### Tier 1 - Bitwarden (the source of truth)

Everything that can be copied or regenerated lives in Bitwarden. Suggested items:

| Item | Type | Notes |
| --- | --- | --- |
| `desu` login / sudo password | login | The weak one. Only reachable locally or over the tailnet. |
| LUKS passphrase - laptop | note | Distinct per machine, see "Do not reuse" below. |
| LUKS passphrase - desktop | note | Distinct per machine. |
| restic repository password | note | Needed to *read* the backups. Losing it loses the backups. |
| restic S3/R2 credentials | login | Access key + secret for the backup target. |
| Cloudflare Origin CA key + cert | certificate | Record the expiry date in the item. |
| CI token (fine-grained GitHub) | login | Rotate quarterly; the server reads it from `/var/lib/secrets/ci-token`. |
| Tailscale auth key | note | One-off, ephemeral. Store the *ability* to mint one, not the key. |
| `fluxer.env`, `ttml.env` contents | secure note / attachment | Application keys. Losing Fluxer's encryption keys loses the data. |
| SPAR `config.toml` + `spar.env` | secure note | Bot config and tokens. |
| Bitwarden recovery code | note, offline copy | See tier 3. |

Two-factor is deliberately not part of this setup (by owner preference). The consequence is that
**the master password is the only barrier to everything above**. So it has to be long and unique,
and it has to exist on paper somewhere outside the vault.

### Tier 2 - on the machine, `/var/lib/secrets`

Root-owned, `0600` (`/var/lib/secrets` itself `0710 root:caddy`, the `cloudflare/` subdirectory
`0750 root:caddy` with `0640` files - Caddy has to be able to read the origin certificate and
nothing else). `README.md` lists every file and which service reads it.

Provision while the target is still mounted at `/mnt`:

```console
install -d -m 0710 /mnt/var/lib/secrets
install -m 0600 /dev/stdin /mnt/var/lib/secrets/desu-password-hash   # paste hash, Ctrl-D
```

`desu-password-hash` is needed on **all three hosts**, not just the server: without it the account
is locked and `sudo` rejects every password. The workstations' autologin hides this until the first
`sudo` or the first SSH login.

### Tier 3 - offline, non-digital

On paper, in a drawer or a safe, outside both the vault and the machines:

- Bitwarden master password + recovery code.
- LUKS passphrase for each machine.
- restic repository password.

The failure this prevents: the only copy of the vault password is inside the machine that will not
unlock, or the only copy of a backup password is inside the backup.

## Generating values

| Secret | Command |
| --- | --- |
| password hash | `nix run nixpkgs#mkpasswd -- -m yescrypt` (produces `$y$j9T$...`) |
| random tokens/API keys | `openssl rand -base64 48` (or `nix run nixpkgs#openssl -- rand -hex 32`) |
| LUKS passphrase | five to seven random words, typed at boot. Do not generate it with a tool you then have to store. |

`mkpasswd` output is a crypt(3) hash, **not** a SHA-256 of the password: salted, slow, memory-hard
(yescrypt). A bare `sha256sum` of a password is neither a valid `/etc/shadow` entry nor safe - PAM
would reject it and you would lock yourself out. The hash is one-way but not uncrackable: a weak
password behind a leaked hash falls in seconds, which is why the file is root-only.

Never use `users.users.desu.password = "..."` - plaintext ends up world-readable in the Nix store.

## Do not reuse one password everywhere

Using the same string for Bitwarden, LUKS and restic collapses three independent failures into one:

- **LUKS is crackable offline.** Anyone who copies the disk image can attack the passphrase at
  billions of guesses per second with no rate limit. The same string in the vault means that one
  result also opens the vault.
- **The vault is the other side of it.** A service breach only hands over a hash; if it is the same
  string as the disk passphrase, that hash is a disk passphrase candidate too.
- **restic is the third copy.** The repository password protects the backup of `/var/lib/secrets`,
  so reusing it means the backup protects its own key.

Minimum sensible split:

| Purpose | Kind | Where it lives |
| --- | --- | --- |
| Bitwarden master | long passphrase, unique, never used elsewhere | head + paper |
| LUKS (per machine) | long passphrase, unique per machine | head + paper |
| Everything you never type (restic, CI, API keys, app `.env`) | random 40+ chars | Bitwarden only |

Rules of thumb: secrets you *type* are passphrases you memorise; secrets you *paste* are random and
live only in the vault. The weak `desu` sudo password is fine for its purpose (rate-limited console
or tailnet login, and it protects nothing else) - it must never be reused for the three above.

## The lock-screen problem

Autologin means the disk passphrase is the only password typed at boot; afterwards the session lock
is the only barrier. A four-letter password defeats that barrier in minutes, so on a stolen,
suspended laptop the session is the weak link, not LUKS.

What is in place: `security.pam.services.login.failDelay` and `.sshd.failDelay` (3 s per failed
attempt), which turns four letters into days of typing.

What actually fixes it, in order of effect:

1. Give the laptop account a real password (it does not have to equal the server's weak one).
2. Make the laptop hibernate instead of suspending, so the LUKS key leaves RAM and resuming needs
   the disk passphrase:
   ```nix
   systemd.sleep.extraConfig = ''
     [Sleep]
     HibernateDelaySec=30min
   '';
   ```
   `systemctl suspend` then hibernates after 30 idle minutes. Requires hibernation to work first -
   see `docs/remaining-work.md`.
3. Shorten the idle timeout before the session locks and the screen blanks.

## Copying secrets between machines

- Preferred: `scp` over the tailnet, or from Bitwarden attachments.
- Also fine: a USB stick you control, deleted afterwards.
- Never: chat, email, a public gist, a shell history (`HISTIGNORE='*secret*'`, or prefix a command
  with a space if `HISTCONTROL=ignorespace`).
- The password hash is not confidential in the same way as a key, but treat it as tier 1 anyway
  while the password behind it is weak.

## Rotation

| Secret | When |
| --- | --- |
| Tailscale auth key | one-off per install; mint a new one, real keys expire |
| Cloudflare Origin CA cert | before its expiry; then `systemctl restart caddy` |
| CI token | quarterly, or whenever the runner image changes hands |
| restic credentials | on any suspicion of backup-target compromise |
| `desu` password | if it ever stops being tailnet/console-only |
| LUKS passphrase | not rotatable without re-encrypting (`cryptsetup luksChangeKey` is fine: it re-wraps the key slot, no re-encryption) |

## Backups of the secrets themselves

`modules/backup.nix` lists `/var/lib/secrets` among restic's default paths, so turning on
`desu.backup.enable` is the difference between "these files exist on one disk" and "these files
also exist, encrypted, somewhere else". Without it, a disk failure or a reinstall means
regenerating every credential on the server - and some of them (Fluxer's encryption keys) cannot
be regenerated at all.

The restic password then protects that copy, so it goes in Bitwarden *and* on paper.
