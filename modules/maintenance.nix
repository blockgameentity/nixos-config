{ config, lib, ... }:
let
  cfg = config.desu.maintenance;
in {
  options.desu.maintenance = {
    gc.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatic Nix store garbage collection (on by default).";
    };
    gc.olderThan = lib.mkOption {
      type = lib.types.str;
      default = "30d";
      description = "Retention for old store paths.";
    };
    gc.dates = lib.mkOption {
      type = lib.types.str;
      default = "weekly";
    };
    autoUpgrade.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Upgrade from this flake on a timer. Off by default: an unattended
        upgrade restarts databases and containers, so enable it deliberately.
      '';
    };
    autoUpgrade.flake = lib.mkOption {
      type = lib.types.str;
      default = "github:blockgameentity/nixos-server";
    };
    autoUpgrade.dates = lib.mkOption {
      type = lib.types.str;
      default = "Mon *-*-* 04:00:00";
    };
  };

  config = {
    nix.gc = lib.mkIf cfg.gc.enable {
      automatic = true;
      dates = cfg.gc.dates;
      options = "--delete-older-than ${cfg.gc.olderThan}";
    };
    nix.optimise.automatic = true;
    nix.settings.auto-optimise-store = lib.mkDefault true;

    system.autoUpgrade = lib.mkIf cfg.autoUpgrade.enable {
      enable = true;
      flake = cfg.autoUpgrade.flake;
      dates = cfg.autoUpgrade.dates;
      # A surprise reboot would drop live chat calls and Overleaf sessions.
      allowReboot = false;
      randomizedDelaySec = "45min";
      flags = [ "--no-write-lock-file" ];
    };
  };
}
