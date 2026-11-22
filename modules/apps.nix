{ config, lib, pkgs, ... }:
let
  cfg = config.desu;
  compose = "${pkgs.docker-compose}/bin/docker-compose --project-name fluxer --env-file /var/lib/secrets/fluxer.env -f ${../services/fluxer}/compose.yaml";
  # Shared by the enqueue-only API and the inference worker (docker-compose.yml
  # contract of ttml-fixer: state, results and model caches).
  ttmlEnv = {
    TTML_FIXER_PROFILE = "homelab-cpu";
    TTML_FIXER_EXECUTION_MODE = "worker";
    TTML_FIXER_STATE_DIR = "/var/lib/ttml-fixer/state";
    TTML_FIXER_DB_PATH = "/var/lib/ttml-fixer/state/jobs.sqlite3";
    TTML_FIXER_SPOOL_DIR = "/var/lib/ttml-fixer/state/spool";
    TTML_FIXER_API_TOKEN_DB = "/var/lib/ttml-fixer/state/api-tokens.sqlite3";
    TTML_FIXER_RESULT_CACHE_DIR = "/var/cache/ttml-fixer/results";
    HF_HOME = "/var/cache/ttml-fixer/models/huggingface";
    TORCH_HOME = "/var/cache/ttml-fixer/models/torch";
    XDG_CACHE_HOME = "/var/cache/ttml-fixer/models";
    DENO_DIR = "/var/cache/ttml-fixer/models/deno";
    TTML_FIXER_TRUSTED_PROXY_CIDRS = "127.0.0.1/32";
  };
  ttmlState = [ "/var/lib/ttml-fixer:/var/lib/ttml-fixer" ];
  ttmlResults = [ "/var/cache/ttml-fixer/results:/var/cache/ttml-fixer/results" ];
