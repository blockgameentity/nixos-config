# Desktop-only additions on top of modules/graphical.nix. The laptop must not
# import this: the NVIDIA driver, the CUDA toolkit and the unfree policy below
# only apply to this machine.
{
  config,
  lib,
  ...
}: {
  # No global `nixpkgs.config.cudaSupport`: neither cache.nixos.org nor
  # Chaotic-Nyx builds packages with it, so it turned firefox, obs-studio,
  # onnxruntime, opencv, openvino, TensorRT, cuDNN and NCCL into hours of local
  # compiling on every nixpkgs bump. Enable CUDA per package instead, here or
  # with `.override { cudaSupport = true; }` where the package is installed
  # (e.g. torch in a project's devShell). obs-studio needs nothing: it links its
  # NVENC plugins against the driver unconditionally.
  nixpkgs.overlays = [
    (final: prev: {
      # GPU panel: btop dlopens libnvidia-ml, found only via the driver runpath
      # that cudaSupport adds. Small C++ build, no CUDA closure.
      btop = prev.btop.override { cudaSupport = true; };
    })
  ];

  # modules/graphical.nix allows only steam, obsidian and the NVIDIA driver. On
  # this host that narrow list is not workable: cudatoolkit ships a whole family
  # of EULA packages (cccl, cuBLAS, ...) plus Unity Hub, whose names move
  # between nixpkgs releases. The desktop therefore allows unfree packages
  # outright; the laptop keeps the narrow predicate.
  nixpkgs.config.allowUnfree = lib.mkForce true;
  nixpkgs.config.allowUnfreePredicate = lib.mkForce null;

  # RTX 4090 (Ada) with the open kernel modules and KMS. CUDA userspace
  # (cudatoolkit) comes from home/desktop.nix.
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true;
    # Ada (4090) runs the open kernel modules.
    open = true;
    # The 4090 is always the primary GPU, never a render-offload helper: the
    # iGPU (UHD 770) stays bound to i915 but nothing is routed to it. Both
    # PRIME modes are off on purpose - `offload` would make the dGPU on-demand
    # only, and `sync` would copy every frame through the iGPU.
    prime = {
      offload.enable = false;
      sync.enable = false;
    };
  };

  # Some applications pick a GPU through libdri/GLX heuristics and would land on
  # the iGPU with both cards present. These force the NVIDIA vendor libraries
  # for OpenGL and VA-API in every session, including Wayland.
  environment.sessionVariables = {
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    LIBVA_DRIVER_NAME = "nvidia";
  };

  home-manager.users.${config.desu.primaryUser}.imports = [ ../home/desktop.nix ];
}
