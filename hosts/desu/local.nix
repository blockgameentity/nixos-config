# Edit before deploying. Never put secret VALUES in this file.
{ ... }: {
  assertions = [{ assertion = false; message = "Configure local.nix: local sudo password file and application image digests; then remove this assertion."; }];
  # Set tokenFile to the repository-specific runner-management token at deployment.
  services.disposableRunners = {
    # Review the contributor-job authorization and token requirements in ci/README.md.
    repository = "ExamWatcher/desktop";
    tokenFile = "/var/lib/secrets/ci-token";
    # REQUIRED: replace with this server's public origin IP(s); documentation-only example fails closed by design.
    blockedIPv4 = [ "203.0.113.1/32" ];
  };
  users.users.desu.hashedPasswordFile = "/var/lib/secrets/desu-password-hash";
  desu.images.overleaf = "rigon/sharelatex-full:latest-shell-escape";
  desu.images.ttml = "localhost/ttml-fixer:migration";
}
