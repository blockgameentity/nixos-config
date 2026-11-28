# Who may use ttml.desu.re

Only two clients: **Limusic** and the **Spicy Lyrics** (Spicetify) extension. Two layers:

- **Bearer tokens are the access control.** `TTML_FIXER_PUBLIC_INSTANCE=true` makes every API call
  require `Authorization: Bearer ...`; `/health` is the only open route. Give each client its own
  token (`--owner limusic`, `--owner spicy-lyrics`; one per device if you like) so one can be
  revoked without touching the other. Nobody else has a token, so nobody else can use the API.
- **CORS only matters for browsers.** `TTML_FIXER_CORS_ORIGINS=https://xpui.app.spotify.com`
  (`modules/apps.nix`) lets the Spicetify extension, which `fetch()`es from Spotify's page, read
  responses. Limusic uses native Rust (`reqwest`), so CORS never applies to it. CORS does not
  stop curl or scripts; tokens do. If the extension is blocked, check its real origin in
  Spotify's devtools (`location.origin`) and put exactly that in the setting.

## Creating the tokens

The API refuses to start in public mode until the token DB holds at least one active token, so
`podman exec` (which needs a running container) cannot be the first step. Use a one-off container
with the same image and state directory, as root, after `podman login ghcr.io`:

```console
IMG=$(systemctl cat podman-ttml-fixer-api | grep -o 'ghcr.io/[^ ]*@sha256:[0-9a-f]*' | head -1)
for owner in limusic spicy-lyrics; do
  sudo podman run --rm --entrypoint python -v /var/lib/ttml-fixer:/var/lib/ttml-fixer "$IMG" \
    -m ttml_fixer.admin --api-token-db /var/lib/ttml-fixer/state/api-tokens.sqlite3 \
    token-provision --owner "$owner"
done
```

Each token is printed once; store it in Bitwarden and paste it into the client:
Limusic -> Settings -> TTML Fixer -> `ttml_fixer_token`; Spicy Lyrics -> extension settings ->
bearer token. Revoke with `token-revoke --token-id ID` and the same `--api-token-db`.
Until the first token exists the API unit restarts every few seconds; it recovers on its own.
