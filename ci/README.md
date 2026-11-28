# Disposable runners — implementation

## Linux

`modules/ci-runners.nix` creates one isolated single-job KVM controller per named
pool. `ci/controller.py` obtains a JIT registration, starts a fresh qcow2 guest,
then removes its disk and registration. The host-only management token is supplied
through a systemd credential; only the short-lived JIT credential enters the guest.

A pool has exactly one `repository`, or one `organization` plus a named `runnerGroup`.
Organization groups must explicitly permit only the intended private repositories.
Never allow untrusted fork pull requests on self-hosted runners: isolation limits
persistence, but does not make hostile concurrent jobs safe. Labels are selectors,
not authorization. Keep each organization's token separate from other pools.

Organization tokens need organization **Administration: write**. Repository tokens
need repository **Administration: write**. Both are broad credentials; rotate them
and never put their values in Nix, Git, or workflow logs.

```nix
services.disposableRunners = {
  pools = {
    private-org = {
      organization = "example";
      runnerGroup = "Self-hosted CI";
      tokenFile = "/var/lib/secrets/ci-example-token";
    };
    private-repo = {
      repository = "owner/private";
      tokenFile = "/var/lib/secrets/ci-private-repo-token";
    };
  };
  blockedIPv4File = "/var/lib/secrets/ci-blocked-ipv4";
};
```

Each pool defaults to one VM with 4 CPUs, 12 GiB RAM, an 80 GiB virtual disk, and a
one-hour TTL. Increase a pool's resources only after checking host capacity. Workflows
select its `ci-POOL-x64` label in addition to `self-hosted`, `Linux`, and `X64`.
All configured pools run concurrently.

The host denies guest-to-host, guest-to-guest, private/metadata, IPv6, and configured
origin traffic. Only public HTTP(S), SSH, and the two configured public DNS servers
are allowed. A public proxy can bypass origin-IP blocking; this is not an application
egress filter. The network service fails closed if the origin file is missing or empty.

## Mac

`darwinConfigurations.ci-mac` runs a single-run trusted repository runner in a fresh
workspace. Enable `services.trustedMacRunner` only for explicitly trusted workflows.
