{ config, lib, pkgs, ... }:
let
  cfg = config.services.disposableRunners;
  poolList = lib.mapAttrsToList (name: pool: pool // { inherit name; }) cfg.pools;
  slots = lib.imap1 (index: pool: pool // {
    number = index;
    tap = "ci-tap${toString index}";
    address = "10.203.${toString index}";
  }) poolList;
  legacySlots = lib.optional (cfg.pools == { }) (cfg // {
    name = "legacy";
    number = 1;
    tap = "ci-tap1";
    address = "10.203.1";
    organization = null;
    runnerGroup = null;
  });
  allSlots = if cfg.pools == { } then legacySlots else slots;
  json = pkgs.formats.json { };
  blocked = [ "0.0.0.0/8" "10.0.0.0/8" "100.64.0.0/10" "127.0.0.0/8" "169.254.0.0/16" "172.16.0.0/12" "192.0.0.0/24" "192.0.2.0/24" "192.168.0.0/16" "198.18.0.0/15" "198.51.100.0/24" "203.0.113.0/24" "224.0.0.0/4" "240.0.0.0/4" ] ++ cfg.blockedIPv4;
  rules = pkgs.writeText "ci-firewall.nft" ''
    table inet ci_isolation {
      # Filled by ci-network.service at start from blockedIPv4File, so the real
      # origin address never enters the repository or the world-readable store.
      set blocked_origin {
        type ipv4_addr
        flags interval
      }
      chain input {
        type filter hook input priority -200; policy accept;
        iifname "ci-tap*" drop
      }
      chain forward {
        type filter hook forward priority -200; policy accept;
        iifname "ci-tap*" meta nfproto ipv6 drop
        oifname "ci-tap*" meta nfproto ipv6 drop
        ${lib.concatMapStringsSep "\n" (pool: ''iifname "${pool.tap}" ip saddr != ${pool.address}.2 drop'') allSlots}
        iifname "ci-tap*" ip daddr { ${lib.concatStringsSep ", " blocked} } drop
        iifname "ci-tap*" ip daddr @blocked_origin drop
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
  poolOptions = { name, ... }: {
    options = {
      repository = lib.mkOption { type = lib.types.nullOr (lib.types.strMatching "[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+"); default = null; };
      organization = lib.mkOption { type = lib.types.nullOr (lib.types.strMatching "[A-Za-z0-9][A-Za-z0-9-]*"); default = null; };
      runnerGroup = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "Required named organization runner group; its repository and workflow policies are authorization boundaries."; };
      tokenFile = lib.mkOption { type = lib.types.str; description = "Host-only token scoped to this repository or organization with Administration:write."; };
      labels = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ "self-hosted" "Linux" "X64" "ci-${name}-x64" ]; };
      cpus = lib.mkOption { type = lib.types.ints.between 1 8; default = 4; };
      memoryMiB = lib.mkOption { type = lib.types.ints.between 1024 16384; default = 12288; };
      diskGiB = lib.mkOption { type = lib.types.ints.between 20 100; default = 80; };
      ttlSeconds = lib.mkOption { type = lib.types.ints.between 300 14400; default = 3600; };
    };
  };
