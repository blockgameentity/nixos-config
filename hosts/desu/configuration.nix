{ pkgs, lib, ... }: {
  imports = [ ./hardware-configuration.nix ./local.nix ../../modules/edge.nix ../../modules/apps.nix ];
  networking.hostName = "desu";
  networking.useDHCP = true;
  # Tailscale SSH handles OAuth; no OpenSSH daemon or SSH keys required.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];
  time.timeZone = "Europe/Copenhagen";
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  services.tailscale = {
    enable = true;
    openFirewall = true;
    authKeyFile = "/var/lib/secrets/tailscale-auth-key";
    authKeyParameters = { ephemeral = false; preauthorized = true; };
    extraUpFlags = [ "--ssh" ];
  };
  services.openssh.enable = false;
  users.users.desu = { isNormalUser = true; extraGroups = [ "wheel" ]; };
  # local.nix supplies a local console/sudo password hash, not an SSH password.
  environment.systemPackages = with pkgs; [ git curl jq restic ];
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
