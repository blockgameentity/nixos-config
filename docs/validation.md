# Validation performed

- All three hosts (`desu`, `desktop`, `laptop`) evaluate to a derivation with assertions **enabled**
  (`nix eval --raw .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath`). The
  assertion that mattered: `services.displayManager.defaultSession = "wayfire"` needs
  `services.displayManager.sessionPackages = [ wayfire ];` or SDDM offers no session at all. This is
  still not a build/boot test: nothing was compiled or started.
- Generated Caddy configuration built and `caddy adapt` passed using the pinned Nixpkgs Caddy.
  Certificate loading and live TLS were NOT tested (runtime certificate files are not available here).
- Fluxer `docker compose config --quiet` passed using synthetic environment values; no services started.
  Run against the vendored bundle plus the behind-a-proxy overlay, which also proves the edge
  publishes exactly one loopback port (`127.0.0.1:42295 -> 8080`) and LiveKit the two public ones.
  See `docs/fluxer.md` for the exact command.
- SPAR `nix flake check --no-build` passed for x86_64-linux in a clean temporary source-only directory.
  ARM output and actual image builds/Go/Paddle runtime were not tested.
- Nix language-server diagnostics are unavailable in this environment; Nix's evaluator was used directly.

Outstanding: target hardware generation, real image digests, full system build/boot, database restore
rehearsal, live firewall tests (including Docker forwarding and IPv6), application smoke tests,
backup automation and CI controller implementation/penetration tests. See README and runner-plan.