in {
  options.desu.images = {
    overleaf = lib.mkOption { type = lib.types.str; description = "Existing Overleaf image, preferably pinned by digest"; };
    ttml = lib.mkOption { type = lib.types.str; description = "Built ttml-fixer image (runs as uid 10001) accessible to rootful Podman"; };
  };
  options.desu.ttmlCookies = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    default = null;
    description = "Optional Netscape cookie export; mounted read-only into the worker only.";
  };
  config = {
    systemd.tmpfiles.rules = [
      "d /srv/overleaf 0750 root root -"
      "d /srv/overleaf/data 0750 root root -"
      "d /srv/overleaf/mongo 0750 root root -"
      "d /srv/overleaf/redis 0750 root root -"
      "d /var/lib/ttml-fixer 0750 10001 10001 -"
      "d /var/cache/ttml-fixer 0750 10001 10001 -"
      "d /var/cache/ttml-fixer/results 0750 10001 10001 -"
      "d /var/cache/ttml-fixer/models 0750 10001 10001 -"
      "d /var/lib/secrets 0710 root caddy -"
    ];
    virtualisation.oci-containers = {
      backend = "podman";
      containers = {
        overleaf-mongo = {
          image = "mongo:6.0";
          cmd = [ "--replSet" "overleaf" ];
          volumes = [ "/srv/overleaf/mongo:/data/db" ];
          extraOptions = [ "--network=overleaf" "--network-alias=mongo" ];
        };
        overleaf-redis = {
          image = "redis:6.2";
          volumes = [ "/srv/overleaf/redis:/data" ];
          extraOptions = [ "--network=overleaf" "--network-alias=redis" ];
        };
        overleaf = {
          image = cfg.images.overleaf;
          dependsOn = [ "overleaf-mongo" "overleaf-redis" ];
          ports = [ "127.0.0.1:1337:80" ];
          volumes = [ "/srv/overleaf/data:/var/lib/overleaf" ];
          extraOptions = [ "--network=overleaf" ];
          environment = {
            OVERLEAF_APP_NAME = "Overleaf Community Edition";
            OVERLEAF_MONGO_URL = "mongodb://mongo/sharelatex?replicaSet=overleaf";
            OVERLEAF_REDIS_HOST = "redis";
            REDIS_HOST = "redis";
            OVERLEAF_SITE_URL = "https://overleaf.desu.re";
            OVERLEAF_BEHIND_PROXY = "true";
            OVERLEAF_SECURE_COOKIE = "true";
            ENABLED_LINKED_FILE_TYPES = "project_file,project_output_file";
            ENABLE_CONVERSIONS = "true";
            EMAIL_CONFIRMATION_DISABLED = "true";
          };
        };
        ttml-fixer-api = {
          image = cfg.images.ttml;
          cmd = [ "uvicorn" "ttml_fixer.main:app" "--host" "0.0.0.0" "--port" "8000" ];
          ports = [ "127.0.0.1:8000:8000" ];
          environmentFiles = [ "/var/lib/secrets/ttml.env" ];
          environment = ttmlEnv;
          volumes = ttmlState ++ ttmlResults;
          extraOptions = [ "--init" ];
        };
        ttml-fixer-worker = {
          image = cfg.images.ttml;
          cmd = [ "python" "-m" "ttml_fixer.worker" ];
          environmentFiles = [ "/var/lib/secrets/ttml.env" ];
          environment = ttmlEnv // lib.optionalAttrs (cfg.ttmlCookies != null) {
            TTML_FIXER_YTDLP_COOKIE_FILE = "/run/secrets/youtube-cookies.txt";
          };
          volumes = ttmlState ++ ttmlResults
            ++ [ "/var/cache/ttml-fixer/models:/var/cache/ttml-fixer/models" ]
            ++ lib.optional (cfg.ttmlCookies != null)
              "${toString cfg.ttmlCookies}:/run/secrets/youtube-cookies.txt:ro";
          extraOptions = [ "--init" ];
        };
      };
    };
    systemd.services = lib.genAttrs [ "podman-overleaf-mongo" "podman-overleaf-redis" ] (_: {
      requires = [ "app-network.service" ];
      after = [ "app-network.service" ];
    }) // {
      app-network = {
        before = [ "podman-overleaf.service" "podman-overleaf-mongo.service" "podman-overleaf-redis.service" ];
        serviceConfig.Type = "oneshot";
        serviceConfig.RemainAfterExit = true;
        script = ''
          ${pkgs.podman}/bin/podman network exists overleaf || ${pkgs.podman}/bin/podman network create overleaf
        '';
      };
      podman-overleaf = {
        requires = [ "app-network.service" ];
        after = [ "app-network.service" ];
        preStart = ''
          ready=0
          for attempt in $(seq 1 90); do
            if ${pkgs.podman}/bin/podman exec overleaf-mongo mongosh --quiet --eval '
              try { rs.status() } catch (e) {
                if (e.code === 94) rs.initiate({_id:"overleaf",members:[{_id:0,host:"mongo:27017"}]});
                else throw e;
              }
              if (!db.hello().isWritablePrimary) quit(1);
            '; then ready=1; break; fi
            sleep 2
          done
          test "$ready" = 1
        '';
        serviceConfig.TimeoutStartSec = lib.mkForce 300;
      };
      # ttml-fixer is an enqueue-only API plus a separate inference worker.
      podman-ttml-fixer-api = {
        after = [ "systemd-tmpfiles-setup.service" ];
        serviceConfig = {
          TimeoutStopSec = lib.mkForce 45;
          MemoryMax = "1G";
          CPUQuota = "100%";
        };
      };
      podman-ttml-fixer-worker = {
        after = [ "systemd-tmpfiles-setup.service" ];
        serviceConfig = {
          TimeoutStopSec = lib.mkForce 45;
          MemoryMax = "24G";
          CPUQuota = "800%";
        };
      };
      # Compose retains Fluxer's health-gated dependencies and initialization job.
      fluxer = {
        wantedBy = [ "multi-user.target" ];
        requires = [ "docker.service" ];
        after = [ "docker.service" "network-online.target" ];
        wants = [ "network-online.target" ];
        restartTriggers = [ ../services/fluxer/compose.yaml ../services/fluxer/Caddyfile ../services/fluxer/livekit.yaml ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = 600;
          ExecStart = "${compose} up -d --remove-orphans";
          ExecStop = "${compose} stop";
        };
      };
    };
  };
}
