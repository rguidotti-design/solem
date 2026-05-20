{ config, pkgs, lib, ... }:

# SOLEM SELFHOST — moduli self-hosted opt-in 100% FOSS.
#
# Single responsibility: SOLO orchestrazione modulo (enable + porte +
# directory). Niente custom logic: deleghiamo a moduli upstream NixOS.
#
# Tutti opt-in (default disabilitati). Ognuno indipendente.
#   solem.selfhost.forgejo      → git hosting (porta 3000)
#   solem.selfhost.vaultwarden  → password manager (porta 8222)
#   solem.selfhost.nextcloud    → cloud privato (porta 8080)
#   solem.selfhost.matrix       → chat federata (porta 8448)
#
# Tutti gratis, tutti FOSS, tutti senza account cloud.

let
  cfg = config.solem.selfhost;
in {
  options.solem.selfhost = {
    forgejo = {
      enable = lib.mkEnableOption "Forgejo git server (alternativa GitHub)";
      port = lib.mkOption { type = lib.types.port; default = 3000; };
    };

    vaultwarden = {
      enable = lib.mkEnableOption "Vaultwarden password manager (Bitwarden compat)";
      port = lib.mkOption { type = lib.types.port; default = 8222; };
    };

    nextcloud = {
      enable = lib.mkEnableOption "Nextcloud cloud privato (file, calendar, contatti)";
      hostname = lib.mkOption { type = lib.types.str; default = "cloud.solem.local"; };
      adminPassFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path file con password admin (richiesto se nextcloud.enable=true)";
      };
    };

    matrix = {
      enable = lib.mkEnableOption "Matrix Synapse homeserver (chat federata E2E)";
      serverName = lib.mkOption { type = lib.types.str; default = "solem.local"; };
    };
  };

  config = lib.mkMerge [
    # ── Forgejo (fork comunitario di Gitea, 100% FOSS) ──
    (lib.mkIf cfg.forgejo.enable {
      services.forgejo = {
        enable = true;
        settings = {
          server = {
            HTTP_PORT = cfg.forgejo.port;
            DOMAIN = "git.solem.local";
            ROOT_URL = "http://git.solem.local:${toString cfg.forgejo.port}/";
          };
          service.DISABLE_REGISTRATION = true;
        };
      };
    })

    # ── Vaultwarden (Bitwarden server in Rust, FOSS) ──
    (lib.mkIf cfg.vaultwarden.enable {
      services.vaultwarden = {
        enable = true;
        config = {
          ROCKET_ADDRESS = "127.0.0.1";
          ROCKET_PORT = cfg.vaultwarden.port;
          SIGNUPS_ALLOWED = false;
          DOMAIN = "https://vault.solem.local";
        };
      };
    })

    # ── Nextcloud (PHP, full cloud) ──
    (lib.mkIf cfg.nextcloud.enable {
      assertions = [{
        assertion = cfg.nextcloud.adminPassFile != null;
        message = "solem.selfhost.nextcloud.adminPassFile è richiesto quando nextcloud.enable=true";
      }];

      services.nextcloud = {
        enable = true;
        hostName = cfg.nextcloud.hostname;
        package = pkgs.nextcloud30;
        config = {
          adminuser = "admin";
          adminpassFile = cfg.nextcloud.adminPassFile;
          dbtype = "sqlite";
        };
        settings = {
          trusted_domains = [ cfg.nextcloud.hostname "localhost" ];
        };
      };
    })

    # ── Matrix Synapse (homeserver federato E2E) ──
    (lib.mkIf cfg.matrix.enable {
      services.matrix-synapse = {
        enable = true;
        settings = {
          server_name = cfg.matrix.serverName;
          public_baseurl = "https://${cfg.matrix.serverName}";
          listeners = [{
            port = 8008;
            bind_addresses = [ "127.0.0.1" ];
            type = "http";
            tls = false;
            x_forwarded = true;
            resources = [{ names = [ "client" "federation" ]; compress = false; }];
          }];
        };
      };
    })
  ];
}
