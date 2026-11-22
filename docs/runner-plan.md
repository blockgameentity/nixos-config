# CI architecture — design, not yet deployed

## Evidence

Reviewed `~/Desktop/proj/examwatcher/desktop/.github/workflows/{ci,build,release}.yml`.
The API and other private repositories have NOT been inspected.

- Most Linux jobs use `container: ubuntu:24.04`, apt, Rust and Bun. Preserve those job containers initially; use Docker inside the guest, not a host socket.
- Windows release binaries are cross-compiled with cargo-xwin from Linux. Native Windows tests use GitHub-hosted Windows runners on manual dispatch.
- Linux ARM64 currently targets `ew-ci`, evidently an ARM machine. An x86 VM cannot run this unchanged. Keep the ARM runner, or explicitly port to cross-compilation/QEMU (slower, needs testing).
- macOS build/notarization and canaries require the separate Apple Silicon Mac.
- Linux PR jobs depend on `secrets.TEST` for private Git dependencies. Fork PRs do not receive this secret. Never fix this using pull_request_target plus checkout of contributor code.
- Release publishing has R2, Ed25519 signing, API publishing and possibly Windows signing credentials. Build artifacts and caches from untrusted runs must not feed releases.

## Architecture

NixOS production host → KVM/QEMU disposable NixOS guest → Docker → Ubuntu job container.
Nix defines the guest OS, runner runtime, Docker, resource limits and network policy.
A host-side controller obtains one-job GitHub JIT registrations and creates fresh VM writable disks.
It destroys the entire guest disk after success, failure, timeout, cancellation or host restart.
The runner's ephemeral flag alone is NOT disk cleanup or a complete lifecycle controller.

Do not install a long-lived GitHub runner on the production host. Do not expose host
Docker/Podman sockets, /nix/store writable shares, host SSH agent, production mounts,
controller credentials, or signing keys to contributor VMs. QEMU runs unprivileged with
only its own disks and /dev/kvm; no privileged host container wrapper.

Use a small dedicated GitHub App scoped to selected repositories to mint JIT configs.
The App private key stays on the controller. Repository registration/runner management
permissions should be the minimum required by the chosen GitHub endpoint. A guest
receives only its short-lived single-run registration, via a per-VM credential channel,
never an App key or broad PAT. Do not persist JIT data in the Nix store or logs.
Check API availability/permissions for repository versus organization runners before implementation.

### Pools and authorization

1. **Contributor:** public PRs; no private dependency credentials, no releases, no shared writable caches.
2. **Trusted build:** reviewed branches/private builds; narrowly scoped read-only dependency access if required.
3. **Release:** protected environment approval; allowlisted release workflow/ref; publishing credentials only here.

Labels such as `ci-public-x64`, `ci-trusted-x64`, `ci-release-x64` describe scheduling,
NOT authorization. Use runner-group selected-workflow restrictions where supported by
GitHub plan/scope. If restrictions are unavailable, place privileged release workflows
and runners in a separate locked-down release repository. Do not expose a privileged
runner to a public repository merely by giving it a different label.

Releases build from verified protected commits. Do not promote arbitrary PR artifacts
or allow `workflow_run` to download and execute contributor-controlled output with secrets.
Use environment approvals, minimal GITHUB_TOKEN permissions, action commit pinning,
`persist-credentials: false`, and explicit job timeouts.

## Network policy

Enforce on the HOST for traffic originating on the guest tap/bridge, before NAT;
guest firewall rules are not a boundary because a job can control its Docker guest.
Use a dedicated non-production bridge with no access to production container bridges.

- Deny guest → host INPUT, except a specifically isolated DNS service if used.
- Deny guest → LAN, loopback, RFC1918, CGNAT, link-local/metadata, multicast and reserved destinations.
- Deny guest → other guests and production container subnets.
- Deny guest → server public IPv4/IPv6 and any other owned origin IPs (including router hairpin paths).
- IPv6 must have equivalent enforcement or be entirely unavailable on this bridge.
- Use antispoofing per tap and order rules before broad established/related accepts.
- Permit outbound public Internet with stateful replies; no inbound port forwarding.
  Start with public TCP 80/443 and DNS through the controlled resolver; add e.g. SSH
  only for demonstrated dependency requirements. Document exceptions per pool.
