{ config, pkgs, lib, ... }:

# SOLEM RADICALE — server CalDAV/CardDAV locale, opt-in.
#
# Single responsibility: SOLO orchestrare Radicale (calendar + contatti
# sincronizzati via standard CalDAV/CardDAV). Niente client (Evolution,
# Thunderbird, KOrganizer si configurano lato user).
#
# Vantaggi:
#   - 100% locale, sync via mesh WireGuard
#   - Standard aperti → compat con tutti i client (Android DAVx5, iOS,
#     Thunderbird, Evolution)
#   - FOSS, costo 0 €
#
# Default: bind 127.0.0.1:5232 (no esposizione esterna).

let
  cfg = config.solem.radicale;
in {
  options.solem.radicale = {
    enable = lib.mkEnableOption "Server CalDAV/CardDAV Radicale (calendar + contatti)";

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "IP listen (127.0.0.1 default; mesh.solem.local per multi-device)";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 5232;
    };

    htpasswdFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path htpasswd auth file (null = no auth, solo per dev locale)";
    };
  };

  config = lib.mkIf cfg.enable {
    services.radicale = {
      enable = true;
      settings = {
        server = {
          hosts = "${cfg.bindAddress}:${toString cfg.port}";
          max_connections = 20;
          timeout = 30;
        };
        encoding = {
          request = "utf-8";
          stock = "utf-8";
        };
        auth = if cfg.htpasswdFile != null then {
          type = "htpasswd";
          htpasswd_filename = toString cfg.htpasswdFile;
          htpasswd_encryption = "bcrypt";
        } else {
          type = "none";
        };
        storage = {
          filesystem_folder = "/var/lib/radicale/collections";
        };
        logging = {
          level = "info";
        };
      };
    };

    # Backup integration: includi radicale data nel restic backup
    systemd.tmpfiles.rules = [
      "d /var/lib/radicale            0755 radicale radicale - -"
      "d /var/lib/radicale/collections 0755 radicale radicale - -"
    ];
  };
}
