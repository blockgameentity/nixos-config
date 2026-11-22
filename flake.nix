{
  description = "desu.re NixOS server";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Application flakes keep their own service contract; the server does not
    # duplicate container/env/volume definitions.
    ttml = {
      url = "github:blockgameentity/ttml-fixer";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    spar = {
      url = "github:O-Blocken/tilbuds-bot";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = { self, nixpkgs, nix-darwin, ttml, spar, ... }: {
    nixosConfigurations.ci-guest = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ./ci/guest.nix ];
    };
    packages.x86_64-linux.ci-guest = self.nixosConfigurations.ci-guest.config.system.build.image;
    darwinConfigurations.ci-mac = nix-darwin.lib.darwinSystem {
      modules = [ ./hosts/mac/configuration.nix ];
    };
    nixosModules.disposable-runners = import ./modules/ci-runners.nix;
    nixosConfigurations.desu = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit ttml spar; };
      modules = [
        ./hosts/desu/configuration.nix
        ./modules/ci-runners.nix
        { services.disposableRunners.image = "${self.packages.x86_64-linux.ci-guest}/ci-guest.qcow2"; }
      ];
    };

    # Cheap CI gates. The installation assertions are intentionally disabled
    # here: they guard real secrets/hardware, not the shape of the config.
    checks.x86_64-linux = let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      evaluated = (self.nixosConfigurations.desu.extendModules {
        modules = [ ({ lib, ... }: { assertions = lib.mkForce [ ]; }) ];
      }).config;
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
        # Discard the string context: this check proves the configuration
        # evaluates, without pulling the whole NixOS system into its closure.
        echo ${pkgs.lib.escapeShellArg (builtins.unsafeDiscardStringContext evaluated.system.build.toplevel.drvPath)} > $out
      '';
    };
  };
}
