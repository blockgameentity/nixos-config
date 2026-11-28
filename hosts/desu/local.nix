# Deployment-specific values. Never put secret VALUES in this file.
{ ... }: {
  services.disposableRunners = {
    # Each organization group must explicitly allow ONLY its selected private repositories.
    # Do not add public repositories to these groups or their self-hosted workflows.
    pools = {
      desu-renai = {
        organization = "desu-renai";
        runnerGroup = "Default";
        tokenFile = "/var/lib/secrets/ci-desu-renai-token";
        memoryMiB = 8192;
      };
      examwatcher = {
        organization = "ExamWatcher";
        # Private repositories only; explicitly exclude any public repositories.
        runnerGroup = "Self-hosted CI";
        tokenFile = "/var/lib/secrets/ci-examwatcher-token";
        memoryMiB = 8192;
      };
      cheesetool = {
        repository = "blockgameentity/cheesetool";
        tokenFile = "/var/lib/secrets/ci-cheesetool-token";
        memoryMiB = 8192;
      };
      pawchive-downloader = {
        repository = "blockgameentity/pawchive_downloader";
        tokenFile = "/var/lib/secrets/ci-pawchive-downloader-token";
        memoryMiB = 8192;
      };
    };
    # Four concurrent 8 GiB VMs on the 48 GiB host leave memory for services.
    # Real origin IP(s), one CIDR per line, never written to git or the Nix store.
    blockedIPv4File = "/var/lib/secrets/ci-blocked-ipv4";
  };
  # No automatic backup target is configured. modules/backup.nix remains available
  # for a future local, SFTP, or other destination; do not enable it without one.
  # The USB migration backup and Bitwarden remain the only independent copies.
  desu.backup.enable = false;
  users.users.desu.hashedPasswordFile = "/var/lib/secrets/desu-password-hash";
  # Pinned to what runs on the old server today (inventory 2026-11-27).
  desu.images.overleaf = "rigon/sharelatex-full@sha256:7fadaaf023399671b0393db00753f4f0747c8da7c612c1c63dee423de0487fa9"; # tag latest-shell-escape
  desu.ttmlCookies = "/var/lib/secrets/youtube-cookies.txt";
  desu.images.ttml = "ghcr.io/blockgameentity/ttml-fixer@sha256:fd37459a9056e2a0a6886d3dcb1835a126a726f5c9decb747425db4d79e04584";
  desu.images.spar = "ghcr.io/blockgameentity/spar-bot@sha256:112572aae8761b908626decf0632611c8b875b33e7eb6c49edf364af25d4567a";
}
