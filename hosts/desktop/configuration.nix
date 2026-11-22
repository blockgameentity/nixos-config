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
    ../../modules/btrfs.nix
    ../../modules/memory.nix
  ];

  networking.hostName = "desktop";
  networking.useDHCP = true;
  time.timeZone = "Europe/Copenhagen";
  # Dual boot with Windows on this machine: Windows keeps the RTC in local time,
  # so writing UTC there would shift its clock by two hours every boot.
  time.hardwareClockInLocalTime = true;
  users.users.desu = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };

  # Tailscale itself is enabled by modules/base.nix; only host flags belong here.
  services.tailscale.extraUpFlags = [ "--ssh" ];
  # Limine instead of systemd-boot; kernels are read straight from /boot.
  boot.loader.limine = {
    enable = true;
    maxGenerations = 10;
  };
  boot.loader.efi.canTouchEfiVariables = true;
  # btrfs housekeeping for the subvolume layout in hardware-configuration.nix.
  desu.btrfs.enable = true;
  # zswap + one swap file on / (modules/memory.nix). Generous: this machine
  # ran ~25 GiB of swap on the old install, and zswap keeps the hot part in RAM.
  desu.memory.swapSizeMiB = 65536;

  system.stateVersion = "26.05";
}
