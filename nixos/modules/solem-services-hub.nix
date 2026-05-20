{ config, pkgs, lib, ... }:

# SOLEM SERVICES HUB — dashboard unificata self-hosted services (Homepage).
#
# Single responsibility: SOLO orchestrare homepage server + config statica.
# Aggrega link a tutti i servizi self-host attivi (Forgejo, Immich, Navidrome,
# Vaultwarden, Grafana, Radicale, Headscale, etc.).
#
# 100% FOSS (gethomepage.dev MIT), costo 0 €.

let
  cfg = config.solem.servicesHub;

  servicesYaml = pkgs.writeText "services.yaml" ''
    - Gestione:
        - Forgejo:
            href: http://localhost:3000
            description: Git server self-host
            icon: gitea
        - Vaultwarden:
            href: http://localhost:8222
            description: Password manager
            icon: bitwarden
        - Nextcloud:
            href: http://localhost:8080
            description: Cloud privato
            icon: nextcloud

    - Multimedia:
        - Immich:
            href: http://localhost:2283
            description: Photo library
            icon: immich
        - Navidrome:
            href: http://localhost:4533
            description: Music streaming
            icon: navidrome
        - Jellyfin:
            href: http://localhost:8096
            description: Media center
            icon: jellyfin

    - Calendario:
        - Radicale:
            href: http://localhost:5232
            description: CalDAV/CardDAV
            icon: radicale

    - Monitoring:
        - Grafana:
            href: http://localhost:3001
            description: Metrics dashboard
            icon: grafana
        - Prometheus:
            href: http://localhost:9090
            description: Time-series DB
            icon: prometheus
        - Netdata:
            href: http://localhost:19999
            description: Realtime monitor
            icon: netdata

    - Network:
        - Headscale:
            href: http://localhost:8080
            description: Mesh VPN control
            icon: tailscale
        - Blocky:
            href: http://localhost:4000
            description: DNS blocker stats
            icon: pi-hole

    - AI:
        - SOLEM API:
            href: http://localhost:8001
            description: SOLEM core
            icon: si-fastapi
        - Ollama:
            href: http://localhost:11434
            description: LLM server
            icon: si-ollama
        - GAVIO:
            href: http://localhost:8000
            description: Personal AI
            icon: ai
  '';

  settingsYaml = pkgs.writeText "settings.yaml" ''
    title: SOLEM
    headerStyle: clean
    background:
      image: /etc/solem/wallpaper.png
      blur: md
      opacity: 60
    theme: dark
    color: slate
    layout:
      Gestione:
        style: row
        columns: 3
      Multimedia:
        style: row
        columns: 3
      AI:
        style: row
        columns: 3
  '';
in {
  options.solem.servicesHub = {
    enable = lib.mkEnableOption "Homepage dashboard unificata self-host services";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3001;
    };
  };

  config = lib.mkIf cfg.enable {
    services.homepage-dashboard = {
      enable = true;
      listenPort = cfg.port;
      services = [
        {
          "Quick" = [
            { "SOLEM API" = { href = "http://localhost:8001"; icon = "fastapi.svg"; }; }
          ];
        }
      ];
      settings = {
        title = "SOLEM";
        theme = "dark";
        color = "slate";
      };
    };

    # Drop config files
    environment.etc."solem/homepage/services.yaml".source = servicesYaml;
    environment.etc."solem/homepage/settings.yaml".source = settingsYaml;
  };
}
