{ config, pkgs, lib, ... }:

# SOLEM MONITORING — stack osservabilità 100% FOSS, opt-in.
#
# Single responsibility: SOLO orchestrazione moduli upstream (prometheus,
# grafana, loki, netdata). Tutta la business logic vive nei moduli NixOS
# upstream.
#
# Default: tutto disabilitato (default minimal di SOLEM).
# Si abilita selettivamente: solem.monitoring.prometheus.enable = true; ...
#
# Costo: 0 €. Nessun account esterno, nessun cloud.

let
  cfg = config.solem.monitoring;
in {
  options.solem.monitoring = {
    prometheus = {
      enable = lib.mkEnableOption "Prometheus metrics server (porta 9090)";
      retention = lib.mkOption { type = lib.types.str; default = "30d"; };
    };

    grafana = {
      enable = lib.mkEnableOption "Grafana dashboard (porta 3001)";
      port = lib.mkOption { type = lib.types.port; default = 3001; };
    };

    loki = {
      enable = lib.mkEnableOption "Loki log aggregator (porta 3100)";
    };

    netdata = {
      enable = lib.mkEnableOption "Netdata realtime monitor (porta 19999)";
    };

    nodeExporter = {
      enable = lib.mkEnableOption "Prometheus node_exporter (CPU/RAM/disk metrics)";
    };
  };

  config = lib.mkMerge [
    # ── Prometheus ──
    (lib.mkIf cfg.prometheus.enable {
      services.prometheus = {
        enable = true;
        port = 9090;
        retentionTime = cfg.prometheus.retention;
        scrapeConfigs = [
          {
            job_name = "solem-api";
            static_configs = [{ targets = [ "127.0.0.1:8001" ]; }];
            metrics_path = "/solem/metrics";
          }
          (lib.mkIf cfg.nodeExporter.enable {
            job_name = "node";
            static_configs = [{ targets = [ "127.0.0.1:9100" ]; }];
          })
        ];
      };
    })

    # ── Grafana ──
    (lib.mkIf cfg.grafana.enable {
      services.grafana = {
        enable = true;
        settings = {
          server = {
            http_port = cfg.grafana.port;
            http_addr = "127.0.0.1";
            domain = "grafana.solem.local";
          };
          analytics.reporting_enabled = false;
          security.allow_embedding = true;
        };
        provision = {
          enable = true;
          datasources.settings.datasources = [
            (lib.mkIf cfg.prometheus.enable {
              name = "Prometheus";
              type = "prometheus";
              url = "http://127.0.0.1:9090";
              isDefault = true;
            })
            (lib.mkIf cfg.loki.enable {
              name = "Loki";
              type = "loki";
              url = "http://127.0.0.1:3100";
            })
          ];
        };
      };
    })

    # ── Loki ──
    (lib.mkIf cfg.loki.enable {
      services.loki = {
        enable = true;
        configuration = {
          server.http_listen_port = 3100;
          auth_enabled = false;
          common = {
            ring.instance_addr = "127.0.0.1";
            ring.kvstore.store = "inmemory";
            replication_factor = 1;
            path_prefix = "/var/lib/loki";
          };
          schema_config.configs = [{
            from = "2024-01-01";
            store = "tsdb";
            object_store = "filesystem";
            schema = "v13";
            index.prefix = "index_";
            index.period = "24h";
          }];
          storage_config.filesystem.directory = "/var/lib/loki/chunks";
        };
      };
    })

    # ── Netdata ──
    (lib.mkIf cfg.netdata.enable {
      services.netdata = {
        enable = true;
        config = {
          global = {
            "default port" = "19999";
            "bind to" = "127.0.0.1";
          };
        };
      };
    })

    # ── Node exporter ──
    (lib.mkIf cfg.nodeExporter.enable {
      services.prometheus.exporters.node = {
        enable = true;
        port = 9100;
        listenAddress = "127.0.0.1";
        enabledCollectors = [ "systemd" "processes" "filesystem" "cpu" "meminfo" "diskstats" ];
      };
    })
  ];
}
