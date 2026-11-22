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
  # NetworkManager owns DHCP and wifi; its module forces networking.useDHCP off
  # (setting it true here is a conflicting definition, not a preference).
  networking.networkmanager.enable = true;

  # Real hardware on this machine: MediaTek Bluetooth (USB 0489:e0cd), touchpad
  # and keyboard through libinput, battery/AC reporting, and a power profile
  # switcher that works with any Wayland session (power-profiles-daemon rather
  # than TLP - the two conflict, and TLP adds nothing on a machine this modern).
  hardware.bluetooth.enable = true;
  services.libinput.enable = true;
  services.upower.enable = true;
  services.power-profiles-daemon.enable = true;
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

  # Hybrid graphics: the Radeon Vega iGPU (05:00.0, rev c6) drives the panel, the
  # RTX 3060 Mobile Max-Q (01:00.0, rev a1) is used on demand via PRIME render
  # offload (`nvidia-offload <program>`). Both bus IDs are from `lspci` on this
  # machine; a wrong ID gives a black screen, not a build failure.
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    # Ampere (3060 Mobile) runs the open kernel modules.
    open = true;
    prime = {
      offload.enable = true;
      offload.enableOffloadCmd = true;
      amdgpuBusId = "PCI:5:0:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  # Every host in this repo keeps the same stateVersion; change it only for a
  # deliberate release upgrade.
  system.stateVersion = "26.05";
}
