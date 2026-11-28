{ lib, ... }:
let
  # Review against https://www.cloudflare.com/ips-v4 and /ips-v6 before deployment.
  v4 = [ "173.245.48.0/20" "103.21.244.0/22" "103.22.200.0/22" "103.31.4.0/22" "141.101.64.0/18" "108.162.192.0/18" "190.93.240.0/20" "188.114.96.0/20" "197.234.240.0/22" "198.41.128.0/17" "162.158.0.0/15" "104.16.0.0/13" "104.24.0.0/14" "172.64.0.0/13" "131.0.72.0/22" ];
  v6 = [ "2400:cb00::/32" "2606:4700::/32" "2803:f800::/32" "2405:b500::/32" "2405:8100::/32" "2a06:98c0::/29" "2c0f:f248::/32" ];
  site = port: { extraConfig = ''
    @notCloudflare not remote_ip ${lib.concatStringsSep " " (v4 ++ v6)}
    respond @notCloudflare 403
    reverse_proxy 127.0.0.1:${toString port} {
      header_up X-Forwarded-For {http.request.header.CF-Connecting-IP}
      header_up X-Real-IP {http.request.header.CF-Connecting-IP}
    }
  ''; };
in {
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 7881 ];
    allowedUDPPorts = [ 7882 ];
    extraCommands = lib.concatMapStringsSep "\n" (range:
      "iptables -A nixos-fw -s ${range} -p tcp -m multiport --dports 80,443 -j nixos-fw-accept") v4
      + "\n" + lib.concatMapStringsSep "\n" (range:
      "ip6tables -A nixos-fw -s ${range} -p tcp -m multiport --dports 80,443 -j nixos-fw-accept") v6;
  };
  # Certificates: Caddy gets Let's Encrypt certificates itself (ACME), as on the old
  # server. The domains are Cloudflare-proxied, so the HTTP-01 challenge arrives
  # from Cloudflare addresses and passes the firewall below; Cloudflare SSL mode
  # must be Full (strict). A DNS-only (grey cloud) record could not be validated.
  services.caddy = {
    enable = true;
    globalConfig = ''
      servers {
        protocols h1 h2
      }
    '';
    virtualHosts = {
      "chat.desu.re" = site 42295;
      "overleaf.desu.re" = site 1337;
      "ttml.desu.re" = site 8000;
    };
  };
}
