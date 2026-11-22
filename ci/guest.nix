{ modulesPath, pkgs, ... }: {
  imports = [ (modulesPath + "/virtualisation/disk-image.nix") ];
  image = { format = "qcow2"; efiSupport = false; baseName = "ci-guest"; };
  virtualisation.diskSize = 16000;
  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" "virtio_net" ];
  boot.kernelModules = [ "qemu_fw_cfg" ];
  boot.kernelParams = [ "console=ttyS0" ];
  networking.hostName = "disposable-ci";
  networking.useDHCP = false;
  networking.usePredictableInterfaceNames = false;
  networking.firewall.enable = true;
  services.openssh.enable = false;
  virtualisation.docker.enable = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  environment.systemPackages = with pkgs; [ git bash coreutils curl cacert jq nix docker ];
  systemd.services.ci-network = {
    wantedBy = [ "multi-user.target" ];
    before = [ "ci-job.service" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    path = [ pkgs.iproute2 ];
    script = ''
      address=$(cat /sys/firmware/qemu_fw_cfg/by_name/opt/address/raw)
      ip link set eth0 up
      ip address add "$address.2/30" dev eth0
      ip route add default via "$address.1"
    '';
  };
  networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];
  systemd.services.ci-job = {
    wantedBy = [ "multi-user.target" ];
    requires = [ "ci-network.service" "docker.service" ];
    after = [ "ci-network.service" "docker.service" ];
    path = with pkgs; [ bash coreutils git docker curl gzip gnutar ];
    environment = {
      HOME = "/var/lib/ci-job";
      RUNNER_ROOT = "/var/lib/ci-job";
      RUNNER_ALLOW_RUNASROOT = "1";
    };
    serviceConfig = {
      Type = "simple";
      StateDirectory = "ci-job";
      WorkingDirectory = "/var/lib/ci-job";
      ExecStopPost = "${pkgs.systemd}/bin/systemctl --no-block poweroff";
    };
    script = ''
      jit=$(cat /sys/firmware/qemu_fw_cfg/by_name/opt/runner/raw)
      exec ${pkgs.github-runner}/bin/Runner.Listener run --jitconfig "$jit"
    '';
  };
  system.stateVersion = "26.05";
}
