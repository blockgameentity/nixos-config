{
  description = "InvokeAI: the full application (backend + web UI), built reproducibly from upstream's uv.lock";

  # A real package, not upstream's impure dev shell (`pip install` into a venv).
  # Everything comes from the lockfile upstream already maintains, so a release is
  # one input bump:
  #
  #   nix flake lock --update-input invokeai-src
  #   (then refresh the pnpm hash in nix/frontend.nix, see the comment there)
  #
  # Python deps: uv2nix reads uv.lock and fetches each pinned wheel by hash
  # (torch+cu130 from PyTorch's index, the nvidia-* CUDA libraries from PyPI).
  # Web UI: webv2 is built from its pnpm-lock.yaml and installed where the server
  # looks for it (`invokeai/frontend/webv2/dist`).

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The application itself. Pinned to a release tag; not a flake.
    invokeai-src = {
      url = "github:invoke-ai/InvokeAI/v7.0.0-beta.2";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      pyproject-nix,
      uv2nix,
      pyproject-build-systems,
      invokeai-src,
      ...
    }:
    let
      lib = nixpkgs.lib;
      system = "x86_64-linux";

      # CUDA wheels and the NVIDIA userspace driver are unfree; allow only what
      # the build actually needs.
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfreePredicate =
          pkg:
          builtins.elem (lib.getName pkg) [
            "cuda_cudart"
            "cuda_nvrtc"
            "libcublas"
            "libcufft"
            "libcusparse"
            "libcusolver"
            "libcurand"
            "cudnn"
            "nccl"
          ];
      };

      frontend = pkgs.callPackage ./nix/frontend.nix { inherit invokeai-src; };

      invokeai = pkgs.callPackage ./nix/invokeai.nix {
        inherit
          invokeai-src
          frontend
          uv2nix
          pyproject-nix
          pyproject-build-systems
          ;
      };
    in
    {
      packages.${system} = {
        inherit frontend invokeai;
        default = invokeai;
      };

      apps.${system}.default = {
        type = "app";
        program = "${invokeai}/bin/invokeai-web";
      };

      overlays.default = final: _prev: {
        invokeai = self.packages.${final.stdenv.hostPlatform.system}.invokeai;
      };

      nixosModules.default = import ./nix/module.nix self;

      formatter.${system} = pkgs.nixfmt;
    };
}
