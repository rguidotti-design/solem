{ config, pkgs, lib, ... }:

# SOLEM CLOUD PERSONAL — cloud personale FOSS (rimpiazza iCloud/OneDrive).
#
# Single responsibility: SOLO orchestrare bundle "Personal Cloud" self-host:
# - Nextcloud           → file sync + photo + calendar + contacts (AGPL-3.0)
# - Joplin Server       → note sync E2EE (AGPL-3.0)
# - Vaultwarden         → password sync E2EE (AGPL-3.0)
# - Radicale            → CalDAV + CardDAV (GPL-3.0)
# - Syncthing           → file P2P device-to-device (MPL-2.0)
#
# Tutto su un singolo nodo (Beelink / Pi5 / mini-PC). 0 €.
# Risponde gap "Cloud backup E2EE built-in" COMPETITIVE-GAP.md.

let
  cfg = config.solem.cloudPersonal;
in {
  options.solem.cloudPersonal = {
    enable = lib.mkEnableOption "Cloud personale FOSS bundle (Nextcloud + Joplin + Vault + CalDAV + Syncthing)";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "solem.local";
      description = "Dominio per esposizione locale (default solem.local via mDNS)";
    };

    nextcloud = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Nextcloud (file + foto + cal + contacts)";
    };

    joplin = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Joplin Server (note markdown E2EE)";
    };

    vaultwarden = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Vaultwarden (password manager Bitwarden CE)";
    };

    radicale = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Radicale (CalDAV/CardDAV — sync calendar/contatti)";
    };

    syncthing = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Syncthing (file P2P direct device-to-device)";
    };

    adminEmail = lib.mkOption {
      type = lib.types.str;
      default = "admin@solem.local";
      description = "Email admin (richiesta da Nextcloud)";
    };

    nextcloudPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path al file contenente admin password Nextcloud. Se null,
        è generata casualmente al primo boot (vedere /var/lib/nextcloud).
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    # ── Nextcloud ────────────────────────────────────────────────────
    (lib.mkIf cfg.nextcloud {
      services.nextcloud = {
        enable = true;
        package = pkgs.nextcloud30;
        hostName = cfg.domain;
        https = false;       # local-only LAN; usa reverse-proxy Caddy per TLS
        maxUploadSize = "16G";
        autoUpdateApps.enable = true;
        configureRedis = true;
        database.createLocally = true;
        config = {
          adminuser = "solem";
          adminpassFile = lib.mkIf (cfg.nextcloudPasswordFile != null) cfg.nextcloudPasswordFile;
          dbtype = "pgsql";
        };
        extraApps = {
          inherit (config.services.nextcloud.package.packages.apps)
            calendar contacts notes mail tasks deck;
        };
        extraAppsEnable = true;
        settings = {
          default_phone_region = "IT";
          overwriteprotocol = "http";
          trusted_domains = [ cfg.domain "localhost" "127.0.0.1" ];
        };
      };
      services.postgresql.enable = true;
    })

    # ── Joplin Server ───────────────────────────────────────────────
    (lib.mkIf cfg.joplin {
      services.joplin-server = {
        enable = true;
        port = 22300;
        baseUrl = "http://${cfg.domain}:22300";
        database = {
          type = "pg";
          host = "127.0.0.1";
          name = "joplin";
          user = "joplin";
        };
      };
    })

    # ── Vaultwarden ─────────────────────────────────────────────────
    (lib.mkIf cfg.vaultwarden {
      services.vaultwarden = {
        enable = true;
        config = {
          DOMAIN = "http://${cfg.domain}:8222";
          SIGNUPS_ALLOWED = true;
          ROCKET_ADDRESS = "127.0.0.1";
          ROCKET_PORT = 8222;
          WEBSOCKET_ENABLED = true;
        };
      };
    })

    # ── Radicale CalDAV/CardDAV ─────────────────────────────────────
    (lib.mkIf cfg.radicale {
      services.radicale = {
        enable = true;
        settings = {
          server.hosts = [ "127.0.0.1:5232" ];
          auth.type = "htpasswd";
          auth.htpasswd_filename = "/var/lib/radicale/users";
          auth.htpasswd_encryption = "bcrypt";
          storage.filesystem_folder = "/var/lib/radicale/collections";
        };
      };
    })

    # ── Syncthing ───────────────────────────────────────────────────
    (lib.mkIf cfg.syncthing {
      services.syncthing = {
        enable = true;
        openDefaultPorts = true;
        guiAddress = "127.0.0.1:8384";
      };
    })

    # ── Apertura firewall locale (LAN only) ──────────────────────────
    {
      networking.firewall.allowedTCPPorts = lib.flatten [
        (lib.optionals cfg.nextcloud [ 80 443 ])
        (lib.optionals cfg.joplin [ 22300 ])
        (lib.optionals cfg.vaultwarden [ 8222 ])
        (lib.optionals cfg.syncthing [ 22000 ])
        (lib.optionals cfg.radicale [ 5232 ])
      ];
      networking.firewall.allowedUDPPorts = lib.optionals cfg.syncthing [ 22000 21027 ];
    }
  ]);
}
