{
  description = "desu.re NixOS configuration: server, laptop and desktop hosts";
  inputs = {
    # unstable: laptop, desktop and the disposable CI runners.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # stable: the always-on server (desu). Track the NixOS release branch, not a
    # tag, so it keeps receiving fixes; bump it deliberately at a release.
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Home Manager supplies the universal user profile (shell, prompt, git) for
    # every NixOS host; see modules/base.nix. It is pinned per channel because a
    # Home Manager release only supports its matching nixpkgs release.
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager-stable = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };
    # Chaotic-Nyx: CachyOS kernels and packages. The branch is the unstable one
    # (nyxpkgs-unstable), and its `nixosModules.default` is the unstable flavour,
    # so only hosts on the unstable channel import modules/cachyos.nix.
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    # Application flakes keep their own service contract; the server does not
    # duplicate container/env/volume definitions. They build against unstable
    # regardless of which channel the host that imports their module runs.
    ttml = {
      url = "github:blockgameentity/ttml-fixer";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    spar = {
      url = "github:O-Blocken/tilbuds-bot";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = {
    self,
    nixpkgs,
    nixpkgs-stable,
    nix-darwin,
    home-manager,
    home-manager-stable,
    chaotic,
    ttml,
    spar,
    ...
  }: let
    # A channel pairs a nixpkgs with the Home Manager that supports it.
    channels = {
      unstable = {
        pkgs = nixpkgs;
        hm = home-manager;
      };
      stable = {
        pkgs = nixpkgs-stable;
        hm = home-manager-stable;
      };
    };
    # One directory per machine under ./hosts. mkHost wires in the shared
    # baseline, the generated hardware description and the host's own choices,
    # so adding a machine is a single line in nixosConfigurations below.
    mkHost = {
      hostName,
      channel ? "unstable",
      system ? "x86_64-linux",
      modules ? [ ],
    }: let
      ch = channels.${channel};
    in
      ch.pkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit ttml spar chaotic; };
        modules = [
          ./modules/base.nix
          ch.hm.nixosModules.home-manager
          ./hosts/${hostName}/hardware-configuration.nix
          ./hosts/${hostName}/configuration.nix
        ] ++ modules;
      };
  in {
    # mkHost is exposed so a host can be evaluated ad hoc, e.g.
    #   nix eval --impure --expr '(builtins.getFlake "./.").lib.mkHost { hostName = "laptop"; }'
    lib.mkHost = mkHost;

    nixosConfigurations.ci-guest = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ./ci/guest.nix ];
    };
    packages.x86_64-linux.ci-guest = self.nixosConfigurations.ci-guest.config.system.build.image;
    darwinConfigurations.ci-mac = nix-darwin.lib.darwinSystem {
      modules = [ ./hosts/mac/configuration.nix ];
    };
    nixosModules.disposable-runners = import ./modules/ci-runners.nix;
    nixosConfigurations.desu = mkHost {
      hostName = "desu";
      # Long-lived server: stable channel. Laptop/desktop stay on the default
      # (unstable).
      channel = "stable";
      modules = [
        ./modules/ci-runners.nix
        { services.disposableRunners.image = "${self.packages.x86_64-linux.ci-guest}/ci-guest.qcow2"; }
      ];
    };
    # Workstations on the default (unstable) channel. Both hardware files are
    # committed with a btrfs subvolume layout (laptop adds LUKS), so these
    # evaluate here; the first install on each machine still needs its own
    # partitioning run (see README "Partitioning with btrfs subvolumes").
    nixosConfigurations.laptop = mkHost { hostName = "laptop"; };
    nixosConfigurations.desktop = mkHost { hostName = "desktop"; };

    # Cheap CI gates. Assertions stay ON, deliberately: they are the cheapest
    # thing that can catch a configuration that would refuse to install, and they
    # already have - `services.displayManager.defaultSession = "wayfire"` without
    # the matching `services.displayManager.sessionPackages` failed an assertion
    # that `nixos-install` would have hit, while a local check that forced
    # `assertions = [ ]` reported success. Do not reintroduce that wrapper.
    #
    # The deployment gates do not need masking: `hosts/desu/local.nix` satisfies
    # their *shape* (`blockedIPv4` is a non-empty list, `desu.backup` falls back to
    # /var/lib/secrets/restic.env), and `scripts/preflight.py` is what enforces the
    # real values before an install. If a gate does fire here, the config is wrong,
    # not the check.
    checks.x86_64-linux = let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      hosts = [ "desu" "desktop" "laptop" ];
      # Evaluate every host, not just the server: a laptop-only change used to
      # be caught by nothing but the slower `nix flake check` path.
      evaluated =
        map
          (name: {
            inherit name;
            drvPath = self.nixosConfigurations.${name}.config.system.build.toplevel.drvPath;
          })
          hosts;
    in {
      preflight-tests = pkgs.runCommand "preflight-tests" {
        nativeBuildInputs = [ pkgs.python3 ];
      } ''
        cp -r ${./scripts} scripts
        cd scripts
        python3 -m unittest -v test_preflight
        touch $out
      '';
      runner-tests = pkgs.runCommand "runner-tests" {
        nativeBuildInputs = [ pkgs.python3 ];
      } ''
        cp -r ${./ci} ci
        cd ci
        python3 -m unittest -v test_controller
        touch $out
      '';
      config-eval = pkgs.runCommand "nixos-config-eval" { } ''
        # Discard the string context: this check proves each configuration
        # evaluates, without pulling the whole NixOS system into its closure.
        cat > $out <<EOF
        ${pkgs.lib.concatMapStringsSep "\n" (h: "${h.name}: ${builtins.unsafeDiscardStringContext h.drvPath}") evaluated}
        EOF
      '';
    };
  };
}
