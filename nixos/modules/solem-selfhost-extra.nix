{ config, pkgs, lib, ... }:

# SOLEM SELFHOST EXTRA — Vikunja (task) + HedgeDoc (collab) + Owncast.
#
# Single responsibility: SOLO orchestrare 3 servizi self-host molto utili
# per il lavoro quotidiano, tutti opt-in indipendenti.

let
  cfg = config.solem.selfhostExtra;
in {
  options.solem.selfhostExtra = {
    vikunja = {
      enable = lib.mkEnableOption "Vikunja task tracker (Trello-like self-host)";
      port = lib.mkOption { type = lib.types.port; default = 3456; };
    };

    hedgedoc = {
      enable = lib.mkEnableOption "HedgeDoc (real-time collab markdown editor)";
      port = lib.mkOption { type = lib.types.port; default = 3000; };
    };

    owncast = {
      enable = lib.mkEnableOption "Owncast (self-host live streaming Twitch-alike)";
      port = lib.mkOption { type = lib.types.port; default = 8080; };
    };

    etherpad = {
      enable = lib.mkEnableOption "Etherpad (collab text legacy ma robusto)";
      port = lib.mkOption { type = lib.types.port; default = 9001; };
    };

    plane = {
      enable = lib.mkEnableOption "Plane (Linear/Jira self-host alternativa)";
    };
  };

  config = lib.mkMerge [
    # Vikunja
    (lib.mkIf cfg.vikunja.enable {
      services.vikunja = {
        enable = true;
        port = cfg.vikunja.port;
        frontendScheme = "http";
        frontendHostname = "tasks.solem.local";
        database = {
          type = "sqlite";
          path = "/var/lib/vikunja/vikunja.db";
        };
      };
    })

    # HedgeDoc
    (lib.mkIf cfg.hedgedoc.enable {
      services.hedgedoc = {
        enable = true;
        settings = {
          port = cfg.hedgedoc.port;
          domain = "notes.solem.local";
          protocolUseSSL = false;
          allowFreeURL = true;
          allowAnonymous = true;
          dbURL = "sqlite:///var/lib/hedgedoc/db.sqlite";
        };
      };
    })

    # Owncast
    (lib.mkIf cfg.owncast.enable {
      services.owncast = {
        enable = true;
        port = cfg.owncast.port;
        rtmp-port = 1935;
      };
      networking.firewall.allowedTCPPorts = [ 1935 ];
    })

    # Etherpad
    (lib.mkIf cfg.etherpad.enable {
      services.etherpad = {
        enable = true;
        plugins = [];
      };
    })

    # Plane
    (lib.mkIf cfg.plane.enable {
      # Plane non è nei nixpkgs ufficiali. Workaround: usa docker-compose.
      # Esempio compose stub:
      environment.etc."solem/plane-docker-compose.yml".text = ''
        # Plane self-host via docker-compose
        # https://docs.plane.so/self-hosting/docker-compose
        # Esegui: cd /etc/solem && docker compose -f plane-docker-compose.yml up -d
        version: "3"
        services:
          plane-app:
            image: makeplane/plane-app:latest
            ports: ["8000:8000"]
            environment:
              - PGUSER=plane
              - PGPASSWORD=plane
              - PGHOST=plane-db
            depends_on: [plane-db]
          plane-db:
            image: postgres:15
            environment:
              - POSTGRES_USER=plane
              - POSTGRES_PASSWORD=plane
              - POSTGRES_DB=plane
            volumes: [plane-db:/var/lib/postgresql/data]
        volumes:
          plane-db:
      '';
    })
  ];
}
