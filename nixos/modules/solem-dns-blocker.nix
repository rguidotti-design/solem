{ config, pkgs, lib, ... }:

# SOLEM DNS BLOCKER — telemetry + ads blocker locale (Pi-hole style).
#
# Single responsibility: SOLO orchestrare blocky (Go, FOSS, leggero) come
# DNS resolver locale + blocklist anti-tracking/ads/malware.
#
# Default: ascolta 127.0.0.1:53 + ::1:53. Upstream: stubby (DoT) → Cloudflare
# + Quad9 (privacy-preserving). Già config in solem-dns-private.nix.
#
# Blocklist FOSS (auto-aggiornate):
#   - StevenBlack hosts unified
#   - oisd-big
#   - EasyList
#   - URLhaus
#
# 100% offline, costo 0 €.

let
  cfg = config.solem.dnsBlocker;
in {
  options.solem.dnsBlocker = {
    enable = lib.mkEnableOption "DNS blocker (blocky) anti-telemetry/ads/malware";

    blocklists = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = {
        ads = [ "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts" ];
        oisd = [ "https://big.oisd.nl/" ];
        malware = [ "https://urlhaus.abuse.ch/downloads/hostfile/" ];
      };
    };

    upstreamGroups = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = {
        default = [
          "tcp-tls:1.1.1.1:853"        # Cloudflare DoT
          "tcp-tls:9.9.9.9:853"        # Quad9 DoT
          "tcp-tls:dns.quad9.net"
        ];
      };
    };

    allowedClients = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "127.0.0.1/8" "::1/128" "10.42.0.0/24" ];
      description = "CIDR whitelist (mesh + localhost)";
    };
  };

  config = lib.mkIf cfg.enable {
    services.blocky = {
      enable = true;
      settings = {
        ports = {
          dns = 53;
          http = 4000;  # dashboard locale
        };
        upstreams.groups = cfg.upstreamGroups;
        bootstrapDns = {
          upstream = "tcp-tls:1.1.1.1:853";
          ips = [ "1.1.1.1" "1.0.0.1" ];
        };
        blocking = {
          denylists = cfg.blocklists;
          clientGroupsBlock.default = builtins.attrNames cfg.blocklists;
          blockType = "zeroIp";
        };
        caching = {
          minTime = "5m";
          maxTime = "30m";
          prefetching = true;
          prefetchExpires = "2h";
        };
        prometheus.enable = true;
        log.level = "info";
      };
    };

    # Apri firewall solo per client whitelist
    networking.firewall = {
      interfaces."lo".allowedTCPPorts = [ 53 4000 ];
      interfaces."lo".allowedUDPPorts = [ 53 ];
    };
  };
}
