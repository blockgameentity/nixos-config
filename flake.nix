{
  description = "desu.re NixOS server";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { nixpkgs, ... }: {
    nixosConfigurations.desu = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ./hosts/desu/configuration.nix ];
    };
  };
}
