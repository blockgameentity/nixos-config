# NixOS module for InvokeAI.
#
#   imports = [ invokeai.nixosModules.default ];
#
#   programs.invokeai.enable = true;       # `invokeai-web` on PATH (run it as yourself)
#
#   services.invokeai = {                  # or: a system service
#     enable = true;
#     port = 9090;
#     openFirewall = false;
#   };
#
# InvokeAI keeps models, outputs and its database in a "root" directory (default
# `~/invokeai`). The service uses /var/lib/invokeai. The NVIDIA driver is found
# through /run/opengl-driver, so `hardware.nvidia` / `hardware.graphics` must be
# enabled on the host (they are on any machine that renders with the GPU).
self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.invokeai;
  defaultPackage = self.packages.${pkgs.stdenv.hostPlatform.system}.invokeai;
in
{
  options.programs.invokeai = {
    enable = lib.mkEnableOption "InvokeAI (puts `invokeai-web` on the system PATH)";
    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      defaultText = lib.literalExpression "invokeai.packages.\${system}.invokeai";
      description = "The InvokeAI package.";
    };
  };

  options.services.invokeai = {
    enable = lib.mkEnableOption "the InvokeAI web server as a system service";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      defaultText = lib.literalExpression "invokeai.packages.\${system}.invokeai";
      description = "The InvokeAI package.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        Address to listen on. InvokeAI has no authentication unless multi-user
        mode is configured, so keep this on loopback unless you front it with a
        reverse proxy or trust the network.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "TCP port of the web UI.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open `port` in the firewall.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "invokeai";
      description = "User the service runs as (created when left at the default).";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "invokeai";
      description = "Group the service runs as (created when left at the default).";
    };

    root = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/invokeai";
      description = ''
        InvokeAI root: configuration (`invokeai.yaml`), models, outputs and the
        database. Created and owned by the service user.
      '';
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        INVOKEAI_LOG_LEVEL = "debug";
      };
      description = "Extra environment (any `INVOKEAI_*` setting).";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf config.programs.invokeai.enable {
      environment.systemPackages = [ config.programs.invokeai.package ];
    })

    (lib.mkIf cfg.enable {
      users.users = lib.mkIf (cfg.user == "invokeai") {
        invokeai = {
          isSystemUser = true;
          group = cfg.group;
          home = cfg.root;
          # CUDA needs the render node; video covers older driver setups.
          extraGroups = [
            "video"
            "render"
          ];
          description = "InvokeAI";
        };
      };
      users.groups = lib.mkIf (cfg.group == "invokeai") { invokeai = { }; };

      networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

      # A custom root is not covered by StateDirectory; create it for the service.
      systemd.tmpfiles.rules = lib.mkIf (cfg.root != "/var/lib/invokeai") [
        "d ${cfg.root} 0750 ${cfg.user} ${cfg.group} -"
      ];

      systemd.services.invokeai = {
        description = "InvokeAI web server";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];

        environment = {
          INVOKEAI_HOST = cfg.host;
          INVOKEAI_PORT = toString cfg.port;
          HOME = cfg.root;
        }
        // cfg.environment;

        serviceConfig = {
          ExecStart = "${cfg.package}/bin/invokeai-web --root ${cfg.root}";
          User = cfg.user;
          Group = cfg.group;
          StateDirectory = lib.mkIf (cfg.root == "/var/lib/invokeai") "invokeai";
          WorkingDirectory = cfg.root;
          Restart = "on-failure";
          RestartSec = "5s";
          # A first start downloads nothing, but model loads and torch import are slow.
          TimeoutStartSec = "5min";

          # The GPU is the point, so no PrivateDevices; everything else is locked
          # down. The app writes only under its root and the temp dir.
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [ cfg.root ];
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
        };
      };
    })
  ];
}