in {
  options.services.disposableRunners = {
    enable = lib.mkEnableOption "single-job KVM GitHub runners";
    image = lib.mkOption { type = lib.types.path; description = "Immutable qcow2 guest image"; };
    # Kept for existing single-repository configurations; new deployments use pools.
    repository = lib.mkOption { type = lib.types.strMatching "[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+"; default = "unused/legacy"; };
    tokenFile = lib.mkOption { type = lib.types.str; default = "/var/lib/secrets/ci-token"; };
    pools = lib.mkOption { type = lib.types.attrsOf (lib.types.submodule poolOptions); default = { }; description = "One isolated single-job VM per named organization or repository pool."; };
    blockedIPv4 = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; description = "Additional origin/public and infrastructure CIDRs denied to jobs"; };
    blockedIPv4File = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/var/lib/secrets/ci-blocked-ipv4";
      description = "Runtime file, one IPv4 CIDR per line (# comments allowed), loaded into the guest deny set at start. The service fails closed if it is missing or empty.";
    };
    # Legacy single-pool resource settings remain available for imported users.
    count = lib.mkOption { type = lib.types.ints.between 1 2; default = 1; };
    labels = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ "self-hosted" "Linux" "X64" "ci-public-x64" ]; };
    cpus = lib.mkOption { type = lib.types.ints.between 1 8; default = 4; };
    memoryMiB = lib.mkOption { type = lib.types.ints.between 1024 16384; default = 12288; };
    diskGiB = lib.mkOption { type = lib.types.ints.between 20 100; default = 80; };
    ttlSeconds = lib.mkOption { type = lib.types.ints.between 300 14400; default = 3600; };
    minimumFreeGiB = lib.mkOption { type = lib.types.ints.positive; default = 150; };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      { assertion = cfg.blockedIPv4 != [ ] || cfg.blockedIPv4File != null; message = "Set disposableRunners.blockedIPv4File (or blockedIPv4) to production origin IPs before enabling CI."; }
      { assertion = lib.length allSlots <= 16; message = "At most 16 CI pools fit the reserved guest address range."; }
    ] ++ lib.map (pool: {
      assertion = (pool.repository == null) != (pool.organization == null) && (pool.organization == null || pool.runnerGroup != null);
      message = "CI pool ${pool.name} needs exactly one repository or organization; organization pools require a named runner group.";
    }) allSlots;
    boot.kernelModules = [ "kvm-intel" "tun" ];
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
    users.groups.ci-vm = { };
    users.users.ci-vm = { isSystemUser = true; group = "ci-vm"; extraGroups = [ "kvm" ]; };
    systemd.services = { ci-network = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "firewall.service" "docker.service" ];
      path = with pkgs; [ iproute2 nftables iptables ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      script = ''
        if nft list table inet ci_isolation >/dev/null 2>&1; then nft delete table inet ci_isolation; fi
        nft -f ${rules}
        ${lib.optionalString (cfg.blockedIPv4File != null) ''
          test -s ${lib.escapeShellArg cfg.blockedIPv4File} || { echo "blockedIPv4File missing or empty; refusing guest networking" >&2; exit 1; }
          while read -r cidr; do
            case "$cidr" in ""|\#*) continue;; esac
            nft add element inet ci_isolation blocked_origin "{ $cidr }"
          done < ${lib.escapeShellArg cfg.blockedIPv4File}
        ''}
        ${lib.concatMapStringsSep "\n" (pool: ''
          ip tuntap add dev ${pool.tap} mode tap user ci-vm
          ip address add ${pool.address}.1/30 dev ${pool.tap}
          ip link set ${pool.tap} up
        '') allSlots}
        iptables -t nat -A POSTROUTING -s 10.203.0.0/16 ! -o ci-tap+ -j MASQUERADE
      '';
      preStop = ''
        ${lib.concatMapStringsSep "\n" (pool: "ip link delete ${pool.tap} || true") allSlots}
        iptables -t nat -D POSTROUTING -s 10.203.0.0/16 ! -o ci-tap+ -j MASQUERADE || true
        nft delete table inet ci_isolation || true
      '';
    }; } // lib.listToAttrs (map (pool: lib.nameValuePair "ci-runner-${pool.name}" {
      wantedBy = [ "multi-user.target" ];
      requires = [ "ci-network.service" ];
      bindsTo = [ "ci-network.service" ];
      after = [ "ci-network.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        User = "ci-vm";
        Group = "ci-vm";
        SupplementaryGroups = [ "kvm" ];
        StateDirectory = "ci-runner-${pool.name}";
        StateDirectoryMode = "0700";
        LoadCredential = "github-token:${pool.tokenFile}";
        ExecStart = "${pkgs.python3}/bin/python ${../ci/controller.py} ${json.generate "runner-${pool.name}.json" {
          inherit (pool) repository organization runnerGroup labels cpus memoryMiB diskGiB ttlSeconds tap address;
          inherit (cfg) minimumFreeGiB image;
          name = "desu-ci-${pool.name}";
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
        MemoryMax = "${toString (pool.memoryMiB + 1024)}M";
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
    }) allSlots);
  };
}
