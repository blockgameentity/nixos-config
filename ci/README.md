# Disposable runners — implementation

## Linux

`modules/ci-runners.nix` creates dedicated unprivileged controller users, fixed tap devices,
host firewall/NAT, and one controller per slot. `ci/controller.py` requests a GitHub JIT
configuration, journals the runner ID, creates a fresh qcow2 overlay and starts QEMU.
`ci/guest.nix` runs Docker and the GitHub runner only. The guest powers off after the job;
the controller kills timed-out guests, removes writable disks, and deregisters runners.

The management token is host-only and loaded via a systemd credential. Only the short-lived
JIT blob enters the guest, through QEMU fw_cfg. Guest shell access to JIT data is expected:
jobs need runner credentials for the duration of their job. It is never persisted in Git/Nix.

This is a **repository runner** implementation. Copy/import the module with another service
scope to implement organization runners; do not assign one repository runner to other repos.
A fine-grained token needs repository **Administration: write**, which GitHub requires for
runner registration/removal. This is broad: use a dedicated credential, rotate it, and keep
it away from the guest. A scoped GitHub App can replace it in a subsequent controller change.
Group 1 is GitHub's Default runner group for repository JIT registration. Workflow restrictions
for public contributors must be enforced separately; labels are not authorization.

The host nft policy drops all guest-to-host traffic, guest-to-guest/private/metadata traffic,
IPv6, and configured public origin ranges. Only public TCP 80/443 and two public DNS servers
are accepted, with stateful replies. Rebooting/restarting `ci-network` reinstates rules before
bringing taps up. No privileged containers or host runtime sockets are mounted into the guest.

## Enable after supplying actual addresses

```nix
services.disposableRunners = {
  enable = true;
  repository = "ExamWatcher/desktop";
  tokenFile = "/var/lib/secrets/ci-token";
  blockedIPv4 = [ "YOUR.PUBLIC.ORIGIN.IP/32" ];
  count = 1; # 4 CPUs, 12 GiB RAM, 80 GiB virtual disk, one hour per job by default
};
```

The module refuses enabling without an explicit origin block. Use the actual IP, not the
documentation example in `local.nix`. Include other owned/infrastructure IPs as appropriate.
Set a repository Actions runner-group/workflow policy before allowing untrusted jobs; ensure
fork jobs cannot access private dependency credentials. Check firewall forwarding on the
actual host with Docker/Podman active. An arbitrary public proxy can still reach public sites;
origin-IP blocking is not a full application-egress filter.

## Mac

`darwinConfigurations.ci-mac` creates a dedicated `ci` user and a real launchd daemon.
`ci/mac.py` requests a single-run JIT runner, runs it in a job-specific directory, then
removes that directory and registration. Token and workspace are outside the Nix store.
The default macOS architecture is `aarch64-darwin`; it can build both macOS architectures
using the workflow's existing cross targets. Xcode/Apple SDK and signing are still installed
through Apple tooling, not Nix. rustup/Bun are provided; workflows may also provision their own.

Enable `services.trustedMacRunner` only after registering for trusted repository/workflow use.
The safety option `trustedRegistrationConfirmed` is an explicit acknowledgement, not a technical
authorization control. This is cleanup and repeatability, **not disposable macOS VM isolation**.
Do not use it for arbitrary fork code or releases/builds sharing sensitive credentials with
untrusted jobs. Migrate to a new Apple Silicon Mini by applying the same configuration,
installing Xcode, creating the token file, and removing old runner registrations.

## ARM64 Linux workflow

The disposable host is x86_64. Cross-building the Linux ARM64 Tauri bundle requires ARM64
WebKit/GTK libraries, pkg-config sysroot, linker and packaging tooling; merely adding a Rust
target is insufficient. QEMU user emulation can run selected tests, but does not supply these
libraries. Do not point the ARM64 workflow at the x86_64 runner until its recipe is validated
end-to-end. The original native ARM runner must remain until then. No successful ARM bundle
is claimed by this implementation.

## Tests and deployment gates

`python3 -m unittest discover -s ci` tests lifecycle and recovery. Full NixOS and enabled
nix-darwin derivations evaluate. The generated firewall has been installed and inspected in
an isolated network namespace. The guest image built and booted under KVM: ci-network, Docker,
and ci-job started, then the VM powered off when the synthetic runner process exited.

Actual GitHub JIT registration, end-to-end job containers, macOS launchd execution, signing,
and full ARM64 application bundles still require target credentials/machines. An additional
isolated packet test (`test_firewall_traffic.py`) passed for allowed HTTP and blocked SMTP,
host, private LAN and IPv6. The desktop repository now has a cross-sysroot recipe whose
AArch64 GTK/WebKit link test passed; its full private application build has not been run.

The isolated firewall test requires a generated rules file (available after building the host):

```sh
CI_FIREWALL_RULES=/path/to/ci-firewall.nft \
  unshare --user --map-root-user --net python3 ci/test_firewall.py
```
