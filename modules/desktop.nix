# Desktop-only additions on top of modules/graphical.nix. The laptop must not
# import this: CUDA rebuilds most CUDA-aware packages locally and the NVIDIA
# driver only applies to this machine.
{
  config,
  lib,
  ...
}: {
  # Build CUDA-aware packages (torch, cupy, ...) against the toolkit.
  nixpkgs.config.cudaSupport = true;

  # modules/graphical.nix allows only steam, obsidian and the NVIDIA driver. On
  # this host that narrow list is not workable: CUDA ships a whole family of EULA
  # packages (cccl, cuDNN, cuBLAS, NCCL, ...) plus Unity Hub, whose names move
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
  };

  home-manager.users.${config.desu.primaryUser}.imports = [ ../home/desktop.nix ];
}
