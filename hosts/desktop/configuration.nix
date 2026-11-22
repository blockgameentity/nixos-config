# Desktop host. Imported by mkHost in flake.nix once the flake output for
# `desktop` is uncommented. Keep machine-specific policy here; shared defaults
# come from ../../modules/base.nix.
{ ... }: {
  # hardware-configuration.nix and modules/base.nix are added by mkHost, not here.

  # Display, terminal emulator and font baseline shared with the laptop, the
  # desktop-only CUDA/NVIDIA/Unity layer, and the CachyOS kernel from Chaotic-Nyx.
  imports = [
    ../../modules/graphical.nix
    ../../modules/desktop.nix
    ../../modules/cachyos.nix
  ];

  networking.hostName = "desktop";
  networking.useDHCP = true;
  time.timeZone = "Europe/Copenhagen";
  users.users.desu = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };

  # Tailscale itself is enabled by modules/base.nix; only host flags belong here.
  services.tailscale.extraUpFlags = [ "--ssh" ];
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  system.stateVersion = "26.05";
}
