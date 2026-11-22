{
  description = "desu.re NixOS server";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.nix-darwin = {
    url = "github:nix-darwin/nix-darwin/master";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = { self, nixpkgs, nix-darwin, ... }: {
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
      modules = [ ./hosts/desu/configuration.nix ./modules/ci-runners.nix
        { services.disposableRunners.image = "${self.packages.x86_64-linux.ci-guest}/ci-guest.qcow2"; }
      ];
    };
  };
}
