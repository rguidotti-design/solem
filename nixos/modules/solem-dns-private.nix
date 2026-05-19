{ config, pkgs, lib, ... }:

let
  cfg = config.solem.dnsPrivate;
in {
  # ──────────────────────────────────────────────────────────────────────
  # SOLEM DNS PRIVATE — DoT/DoH via stubby + unbound
  # ──────────────────────────────────────────────────────────────────────
  # Single responsibility: SOLO DNS privato cifrato.
  #
  # Flow:
  #   applicazioni → unbound (127.0.0.1:53) → stubby (127.0.0.1:5353 DoT)
  #                                          → upstream server (cifrato)
  #
  # Default upstream: Cloudflare + Quad9 (entrambi free, no carta, no tracking).

  options.solem.dnsPrivate = {
    enable = lib.mkEnableOption "DoT/DoH DNS privato cifrato (stubby+unbound)";

    upstreams = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          address = lib.mkOption { type = lib.types.str; };
          port = lib.mkOption { type = lib.types.int; default = 853; };
          name = lib.mkOption { type = lib.types.str; description = "Hostname per TLS verify"; };
        };
      });
      default = [
        { address = "1.1.1.1"; name = "cloudflare-dns.com"; }
        { address = "9.9.9.9"; name = "dns.quad9.net"; }
      ];
      description = "Server upstream DoT (default Cloudflare + Quad9).";
    };
  };

  config = lib.mkIf cfg.enable {
    # stubby: relay DoT → upstream cifrato
    services.stubby = {
      enable = true;
      settings = {
        resolution_type = "GETDNS_RESOLUTION_STUB";
        dns_transport_list = [ "GETDNS_TRANSPORT_TLS" ];
        tls_authentication = "GETDNS_AUTHENTICATION_REQUIRED";
        tls_query_padding_blocksize = 128;
        edns_client_subnet_private = 1;
        round_robin_upstreams = 1;
        idle_timeout = 10000;
        listen_addresses = [ "127.0.0.1@5353" ];
        upstream_recursive_servers = map (s: {
          address_data = s.address;
          tls_port = s.port;
          tls_auth_name = s.name;
        }) cfg.upstreams;
      };
    };

    # unbound: cache locale + forward a stubby
    services.unbound = {
      enable = true;
      settings = {
        server = {
          interface = [ "127.0.0.1" ];
          port = 53;
          access-control = [ "127.0.0.0/8 allow" "::1 allow" ];
          do-tcp = true;
          do-udp = true;
          # privacy
          hide-identity = true;
          hide-version = true;
          qname-minimisation = true;
          aggressive-nsec = true;
          # cache
          cache-min-ttl = 300;
          cache-max-ttl = 14400;
          prefetch = true;
        };
        # Forward TUTTO a stubby (che fa DoT)
        forward-zone = [{
          name = ".";
          forward-addr = "127.0.0.1@5353";
        }];
      };
    };

    # Sistema usa unbound come resolver
    networking.nameservers = lib.mkForce [ "127.0.0.1" ];
    services.resolved.enable = lib.mkForce false;

    environment.etc."solem/dns-private-config.json".text = builtins.toJSON {
      enabled = cfg.enable;
      resolver = "unbound (127.0.0.1:53)";
      dot_relay = "stubby (127.0.0.1:5353)";
      upstreams = map (s: "${s.address} (${s.name})") cfg.upstreams;
    };
  };
}
