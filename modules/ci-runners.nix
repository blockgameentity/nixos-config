{ config, lib, pkgs, ... }:
let
  cfg = config.services.disposableRunners;
  slots = lib.range 1 cfg.count;
  json = pkgs.formats.json { };
  slot = n: toString n;
  tap = n: "ci-tap${slot n}";
  address = n: "10.203.${slot n}";
  blocked = [ "0.0.0.0/8" "10.0.0.0/8" "100.64.0.0/10" "127.0.0.0/8" "169.254.0.0/16" "172.16.0.0/12" "192.0.0.0/24" "192.0.2.0/24" "192.168.0.0/16" "198.18.0.0/15" "198.51.100.0/24" "203.0.113.0/24" "224.0.0.0/4" "240.0.0.0/4" ] ++ cfg.blockedIPv4;
  rules = pkgs.writeText "ci-firewall.nft" ''
    table inet ci_isolation {
      chain input {
        type filter hook input priority -200; policy accept;
        iifname "ci-tap*" drop
      }
      chain forward {
        type filter hook forward priority -200; policy accept;
        iifname "ci-tap*" meta nfproto ipv6 drop
        oifname "ci-tap*" meta nfproto ipv6 drop
        ${lib.concatMapStringsSep "\n" (n: ''iifname "${tap n}" ip saddr != ${address n}.2 drop'') slots}
        iifname "ci-tap*" ip daddr { ${lib.concatStringsSep ", " blocked} } drop
        iifname "ci-tap*" udp dport { 123, 1900, 5353 } drop
        iifname "ci-tap*" ip daddr { 1.1.1.1, 1.0.0.1 } udp dport 53 accept
        iifname "ci-tap*" ip daddr { 1.1.1.1, 1.0.0.1 } tcp dport 53 accept
        iifname "ci-tap*" tcp dport { 22, 80, 443 } accept
        iifname "ci-tap*" udp dport 443 accept
        iifname "ci-tap*" tcp dport { 80, 443 } accept
        iifname "ci-tap*" drop
        oifname "ci-tap*" ct state established,related accept
        oifname "ci-tap*" drop
      }
    }
  '';
in {
  options.services.disposableRunners = {
    enable = lib.mkEnableOption "single-job KVM GitHub runners";
    image = lib.mkOption { type = lib.types.path; description = "Immutable qcow2 guest image"; };
    repository = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+"; };
    tokenFile = lib.mkOption { type = lib.types.str; description = "Host-only fine-grained token with repository Administration:write (required by runner-management API). Rotate after use; this is broader access than runners themselves need."; };
    blockedIPv4 = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; description = "Additional origin/public and infrastructure CIDRs denied to jobs"; };
    count = lib.mkOption { type = lib.types.ints.between 1 2; default = 1; };
    labels = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ "self-hosted" "Linux" "X64" "ci-public-x64" ]; };
    cpus = lib.mkOption { type = lib.types.ints.between 1 8; default = 4; };
    memoryMiB = lib.mkOption { type = lib.types.ints.between 1024 16384; default = 12288; };
    diskGiB = lib.mkOption { type = lib.types.ints.between 20 100; default = 80; };
    ttlSeconds = lib.mkOption { type = lib.types.ints.between 300 14400; default = 3600; };
    minimumFreeGiB = lib.mkOption { type = lib.types.ints.positive; default = 150; };
  };
  config = lib.mkIf cfg.enable {
    assertions = [{ assertion = cfg.blockedIPv4 != []; message = "Set disposableRunners.blockedIPv4 to the production origin IPs before enabling CI."; }];
    boot.kernelModules = [ "kvm-intel" "tun" ];
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
    users.groups.ci-vm = {};
    users.users.ci-vm = { isSystemUser = true; group = "ci-vm"; extraGroups = [ "kvm" ]; };
    systemd.services = { ci-network = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "firewall.service" "docker.service" ];
      path = with pkgs; [ iproute2 nftables iptables ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      script = ''
        # Install the deny policy BEFORE bringing up any guest tap.
        if nft list table inet ci_isolation >/dev/null 2>&1; then nft delete table inet ci_isolation; fi
        nft -f ${rules}
        ${lib.concatMapStringsSep "\n" (n: ''
          ip tuntap add dev ${tap n} mode tap user ci-vm
          ip address add ${address n}.1/30 dev ${tap n}
          ip link set ${tap n} up
        '') slots}
        iptables -t nat -A POSTROUTING -s 10.203.0.0/16 ! -o ci-tap+ -j MASQUERADE
        # No iptables accepts: the nft filter must remain authoritative.
      '';
      preStop = ''
        ${lib.concatMapStringsSep "\n" (n: "ip link delete ${tap n} || true") slots}
        iptables -t nat -D POSTROUTING -s 10.203.0.0/16 ! -o ci-tap+ -j MASQUERADE || true
        nft delete table inet ci_isolation || true
      '';
    }; } // lib.listToAttrs (map (n: lib.nameValuePair "ci-runner-${slot n}" {
      wantedBy = [ "multi-user.target" ];
      requires = [ "ci-network.service" ];
      bindsTo = [ "ci-network.service" ];
      after = [ "ci-network.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        User = "ci-vm";
        Group = "ci-vm";
        SupplementaryGroups = [ "kvm" ];
        StateDirectory = "ci-runner-${slot n}";
        StateDirectoryMode = "0700";
        LoadCredential = "github-token:${cfg.tokenFile}";
        ExecStart = "${pkgs.python3}/bin/python ${../ci/controller.py} ${json.generate "runner-${slot n}.json" {
          inherit (cfg) repository labels cpus memoryMiB diskGiB ttlSeconds minimumFreeGiB image;
          name = "desu-ci-${slot n}";
          tap = tap n;
          address = address n;
          qemu = "${pkgs.qemu_kvm}/bin/qemu-system-x86_64";
          qemuImg = "${pkgs.qemu_kvm}/bin/qemu-img";
        }}";
        Restart = "always";
        RestartSec = 60;
        TimeoutStopSec = 60;
        KillMode = "control-group";
        Nice = 10;
        CPUWeight = 20;
        IOWeight = 20;
        MemoryMax = "${toString (cfg.memoryMiB + 1024)}M";
        TasksMax = 512;
        UMask = "0077";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        DevicePolicy = "closed";
        DeviceAllow = [ "/dev/kvm rw" "/dev/net/tun rw" ];
      };
    }) slots);
  };
}
