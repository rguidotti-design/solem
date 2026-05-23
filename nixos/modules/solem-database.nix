{ config, pkgs, lib, ... }:

# SOLEM DATABASE — PostgreSQL + Redis + pgAdmin GUI preconfig.
#
# Single responsibility: SOLO orchestrare DB engines + GUI client.
# Niente schema (l'utente lo gestisce).

let
  cfg = config.solem.database;
in {
  options.solem.database = {
    postgres = {
      enable = lib.mkEnableOption "PostgreSQL server";
      version = lib.mkOption {
        type = lib.types.enum [ "15" "16" "17" ];
        default = "16";
      };
      databases = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "gavio" ];
        description = "DB da creare al primo boot";
      };
      authentication = lib.mkOption {
        type = lib.types.lines;
        default = ''
          local all all peer
          host  all all 127.0.0.1/32 trust
          host  all all ::1/128 trust
        '';
      };
    };

    redis = {
      enable = lib.mkEnableOption "Redis server (cache/queue)";
      port = lib.mkOption { type = lib.types.port; default = 6379; };
    };

    mariadb = lib.mkEnableOption "MariaDB (MySQL-compatible)";

    sqliteTools = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "sqlite-utils + sqlite-browser GUI";
    };

    gui = lib.mkEnableOption "DBeaver GUI universale (PostgreSQL/MySQL/SQLite/MariaDB)";
  };

  config = lib.mkMerge [
    # PostgreSQL
    (lib.mkIf cfg.postgres.enable {
      services.postgresql = {
        enable = true;
        package = pkgs."postgresql_${cfg.postgres.version}";
        ensureDatabases = cfg.postgres.databases;
        ensureUsers = map (db: {
          name = db;
          ensureDBOwnership = true;
        }) cfg.postgres.databases;
        authentication = cfg.postgres.authentication;
        settings = {
          listen_addresses = "127.0.0.1";
          max_connections = 100;
          shared_buffers = "256MB";
          effective_cache_size = "1GB";
        };
      };

      environment.systemPackages = with pkgs; [
        pgcli            # CLI bello con autocomplete
        postgresql_16   # client psql
      ];
    })

    # Redis
    (lib.mkIf cfg.redis.enable {
      services.redis.servers.solem = {
        enable = true;
        port = cfg.redis.port;
        bind = "127.0.0.1";
      };
      environment.systemPackages = [ pkgs.redis ];  # CLI redis-cli
    })

    # MariaDB
    (lib.mkIf cfg.mariadb {
      services.mysql = {
        enable = true;
        package = pkgs.mariadb;
      };
      environment.systemPackages = [ pkgs.mariadb ];
    })

    # SQLite tools
    (lib.mkIf cfg.sqliteTools {
      environment.systemPackages = with pkgs; [
        sqlite
        sqlite-interactive
        sqlitebrowser
      ];
    })

    # GUI universale
    (lib.mkIf cfg.gui {
      environment.systemPackages = [ pkgs.dbeaver-bin ];
    })
  ];
}
