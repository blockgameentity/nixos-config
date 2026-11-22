{ config, lib, pkgs, ... }:
let
  cfg = config.desu;
  compose = "${pkgs.docker-compose}/bin/docker-compose --project-name fluxer --env-file /var/lib/secrets/fluxer.env -f ${../services/fluxer}/compose.yaml";
in {
  options.desu.images = {
    overleaf = lib.mkOption { type = lib.types.str; description = "Existing Overleaf image, preferably pinned by digest"; };
    ttml = lib.mkOption { type = lib.types.str; description = "Built TTML backend image accessible to Podman"; };
  };
  config = {
    systemd.tmpfiles.rules = [
      "d /srv/overleaf 0750 root root -"
      "d /srv/overleaf/data 0750 root root -"
      "d /srv/overleaf/mongo 0750 root root -"
      "d /srv/overleaf/redis 0750 root root -"
      "d /srv/ttml/cache 0750 root root -"
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
        ttml = {
          image = cfg.images.ttml;
          ports = [ "127.0.0.1:8000:8000" ];
          environmentFiles = [ "/var/lib/secrets/ttml.env" ];
          environment = {
            TTML_FIXER_YTDLP_COOKIE_FILE = "/run/secrets/youtube-cookies.txt";
            HF_HOME = "/var/cache/ttml-fixer/huggingface";
            TORCH_HOME = "/var/cache/ttml-fixer/torch";
            XDG_CACHE_HOME = "/var/cache/ttml-fixer";
            DENO_DIR = "/var/cache/ttml-fixer/deno";
            TTML_FIXER_RESULT_CACHE_DIR = "/var/cache/ttml-fixer/results";
          };
          volumes = [ "/srv/ttml/cache:/var/cache/ttml-fixer" "/var/lib/secrets/youtube-cookies.txt:/run/secrets/youtube-cookies.txt:ro" ];
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