- Block SMTP and rate-limit connections/bandwidth. Stop/drop-network before deleting guests.

Public Internet access is deliberately not a package-domain allowlist: Rust, crates.io,
GitHub artifacts, npm/Bun, Ubuntu mirrors, Microsoft SDK downloads and caches use changing
CDNs. IP filtering prevents DNS rebinding to blocked addresses, but does not stop public
proxy services or malicious outbound activity. Public Internet access allows exfiltration
of anything actually made available to a job: contributor VMs therefore get no secrets.

**Important limitation:** blocking the origin IP does not block public production websites
through Cloudflare. Those services must remain secure as public services; external attackers
can already reach them. If CI must be unable to reach them even via public proxies, broad
Internet egress cannot meet that requirement. Use a separate CI machine/provider for stronger
production separation. An approved project needing a LAN database gets an isolated test copy,
not an exception to reach production.

## Capacity: i5-10600KF / 48 GiB / 1 TB NVMe

Start with ONE active VM: 4 vCPUs, 12 GiB RAM, 80 GiB capped scratch disk, 60-minute job TTL
(adjust for measured compile times), and CPU/I/O priority below production. Expand to two
only after measuring TTML inference, Overleaf compilation and Fluxer latency. Two such
VMs leave 24 GiB for the host/services but TTML may require more. Do not oversubscribe RAM
or use unlimited thin disks. Keep >=150 GiB free; admission stops below a threshold.
No GPU passthrough is planned. Verify KVM/VT-x is enabled in firmware before installation.

Use a read-only prebuilt guest image with fresh overlay per job; no reusable workspace.
Package dependencies into versioned images later to reduce apt/toolchain startup cost.
Trusted caches may use a separate namespace and credentials; contributor caches never
become a trusted release input. A Nix binary cache can be read-only for contributor jobs;
cache signing keys remain outside guests.

## Fork/private dependency decision

Choose one before enabling ExamWatcher fork PRs:
- Split public tests so they work without private crates; use public stubs/interfaces.
- Publish a non-sensitive dependency version available without credentials.
- Require maintainer review, then run the exact reviewed commit in a trusted workflow.
  This is explicit trust elevation, not safe automatic execution of arbitrary fork code.

Do not inject private read tokens into arbitrary fork builds. Even if the token is hidden,
private source code itself can be copied out by the build.

## Implementation sequence / acceptance gates

1. Inventory API/private repo workflows, current runner registrations, concurrency, ARM/Mac runners.
2. Confirm target KVM support and identify host/LAN/origin ranges. Pick GitHub App scope and release authorization mechanism.
3. Build a NixOS guest with GitHub runner + Docker; validate existing Ubuntu container jobs in a disposable test VM.
4. Implement the controller: queue admission, JIT registration, one VM per job, authenticated event handling (or polling),
   bounded retries, cleanup on all exit paths, orphan sweep on boot, deregistration, metrics and log redaction.
5. Implement host networking and test from a ROOT guest: cannot reach host SSH, Nix daemon,
   Docker socket, LAN/router, metadata, sibling guests, production databases, origin IPs, IPv6 bypasses.
   Test public dependency downloads and artifacts. Include DNS rebinding and spoofed source tests.
6. Test success/failure/cancel/timeouts/reboot; verify no disks/credentials/registrations remain.
7. Enable trusted pilot repository first. Split release authorization and fork workflows before adding contributor jobs.
8. Run a malicious-job test matrix; only then enable external contributor execution.

Do not enable untrusted runner services until these gates pass. The controller and host
modules are now implemented in `ci/` and `modules/ci-runners.nix`; see `ci/README.md`
for tests performed and remaining deployment gates. This document retains the threat model
and requirements, and does not claim target-machine deployment.
