{ config, pkgs, lib, ... }:

# SOLEM HEADSCALE — Tailscale-compatible control plane self-hosted, FOSS.
#
# Single responsibility: SOLO orchestrare headscale server. Niente client
# (è in solem-mesh per WireGuard custom o tailscale per client compat).
#
# Vantaggi su Tailscale ufficiale:
#   - 100% self-host: control plane sul TUO server
#   - Niente account Microsoft/Tailscale
#   - 100% FOSS (BSD-3-Clause)
#   - Client compatibili Tailscale Android/iOS/desktop
#
# Costo: 0 € (vs Tailscale 5$/user/mese per teams).

let
  cfg = config.solem.headscale;
in {
  options.solem.headscale = {
    enable = lib.mkEnableOption "Headscale (Tailscale control plane self-hosted)";

    address = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Bind address (127.0.0.1 default; pubblica via Caddy mTLS)";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
    };

    serverUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://headscale.solem.local";
      description = "URL pubblico (mesh DNS interno)";
    };

    ipv4Range = lib.mkOption {
      type = lib.types.str;
      default = "100.64.0.0/10";
      description = "Tailscale-compat CGNAT range";
    };
  };

  config = lib.mkIf cfg.enable {
    services.headscale = {
      enable = true;
      address = cfg.address;
      port = cfg.port;
      settings = {
        server_url = cfg.serverUrl;
        ip_prefixes = [ cfg.ipv4Range ];

        # No DERP relay esterno (privacy: traffico solo P2P o via tuo server)
        derp = {
          server.enabled = true;
          server.region_id = 999;
          server.region_code = "solem";
          server.region_name = "SOLEM Mesh";
          server.stun_listen_addr = "${cfg.address}:3478";
        };

        # Disable analytics
        disable_check_updates = true;
        ephemeral_node_inactivity_timeout = "30m";

        # DNS interno
        dns_config = {
          override_local_dns = false;
          nameservers = [ "1.1.1.1" "9.9.9.9" ];
          magic_dns = true;
          base_domain = "solem.local";
        };

        # Database SQLite (sufficiente per nodi <100)
        db_type = "sqlite3";
        db_path = "/var/lib/headscale/db.sqlite";

        logtail.enabled = false;
        randomize_client_port = false;
      };
    };

    # Client tailscale per join al control plane
    services.tailscale = {
      enable = true;
      openFirewall = true;
    };

    networking.firewall = {
      allowedTCPPorts = [ cfg.port ];
      allowedUDPPorts = [ 3478 41641 ];  # STUN + tailscale udp
    };

    environment.systemPackages = with pkgs; [
      headscale tailscale
    ];
  };
}
