# What remains

## Completed locally

- Disposable KVM controller/guest, lifecycle tests, and nix-darwin launchd configuration.
- Generated nft policy installs in an isolated namespace. The packet test confirms public
  HTTP works while SMTP, host/router, private-LAN and IPv6 access are blocked.
- All ExamWatcher API workflows inspected. Their persistent cache assumptions are recorded;
  they remain on the trusted `ew-ci` runner, not redirected to untrusted disposable VMs.
- `scripts/preflight.py` checks required files, secret permissions, image/origin settings
  and installation placeholders. Its unit tests cover Caddy's special group-read exception.
- ExamWatcher desktop `.github/ci/setup-linux-arm64-cross.sh` now creates a separate ARM64
  Ubuntu WebKit/GTK sysroot and tests a real AArch64 linked executable. The ARM64 workflow
  is wired to the X64 runner. This is a working toolchain prerequisite, NOT a claim that the
  full private application or its AppImage/deb have built successfully.

## You must supply/do on the real machines

1. Before wiping: inventory the live server and make verified off-host backups/restores.
   Only the live system can reveal actual volume names, image digests and remaining services.
2. Generate target hardware configuration with `nixos-generate-config`; choose partitioning/UEFI.
3. Supply local console/sudo password hash, actual public origin IP, Cloudflare Origin CA
   certificate/key, original Fluxer/TTML environment and cookies, and pinned image digests.
   Supply a one-off Tailscale auth key for headless enrollment. Tailscale SSH uses OAuth;
   OpenSSH is disabled and the local password is not accepted for SSH.
   Confirm SSH from another tailnet device before removing rescue-console access.
4. Build/push/load the TTML image on a machine with its full build context. Push the SPAR
   flake to its real repository, then supply the image and original data/config.
5. Install and boot the NixOS host; restore databases/files; run live service/network tests.
6. Create a repository-scoped GitHub token with Administration:write for runner management.
   Put it at `/var/lib/secrets/ci-token` (0600 root). Configure GitHub runner/workflow access
   before allowing external contributor jobs. Test a real JIT job and cancellation.
7. Apply the Mac configuration with nix-darwin, install Xcode/Apple SDKs, provision signing
   identities/keychains, create the trusted runner token file, and validate signing/notarization.
   Keep untrusted jobs off this non-VM Mac runner.
8. Push the ExamWatcher desktop sysroot/workflow changes after review; run its ARM64 release
   workflow with the existing private dependency secret. Verify the complete Rust/Tauri
   compilation, AppImage/deb packaging and an ARM64 runtime test before retiring the ARM runner.

After settings are supplied, run (with the actual public origin IP):

```sh
python3 scripts/preflight.py --origin YOUR.PUBLIC.IPV4
```

Passing this check does not prove backups, certificate validity, GitHub authorization,
hardware compatibility, or application recovery. These require the actual systems/secrets.
