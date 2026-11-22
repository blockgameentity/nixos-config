# Baseline for every NixOS machine in this repo (server, laptop, desktop).
# Only host-independent plumbing belongs here. Anything that describes a
# particular machine - timezone, services, firewall, users, hardware - stays in
# hosts/<name>/configuration.nix so hosts cannot silently inherit each other's
# exposure.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.desu;
in {
  options.desu.primaryUser = lib.mkOption {
    type = lib.types.str;
    default = "desu";
    description = ''
      Account that owns the Home Manager profile (shell, prompt, git) on every
      host. Hosts that log in as somebody else override this and Home Manager
      follows, so there is one home profile rather than one per host.
    '';
  };

  config = {
    nix.settings.experimental-features = [ "nix-command" "flakes" ];

    # nh is the rebuild/clean CLI used on every host. `flake` sets NH_FLAKE, so a
    # plain `nh os switch` (or `nh os boot`) targets this repository without
    # repeating the path. The repo is expected to be cloned at /etc/nixos:
    #   git clone git@github.com:blockgameentity/nixos-config.git /etc/nixos
    # Override per command with NH_OS_FLAKE, or per host if a machine keeps its
    # checkout elsewhere.
    programs.nh = {
      enable = true;
      flake = "/etc/nixos";
      # nh clean stays off: modules/maintenance.nix owns store GC, and enabling
      # both makes nh warn about conflicting collectors.
      clean.enable = false;
    };

    # Tailscale is a hard requirement on every host: the server relies on it for
    # SSH, and it is how the laptop/desktop reach each other and the server.
    # Host-specific bits (auth key, --ssh flag, tags) stay in hosts/<name>.
    services.tailscale = {
      enable = true;
      openFirewall = true;
    };

    # Interactive shell is fish on every host (home/shared.nix configures it).
    programs.fish.enable = true;
    users.users.${cfg.primaryUser}.shell = pkgs.fish;

    # Home Manager runs as a NixOS module: identical home config on every host,
    # with graphical-only pieces added by modules/graphical.nix.
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      # A pre-existing ~/.config/... file is moved aside instead of failing the
      # activation; delete the *.hm-backup copies once a host looks right.
      backupFileExtension = "hm-backup";
      users.${cfg.primaryUser} = {
        imports = [ ../home/shared.nix ];
      };
    };
  };
}
