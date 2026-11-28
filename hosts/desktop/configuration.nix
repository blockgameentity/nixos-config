# Desktop host. Imported by mkHost in flake.nix once the flake output for
# `desktop` is uncommented. Keep machine-specific policy here; shared defaults
# come from ../../modules/base.nix.
{ ... }: {
  # hardware-configuration.nix and modules/base.nix are added by mkHost, not here.

  # Display, terminal emulator and font baseline shared with the laptop, the
  # desktop-only CUDA/NVIDIA/Unity layer, the CachyOS kernel from Chaotic-Nyx, and
  # the Wayfire session (modules/wayfire.nix). Wayfire lives on its own branch
  # until it has proven itself against Plasma; see docs/wayfire.md.
  imports = [
    ../../modules/graphical.nix
    ../../modules/desktop.nix
    ../../modules/wayfire.nix
    ../../modules/cachyos.nix
    ../../modules/btrfs.nix
    ../../modules/memory.nix
  ];

  networking.hostName = "desktop";

  # Rootless podman, for scripts/publish-image.sh (builds the TTML and SPAR images and
  # pushes them to the private GHCR). Not used to run any service on this machine.
  virtualisation.podman.enable = true;

  # Grayscale antialiasing only. The main display (AW3425DW) is QD-OLED with a
  # triangular subpixel layout, so RGB subpixel rendering would add colour
  # fringes there; the right Acer is portrait (vertical subpixels) as well.
  fonts.fontconfig.subpixel.rgba = "none";
  # NetworkManager owns DHCP on ethernet and wifi. Its module forces
  # networking.useDHCP off, so that option is not set here; nm-applet in the
  # Wayfire [autostart] is the front end.
  networking.networkmanager.enable = true;

  # Intel Bluetooth (firmware from hardware.enableRedistributableFirmware).
  # blueman-applet in the Wayfire [autostart] is the front end; services.blueman
  # is enabled in modules/wayfire.nix.
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  time.timeZone = "Europe/Copenhagen";
  # Dual boot with Windows on this machine: Windows keeps the RTC in local time,
  # so writing UTC there would shift its clock by two hours every boot.
  time.hardwareClockInLocalTime = true;
  users.users.desu = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "render" ];
    # Password for sudo and the local greeter. Root-only file,
    # provisioned before the first boot; without it the account is locked and
    # sudo rejects every password. Generate it with `mkpasswd -m yescrypt`.
    hashedPasswordFile = "/var/lib/secrets/desu-password-hash";
  };

  # Only the server accepts remote logins, and only through Tailscale SSH.
  # Workstations retain NixOS's openssh client for connecting to other hosts.
  services.tailscale.extraUpFlags = [ ];
  services.openssh.enable = false;
  # Limine instead of systemd-boot; kernels are read straight from /boot.
  boot.loader.limine = {
    enable = true;
    maxGenerations = 10;
    # Windows in the Limine menu. The ESP is shared, so boot() (the partition
    # Limine itself was loaded from) is where Windows Boot Manager lives too.
    extraEntries = ''
      /Windows
        protocol: efi_chainload
        path: boot():/EFI/Microsoft/Boot/bootmgfw.efi
    '';
  };
  boot.loader.efi.canTouchEfiVariables = true;
  # btrfs housekeeping for the subvolume layout in hardware-configuration.nix.
  desu.btrfs.enable = true;
  # zswap + one swap file on / (modules/memory.nix). Generous: this machine
  # ran ~25 GiB of swap on the old install, and zswap keeps the hot part in RAM.
  desu.memory.swapSizeMiB = 65536;

  system.stateVersion = "26.05";
}
