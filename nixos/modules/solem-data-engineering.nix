{ config, pkgs, lib, ... }:

# SOLEM DATA ENGINEERING — toolkit data science / analytics 100% FOSS.
#
# Single responsibility: SOLO tool data engineering FOSS:
# - DuckDB    → analitica colonnare in-process (MIT)
# - ClickHouse → OLAP columnar database (Apache-2.0)
# - MinIO     → S3-compatible self-host (AGPL-3.0)
# - Apache Arrow → format colonnare zero-copy (Apache-2.0)
# - SQLite + Datasette → publish dataset (Apache-2.0)
# - jq / yq / xsv / qsv → CLI data manipulation
# - Visidata → spreadsheet TUI (GPL-3.0)
# - Apache Superset (opt-in) → BI dashboard (Apache-2.0)
# - Metabase (opt-in) → BI free CE (AGPL-3.0)
#
# 0 €. Niente Tableau / Power BI / Looker (closed/paid).

let
  cfg = config.solem.dataEngineering;
in {
  options.solem.dataEngineering = {
    enable = lib.mkEnableOption "Toolkit data engineering FOSS (DuckDB + MinIO + Arrow + Visidata)";

    minio = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Avvia MinIO server S3-compatible (storage object self-host)";
    };

    clickhouse = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "ClickHouse server (OLAP columnar, alternative a BigQuery)";
    };

    datasette = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Datasette CLI per pubblicare SQLite come API + UI";
    };

    metabase = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Metabase Community Edition (BI dashboard, AGPL-3.0). Server Java.
        Opt-in per peso (Java + JVM). Alternativa libera a Tableau/Power BI.
      '';
    };

    minioPort = lib.mkOption {
      type = lib.types.port;
      default = 9000;
      description = "Porta MinIO API (default 9000); console su 9001";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      environment.systemPackages = with pkgs; lib.flatten [
        [
          # Embedded analytics
          duckdb

          # Apache Arrow
          arrow-cpp

          # CLI data wrangling
          jq
          yq-go
          xsv         # CSV manipulation Rust
          qsv         # qsv (xsv successore Rust)
          miller      # CSV/JSON/TSV transformer
          csvkit      # Python CSV toolbox
          visidata    # TUI spreadsheet
          octosql     # SQL across CSV/JSON/MySQL/Postgres

          # SQLite
          sqlite
          sqlite-utils  # Simon Willison toolkit

          # Streaming / queue (solo FOSS)
          nats-server   # NATS messaging (Apache-2.0)
          apacheKafka   # Kafka classico (Apache-2.0) — alt FOSS a Redpanda BSL
        ]

        (lib.optionals cfg.datasette [
          datasette
        ])
      ];
    }

    # MinIO server (S3-compatible)
    (lib.mkIf cfg.minio {
      services.minio = {
        enable = true;
        listenAddress = "127.0.0.1:${toString cfg.minioPort}";
        consoleAddress = "127.0.0.1:9001";
        rootCredentialsFile = "/var/lib/minio/credentials";
        dataDir = [ "/var/lib/minio/data" ];
      };
    })

    # ClickHouse OLAP
    (lib.mkIf cfg.clickhouse {
      services.clickhouse.enable = true;
    })

    # Metabase BI dashboard
    (lib.mkIf cfg.metabase {
      services.metabase = {
        enable = true;
        listen = {
          ip = "127.0.0.1";
          port = 3000;
        };
      };
    })
  ]);
}
