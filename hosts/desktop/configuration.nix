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
    extraGroups = [ "wheel" "networkmanager" ];
    # Password for sudo and for the tailnet SSH login below. Root-only file,
    # provisioned before the first boot; without it the account is locked and
    # sudo rejects every password. Generate it with `mkpasswd -m yescrypt`.
    hashedPasswordFile = "/var/lib/secrets/desu-password-hash";
  };

  # Tailscale itself is enabled by modules/base.nix; only host flags belong here.
  # No `--ssh`: Tailscale SSH intercepts port 22 on the tailnet and authenticates
  # by tailnet identity, which would bypass the sshd + password you actually use.
  services.tailscale.extraUpFlags = [ ];

  # Remote access over the tailnet only, with a normal password login:
  # sshd is enabled, nothing opens 22 on the LAN or WAN, and the only interface
  # allowed through the firewall is tailscale0.
  #
  # The password hash above is what makes this usable: without that file the
  # account is locked and password logins fail even though sshd accepts them.
  services.openssh = {
    enable = true;
    # The module defaults openFirewall to true, which opened 22 (with password
    # login) on every interface, wifi included. Only tailscale0 opens it (below).
    openFirewall = false;
    settings = {
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];
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
