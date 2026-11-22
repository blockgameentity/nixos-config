{ config, lib, ... }:
let
  cfg = config.desu.backup;
  # Data owners that must be quiesced for a consistent snapshot.
  units = [
    "fluxer.service"
    "podman-overleaf.service"
    "podman-overleaf-mongo.service"
    "podman-overleaf-redis.service"
    "podman-ttml-fixer-api.service"
    "podman-ttml-fixer-worker.service"
    "podman-spar-bot.service"
  ];
  systemctl = "${config.systemd.package}/bin/systemctl";
  stopUnits = lib.concatMapStringsSep "\n" (unit: "${systemctl} stop ${unit} || true") units;
  startUnits = lib.concatMapStringsSep "\n" (unit: "${systemctl} start ${unit} || true") units;

  # The restic module requires exactly one of repository/passwordFile or
  # environmentFile. A credentials file (S3/R2/B2) also carries
  # RESTIC_REPOSITORY and RESTIC_PASSWORD, so it replaces both options.
  usesRepository = cfg.repository != "";
in {
  options.desu.backup = {
    enable = lib.mkEnableOption "encrypted off-host restic backups";
    repository = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "sftp:backup@host:/srv/restic/desu";
      description = "restic repository URL when credentials come from passwordFile.";
    };
    passwordFile = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/secrets/restic-password";
      description = "Password file used with `repository`.";
    };
    environmentFile = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/secrets/restic.env";
      description = ''
        Used when `repository` is empty: source of RESTIC_REPOSITORY,
        RESTIC_PASSWORD and any S3/R2 credentials.
      '';
    };
    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "/var/lib/secrets"
        "/srv/overleaf"
        "/srv/spar"
        "/var/lib/ttml-fixer"
        # Fluxer's databases live in Docker volumes. Verify the exact names
        # with `docker volume ls` on the migrated host before trusting them.
        "/var/lib/docker/volumes/fluxer_postgres-data/_data"
        "/var/lib/docker/volumes/fluxer_nats-data/_data"
        "/var/lib/docker/volumes/fluxer_meilisearch-data/_data"
        "/var/lib/docker/volumes/fluxer_seaweedfs-data/_data"
      ];
      description = "Paths to snapshot; nonexistent paths are skipped.";
    };
    exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "/var/cache/ttml-fixer" "**/*.tmp" "**/_work" ];
      description = "Regenerable caches excluded from the snapshot.";
    };
    startAt = lib.mkOption {
      type = lib.types.str;
      default = "03:30";
    };
    retention = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "--keep-daily 7" "--keep-weekly 4" "--keep-monthly 6" ];
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = usesRepository || cfg.environmentFile != null;
      message = "desu.backup needs either `repository` (with passwordFile) or an environmentFile.";
    }];

    services.restic.backups.desu = {
      inherit (cfg) paths exclude;
      initialize = true;
      pruneOpts = cfg.retention;
      # Stop writers, snapshot, then restart even if the snapshot failed.
      backupPrepareCommand = stopUnits;
      backupCleanupCommand = startUnits;
      timerConfig = {
        OnCalendar = cfg.startAt;
        RandomizedDelaySec = "15m";
        Persistent = true;
      };
    } // (if usesRepository then {
      inherit (cfg) repository passwordFile;
    } else {
      inherit (cfg) environmentFile;
    });
  };
}
