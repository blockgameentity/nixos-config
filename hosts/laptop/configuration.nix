# Laptop host. Imported by mkHost in flake.nix (nixosConfigurations.laptop).
# Keep machine-specific policy here; shared defaults
# come from ../../modules/base.nix.
{ ... }: {
  # hardware-configuration.nix and modules/base.nix are added by mkHost, not here.

  # Display, terminal emulator and font baseline shared with the desktop, plus
  # the CachyOS kernel from Chaotic-Nyx and the Wayfire session
  # (modules/wayfire.nix).
  imports = [
    ../../modules/graphical.nix
    ../../modules/wayfire.nix
    ../../modules/cachyos.nix
    ../../modules/btrfs.nix
    ../../modules/memory.nix
  ];

  networking.hostName = "laptop";

  # Single built-in LCD in landscape: RGB subpixel rendering sharpens text in
  # Firefox, Electron and Qt (GTK 4 renders grayscale regardless). If text
  # shows coloured edges, the panel is BGR: switch to "bgr".
  fonts.fontconfig.subpixel = {
    rgba = "rgb";
    lcdfilter = "default";
  };
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
    # Password for sudo and for the tailnet SSH login below. Root-only file,
    # provisioned before the first boot; without it the account is locked and
    # sudo rejects every password. Generate it with `mkpasswd -m yescrypt`.
    hashedPasswordFile = "/var/lib/secrets/desu-password-hash";
  };

  # Typical laptop baseline; adjust to the actual hardware.
  # Tailscale itself is enabled by modules/base.nix; only host flags belong here.
  # No `--ssh`: Tailscale SSH intercepts port 22 on the tailnet and authenticates
  # by tailnet identity, which would bypass the sshd + password you actually use.
  services.tailscale.extraUpFlags = [ ];

  # Password SSH over the tailnet only (sshd enabled, port 22 opened on nothing
  # but tailscale0). The hash above is what the login prompt checks.
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

  # Firmware updates (BIOS/EC via LVFS and the NVMe/SSD firmware) - the laptop is
  # the machine where those actually matter.
  services.fwupd.enable = true;

  # Hibernate instead of suspend. `systemctl suspend`, the lid and the suspend key
  # all end in hibernation, so the LUKS key leaves RAM: a laptop stolen while
  # "asleep" needs the disk passphrase to come back, not just a lock-screen
  # password. Resume path: cryptroot unlocked -> vg0 activated -> image read from
  # /dev/vg0/swap (boot.resumeDevice in hardware-configuration.nix).
  #
  # SuspendState=disk rather than suspend-then-hibernate: there is no window at
  # all where the disk key sits in RAM untouched. The cost is ~13 GiB written to
  # NVMe per suspend and a slower wake - if that gets annoying, replace this with
  # `HibernateDelaySec=15min` and keep SuspendState=mem.
  systemd.sleep.settings.Sleep.SuspendState = "disk";
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
