{ config, pkgs, lib, ... }:

# SOLEM NETWORK STACK — la macchina SOLEM diventa gateway di rete propria.
#
# Single responsibility: SOLO orchestrare i servizi di rete che fanno di
# SOLEM una "rete autonoma": DHCP server, DNS authoritative interno,
# router/NAT, mesh ingress, port-forward management.
#
# Topologia tipica:
#
#    [Internet] ─── (uplinkIface=wan)
#                       │
#                       │ NAT + firewall
#                       ▼
#    [SOLEM box] ─── (lanIface=lan)
#                       │
#                       │ DHCP + DNS + zona .solem.local
#                       ▼
#    [client casalinghi] (smartphone, laptop, IoT)
#
# 100% FOSS, costo 0 €.

let
  cfg = config.solem.networkStack;
in {
  options.solem.networkStack = {
    enable = lib.mkEnableOption "Network stack proprio (gateway DHCP+DNS+NAT)";

    uplinkIface = lib.mkOption {
      type = lib.types.str;
      default = "eth0";
      description = "Interfaccia verso Internet (WAN)";
    };

    lanIface = lib.mkOption {
      type = lib.types.str;
      default = "eth1";
      description = "Interfaccia verso rete locale (LAN)";
    };

    lanSubnet = lib.mkOption {
      type = lib.types.str;
      default = "10.99.0.0/24";
      description = "Subnet LAN gestita da SOLEM";
    };

    lanGateway = lib.mkOption {
      type = lib.types.str;
      default = "10.99.0.1";
      description = "IP SOLEM su LAN (gateway dei client)";
    };

    dhcpRangeStart = lib.mkOption { type = lib.types.str; default = "10.99.0.100"; };
    dhcpRangeEnd   = lib.mkOption { type = lib.types.str; default = "10.99.0.200"; };

    internalDomain = lib.mkOption {
      type = lib.types.str;
      default = "solem.local";
      description = "Dominio interno (es. gavio.solem.local, immich.solem.local)";
    };

    internalHosts = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        gavio        = "10.99.0.1";
        api          = "10.99.0.1";
        immich       = "10.99.0.1";
        navidrome    = "10.99.0.1";
        forgejo      = "10.99.0.1";
        vault        = "10.99.0.1";
        cloud        = "10.99.0.1";
        grafana      = "10.99.0.1";
        radicale     = "10.99.0.1";
      };
      description = "Mappa hostname → IP (registrati in DNS interno)";
    };

    upstreamDns = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "1.1.1.1" "9.9.9.9" ];
      description = "DNS upstream per query non-locali";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── IP forwarding (router behavior) ──
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
      "net.ipv4.conf.all.rp_filter" = 1;
      "net.ipv4.conf.default.rp_filter" = 1;
    };

    # ── IP statico su LAN ──
    networking.interfaces.${cfg.lanIface}.ipv4.addresses = [{
      address = cfg.lanGateway;
      prefixLength = 24;
    }];

    networking.nftables = {
      enable = true;
      ruleset = ''
        table inet filter {
          chain input {
            type filter hook input priority 0; policy drop;
            ct state {established, related} accept
            ct state invalid drop
            iif lo accept
            iifname "${cfg.lanIface}" accept
            ip protocol icmp accept
            ip6 nexthdr icmpv6 accept
            udp dport 67 accept  # DHCP
            tcp dport 22 accept  # SSH
          }
          chain forward {
            type filter hook forward priority 0; policy drop;
            ct state {established, related} accept
            ct state invalid drop
            iifname "${cfg.lanIface}" oifname "${cfg.uplinkIface}" accept
          }
          chain output {
            type filter hook output priority 0; policy accept;
          }
        }
        table ip nat {
          chain postrouting {
            type nat hook postrouting priority 100; policy accept;
            oifname "${cfg.uplinkIface}" masquerade
          }
        }
      '';
    };

    # ── DHCP server (dnsmasq integrato con DNS) ──
    services.dnsmasq = {
      enable = true;
      settings = {
        interface = cfg.lanIface;
        bind-interfaces = true;
        domain-needed = true;
        bogus-priv = true;
        no-resolv = true;
        server = cfg.upstreamDns;

        dhcp-range = "${cfg.dhcpRangeStart},${cfg.dhcpRangeEnd},24h";
        dhcp-option = [
          "3,${cfg.lanGateway}"     # gateway
          "6,${cfg.lanGateway}"     # DNS
        ];

        # DNS interno: solem.local zona
        local = "/${cfg.internalDomain}/";
        domain = cfg.internalDomain;
        expand-hosts = true;

        # Cache aggressivo
        cache-size = 1000;
        dns-forward-max = 150;

        # Niente telemetry
        log-queries = false;
      };
    };

    # ── DNS records statici dei servizi ──
    networking.extraHosts = lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: ip: "${ip} ${name}.${cfg.internalDomain}") cfg.internalHosts
    );

    # ── Firewall NixOS coerente ──
    networking.firewall = {
      enable = true;
      allowedTCPPorts = [ 22 53 80 443 ];
      allowedUDPPorts = [ 53 67 68 ];
      trustedInterfaces = [ cfg.lanIface ];
    };

    # ── Reverse proxy (Caddy) per gli host interni ──
    services.caddy = {
      enable = true;
      virtualHosts = lib.mapAttrs' (name: ip: lib.nameValuePair "${name}.${cfg.internalDomain}" {
        extraConfig = ''
          reverse_proxy ${ip}:8001
        '';
      }) cfg.internalHosts;
    };

    # ── Tools di rete ──
    environment.systemPackages = with pkgs; [
      dnsmasq nftables conntrack-tools
      bind  # dig
      wireguard-tools
    ];
  };
}
