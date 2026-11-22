# Laptop host. Imported by mkHost in flake.nix once the flake output for
# `laptop` is uncommented. Keep machine-specific policy here; shared defaults
# come from ../../modules/base.nix.
{ ... }: {
  # hardware-configuration.nix and modules/base.nix are added by mkHost, not here.

  # Display, terminal emulator and font baseline shared with the desktop, plus
  # the CachyOS kernel from Chaotic-Nyx.
  imports = [
    ../../modules/graphical.nix
    ../../modules/cachyos.nix
    ../../modules/btrfs.nix
    ../../modules/memory.nix
  ];

  networking.hostName = "laptop";
  networking.useDHCP = true;
  time.timeZone = "Europe/Copenhagen";
  users.users.desu = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
  };

  # Typical laptop baseline; adjust to the actual hardware.
  # Tailscale itself is enabled by modules/base.nix; only host flags belong here.
  services.tailscale.extraUpFlags = [ "--ssh" ];
  # Limine instead of systemd-boot; kernels are read straight from /boot.
  boot.loader.limine = {
    enable = true;
    maxGenerations = 10;
  };
  boot.loader.efi.canTouchEfiVariables = true;
  # btrfs scrub/trim for the subvolume layout in hardware-configuration.nix.
  # That file also holds the LUKS device: the whole laptop disk is encrypted
  # except for the ESP, so the store, /home and the swap file are all inside it.
  desu.btrfs.enable = true;
  # No swap file here: the laptop uses a swap LV so hibernation works
  # (hardware-configuration.nix), and zswap compresses pages in front of it.
  desu.memory.swapFile = null;

  # Hybrid graphics: the AMD iGPU drives the desktop, the RTX 3060 Mobile is used
  # on demand via PRIME render offload (`nvidia-offload <program>`). Both bus IDs
  # are machine-specific: read them with `lspci | grep -E "VGA|3D"` and replace
  # the placeholders - wrong IDs give a black screen, not a build failure.
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    # Ampere (3060 Mobile) runs the open kernel modules.
    open = true;
    prime = {
      offload.enable = true;
      offload.enableOffloadCmd = true;
      amdgpuBusId = "PCI:5:0:0"; # PLACEHOLDER: AMD iGPU bus ID
      nvidiaBusId = "PCI:1:0:0"; # PLACEHOLDER: RTX 3060 Mobile bus ID
    };
  };

  # Every host in this repo keeps the same stateVersion; change it only for a
  # deliberate release upgrade.
  system.stateVersion = "26.05";
}
