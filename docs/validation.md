# Validation performed

- NixOS assertions evaluated: only the two intentional installation gates fail (hardware and local settings).
- Entire NixOS system derivation evaluated successfully with assertions disabled for that evaluation only.
  The repository itself retains the safety assertions. This is not a full OS build/boot test.
- Generated Caddy configuration built and `caddy adapt` passed using the pinned Nixpkgs Caddy.
  Certificate loading and live TLS were NOT tested (runtime certificate files are not available here).
- Fluxer `docker compose config --quiet` passed using synthetic environment values; no services started.
- SPAR `nix flake check --no-build` passed for x86_64-linux in a clean temporary source-only directory.
  ARM output and actual image builds/Go/Paddle runtime were not tested.
- Nix language-server diagnostics are unavailable in this environment; Nix's evaluator was used directly.

Outstanding: target hardware generation, real image digests, full system build/boot, database restore
rehearsal, live firewall tests (including Docker forwarding and IPv6), application smoke tests,
backup automation and CI controller implementation/penetration tests. See README and runner-plan.
