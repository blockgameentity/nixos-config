{ config, lib, pkgs, ... }:
let
  cfg = config.desu;
  # services/fluxer is vendored verbatim from the upstream self-hosting compose
  # bundle, so the file names are upstream's: docker-compose.yml is the stack and
  # docker-compose.proxy.yml is the overlay that puts it behind an existing
  # reverse proxy (modules/edge.nix terminates TLS and forwards here).
  compose =
    "${pkgs.docker-compose}/bin/docker-compose --project-name fluxer"
    + " --env-file /var/lib/secrets/fluxer.env"
    + " -f ${../services/fluxer}/docker-compose.yml"
    + " -f ${../services/fluxer}/docker-compose.proxy.yml";
in {
  options.desu.images = {
    overleaf = lib.mkOption { type = lib.types.str; description = "Existing Overleaf image, preferably pinned by digest"; };
    ttml = lib.mkOption { type = lib.types.str; description = "Built ttml-fixer image (runs as uid 10001) accessible to rootful Podman"; };
    spar = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Built spar-tilbuds-bot image; the service is disabled while null.";
    };
    mongo = lib.mkOption {
      type = lib.types.str;
      default = "mongo:7.0";
      description = ''
        Overleaf's MongoDB. Upstream still pins 6.0; 7.0 is a supported single-major
        upgrade for the node driver (mongodb 6.x) Overleaf uses. Existing 6.0 data
        files start on 7.0 but keep FCV 6.0 until setFeatureCompatibilityVersion.
      '';
    };
    redis = lib.mkOption {
      type = lib.types.str;
      default = "redis:7.4-alpine";
      description = "Overleaf's Redis (cache only; ioredis 4.x is compatible with 7.x).";
    };
  };
  options.desu.fluxer = {
    domain = lib.mkOption {
      type = lib.types.str;
      default = "chat.desu.re";
      description = ''
        Public hostname of the Fluxer instance. Non-secret, so it lives here (and
        is handed to Compose through the unit's environment) rather than in
        /var/lib/secrets/fluxer.env; modules/edge.nix serves the same name.
      '';
    };
    edgeBind = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:42295";
      description = ''
        Loopback address the Fluxer edge container publishes: the port
        modules/edge.nix reverse-proxies chat.desu.re to. The container itself
        speaks plain HTTP on 8080 because TLS is terminated at the host Caddy.
      '';
    };
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
      "d /var/lib/secrets 0710 root caddy -"
    ];
    virtualisation.oci-containers = {
      backend = "podman";
      containers = {
        overleaf-mongo = {
          image = cfg.images.mongo;
          cmd = [ "--replSet" "overleaf" ];
          volumes = [ "/srv/overleaf/mongo:/data/db" ];
          extraOptions = [ "--network=overleaf" "--network-alias=mongo" ];
        };
        overleaf-redis = {
          image = cfg.images.redis;
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
      };
    };
    # Container contract lives in the upstream flakes; only deployment inputs
    # (image, cookies) are set here.
    services.ttmlFixer = {
      enable = true;
      image = cfg.images.ttml;
      cookieFile = cfg.ttmlCookies;
    };
    services.sparBot = lib.mkIf (cfg.images.spar != null) {
      enable = true;
      image = cfg.images.spar;
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
        restartTriggers = [
          ../services/fluxer/docker-compose.yml
          ../services/fluxer/docker-compose.proxy.yml
          ../services/fluxer/Caddyfile
        ];
        # Non-secret settings are declared here instead of in the secrets file, so
        # they are reviewed in git and cannot drift. Compose interpolation gives
        # the process environment precedence over --env-file, so a stale value in
        # fluxer.env is ignored rather than silently winning.
        environment = {
          # Compose refuses to run the bundle without this acknowledgement.
          FLUXER_SETTINGS_LOADED = "true";
          FLUXER_DOMAIN = cfg.fluxer.domain;
          FLUXER_PUBLIC_SCHEME = "https";
          FLUXER_PUBLIC_PORT = "443";
          # Read by the proxy overlay: publish plain HTTP on loopback only.
          FLUXER_EDGE_BIND = cfg.fluxer.edgeBind;
          # h3 needs UDP/443 published, which the host proxy does not do.
          FLUXER_EDGE_PROTOCOLS = "h1 h2";
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          # Meilisearch migrates the search database on the first start of a new
          # release and the API waits on 21 health gates; 20 minutes covers a
          # restore-sized first start without masking a genuinely stuck stack.
          TimeoutStartSec = 1200;
          ExecStart = "${compose} up -d --remove-orphans";
          ExecStop = "${compose} stop";
        };
      };
    };
  };
}
