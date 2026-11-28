# Laptop host. Imported by mkHost in flake.nix (nixosConfigurations.laptop).
# Keep machine-specific policy here; shared defaults
# come from ../../modules/base.nix.
{ pkgs, ... }: {
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

  # Battery policy, applied whenever the charger is plugged in or pulled, and once
  # at boot:
  #   battery  power-profiles-daemon "power-saver" + scx_bpfland PowerSave
  #   charger  "balanced" + bpfland Auto (no power saving while on mains)
  # Nothing else switches the profile under Wayfire (no desktop power manager).
  # A profile picked by hand still sticks until the next plug/unplug.
  #
  # bpfland stays the scheduler (lavd was worse on the desktop); only its mode
  # changes. Modes are passed to scx_loader over D-Bus by number:
  # 0 = Auto, 2 = PowerSave (`busctl call org.scx.Loader /org/scx/Loader
  # org.scx.Loader SchedulerModeArgs s scx_bpfland` lists them).
  services.scx-loader.config.default_mode = "PowerSave";
  systemd.services.power-source-sync = {
    description = "Match power profile and scheduler mode to charger/battery";
    after = [ "power-profiles-daemon.service" "scx_loader.service" ];
    wants = [ "power-profiles-daemon.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.power-profiles-daemon pkgs.systemd pkgs.coreutils ];
    serviceConfig.Type = "oneshot";
    script = ''
      # Mains is the barrel adapter; USB* covers USB-C PD chargers.
      online=0
      for s in /sys/class/power_supply/*; do
        case "$(cat "$s/type")" in
          Mains|USB*) [ "$(cat "$s/online" 2>/dev/null)" = 1 ] && online=1 ;;
        esac
      done
      if [ "$online" = 1 ]; then profile=balanced mode=0; else profile=power-saver mode=2; fi
      echo "charger online=$online -> $profile, bpfland mode $mode"
      powerprofilesctl set "$profile"
      # Not fatal: if scx_loader is down the kernel scheduler runs, which is fine.
      busctl call org.scx.Loader /org/scx/Loader org.scx.Loader \
        SwitchScheduler su scx_bpfland "$mode" || echo "scx_loader not reachable"
    '';
  };
  # udev must not block on D-Bus calls, so it only queues the unit.
  services.udev.extraRules = ''
    ACTION=="change", SUBSYSTEM=="power_supply", ATTR{type}=="Mains|USB*", RUN+="${pkgs.systemd}/bin/systemctl start --no-block power-source-sync.service"
  '';

  # amd_pstate in active (EPP) mode, which is what power-profiles-daemon drives.
  # It is the kernel default on Zen 3 with CPPC, so this only pins it; if
  # /sys/devices/system/cpu/amd_pstate/status is not "active", CPPC is off in
  # the firmware setup.
  boot.kernelParams = [ "amd_pstate=active" ];

  # powertop: per-device wattage and wakeups (`sudo powertop`). Only the tool -
  # powerManagement.powertop.enable (auto-tune at boot) is left off because it
  # also autosuspends USB input devices, which makes mice/keyboards lag.
  environment.systemPackages = [ pkgs.powertop ];
  time.timeZone = "Europe/Copenhagen";
  users.users.desu = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    # Password for sudo and the local greeter. Root-only file,
    # provisioned before the first boot; without it the account is locked and
    # sudo rejects every password. Generate it with `mkpasswd -m yescrypt`.
    hashedPasswordFile = "/var/lib/secrets/desu-password-hash";
  };

  # Only the server accepts remote logins, and only through Tailscale SSH.
  # The OpenSSH client remains available for connecting to other hosts.
  services.tailscale.extraUpFlags = [ ];
  services.openssh.enable = false;

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
    # RTD3: power the dGPU down to D3cold whenever nothing is using it (udev
    # rules + NVreg_DynamicPowerManagement=0x02). Without it the idle 3060 stays
    # powered for the whole session. Check on battery with
    # `cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status` -> suspended.
    # If it stays "active", something holds the card open: `nvidia-smi` lists
    # the process, or an external monitor is on a port wired to the dGPU.
    powerManagement.finegrained = true;
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
