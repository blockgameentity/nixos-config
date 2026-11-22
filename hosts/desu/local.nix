# Edit before deploying. Never put secret VALUES in this file.
# PLACEHOLDER markers below are enforced by scripts/preflight.py; remove them only
# after the real password hash, digest pins and public origin IP are set.
{ ... }: {
  # PLACEHOLDER: set tokenFile to the repository-specific runner token at deployment.
  services.disposableRunners = {
    # Review the contributor-job authorization and token requirements in ci/README.md.
    repository = "ExamWatcher/desktop";
    tokenFile = "/var/lib/secrets/ci-token";
    # REQUIRED: replace with this server's public origin IP(s); documentation-only example fails closed by design.
    blockedIPv4 = [ "203.0.113.1/32" ];
  };
  # Off-host restic target; either this or /var/lib/secrets/restic.env (RESTIC_* + S3 creds).
  # desu.backup = { enable = true; repository = "sftp:backup@host:/srv/restic/desu"; };
  users.users.desu.hashedPasswordFile = "/var/lib/secrets/desu-password-hash";
  desu.images.overleaf = "rigon/sharelatex-full:latest-shell-escape"; # PLACEHOLDER: pin by digest
  desu.images.ttml = "localhost/ttml-fixer:migration"; # PLACEHOLDER: pin by digest
}
