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
  # Encrypted off-host backups, on. The repository URL, password and any S3/R2
  # credentials come from /var/lib/secrets/restic.env (RESTIC_REPOSITORY,
  # RESTIC_PASSWORD, ...), so no target and no credential is ever in this file.
  #
  # modules/backup.nix stops fluxer, overleaf, ttml and spar for the duration of
  # the nightly 03:30 snapshot and restarts them afterwards (even on failure), so
  # databases are quiesced instead of copied mid-write.
  #
  # The path list already includes /var/lib/secrets: this is the second copy of
  # those files, independent of the Bitwarden vault.
  desu.backup.enable = true;
  users.users.desu.hashedPasswordFile = "/var/lib/secrets/desu-password-hash";
  desu.images.overleaf = "rigon/sharelatex-full:latest-shell-escape"; # PLACEHOLDER: pin by digest
  desu.images.ttml = "localhost/ttml-fixer:migration"; # PLACEHOLDER: pin by digest
}
