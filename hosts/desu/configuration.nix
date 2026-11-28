{ pkgs, lib, ttml, spar, cheesetool, ... }: {
  imports = [
    # ./hardware-configuration.nix is imported by mkHost in flake.nix, together
    # with ../../modules/base.nix (flakes + nh). Keep this file to what is true
    # about this machine only.
    ./local.nix
    ../../modules/edge.nix
    ../../modules/apps.nix
    ../../modules/backup.nix
    ../../modules/btrfs.nix
    ../../modules/memory.nix
    ../../modules/maintenance.nix
    ttml.nixosModules.default
    spar.nixosModules.default
    cheesetool.nixosModules.reseed
  ];
  networking.hostName = "desu";
  networking.useDHCP = true;
  # Tailscale SSH handles OAuth; no OpenSSH daemon or SSH keys required.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];
  time.timeZone = "Europe/Copenhagen";
  # Limine instead of systemd-boot. Limine reads kernels straight from /boot, so
  # maxGenerations only bounds how many menu entries are written; canTouchEfiVariables
  # stays true so the installer can own the UEFI Boot#### entry.
  boot.loader.limine = {
    enable = true;
    maxGenerations = 10;
  };
  boot.loader.efi.canTouchEfiVariables = true;
  # btrfs housekeeping for the subvolume layout in hardware-configuration.nix:
  # monthly scrub over every btrfs filesystem, weekly fstrim, and the boot
  # ordering flags for /nix and /var/log.
  desu.btrfs.enable = true;
  # zswap + a swap file on / (modules/memory.nix). Sized for CI builds: a
  # compile that would otherwise be OOM-killed spills instead.
  desu.memory.swapSizeMiB = 32768;
  # Tailscale is enabled by modules/base.nix; the server adds its headless
  # enrollment key and --ssh (that is the only SSH path - no OpenSSH daemon).
  services.tailscale = {
    authKeyFile = "/var/lib/secrets/tailscale-auth-key";
    authKeyParameters = { ephemeral = false; preauthorized = true; };
    extraUpFlags = [ "--ssh" ];
  };
  services.openssh.enable = false;
  users.users.desu = { isNormalUser = true; extraGroups = [ "wheel" ]; };
  # local.nix supplies a local console/sudo password hash, not an SSH password.
  environment.systemPackages = with pkgs; [ git curl jq restic ];
  # cheesetool reseed node (relay-only Iroh endpoint; outbound connections only, so
  # no inbound port). State, including the identity key iroh-endpoint.key, is
  # /var/lib/cheesetool-reseed: restore the OLD key there before the first start or
  # every client orphans (docs/cheesetool-reseed.md). The operator dashboard/API
  # stays on loopback; reach it with `ssh -L 8080:127.0.0.1:8080` or Tailscale SSH.
  services.cheesetool-reseed = {
    enable = true;
    http.address = "127.0.0.1:8080";
    # Operator API bearer token (openssl rand -hex 32), root-only; the unit fails
    # closed without it, like the other secrets in /var/lib/secrets.
    http.tokenFile = "/var/lib/secrets/cheesetool-reseed-token";
  };
  services.disposableRunners.enable = true;
  virtualisation.podman.enable = true;
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = false; # Never prune application state automatically.
    daemon.settings = {
      features.userland-proxy = false;
      log-driver = "json-file";
      log-opts = { max-size = "10m"; max-file = "3"; };
    };
  };
  system.stateVersion = "26.05";
}
