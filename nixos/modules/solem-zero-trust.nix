{ config, pkgs, lib, ... }:

let
  cfg = config.solem.zeroTrust;
in {
  # ──────────────────────────────────────────────────────────────────────
  # SOLEM ZERO-TRUST — proxy mTLS davanti a GAVIO + SOLEM API
  # ──────────────────────────────────────────────────────────────────────
  # Principio: nessuna rete è fidata. Anche la mesh interna (10.42.0.0/24)
  # è trattata come pubblica. Ogni richiesta API deve:
  #   1. Provenire da un client con certificato firmato dalla CA SOLEM
  #   2. Avere un token di sessione valido (short-lived, max 15 min)
  #   3. Passare policy check (chi-può-fare-cosa)
  #   4. Essere loggata in audit jsonl
  #
  # Architettura:
  #   client → mTLS → Caddy (:8443) → reverse_proxy → backend (:8000/:8001)
  #                       │
  #                       ├─ CA interna: /var/lib/solem-ca/ca.crt
  #                       ├─ Server cert: /var/lib/solem-ca/server.crt
  #                       └─ Client certs: rilasciati via pairing API
  #
  # Step 0: option disabled. Quando si attiva, bootstrap CA al primo boot.

  options.solem.zeroTrust = {
    enable = lib.mkEnableOption "Zero-Trust mTLS proxy davanti a SOLEM/GAVIO";

    caDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/solem-ca";
      description = "Directory CA interna (mai esposta su rete).";
    };

    hostname = lib.mkOption {
      type = lib.types.str;
      default = "solem.local";
      description = "Hostname per cert server (CommonName).";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8443;
      description = "Porta HTTPS mTLS esposta.";
    };

    upstreams = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        gavio = "http://127.0.0.1:8000";
        solem = "http://127.0.0.1:8001";
      };
      description = ''
        Mappa nome → upstream. Esposti come /api/<nome>/...
        Es: /api/gavio/health → 127.0.0.1:8000/health
      '';
    };

    auditLogPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/log/solem/audit.jsonl";
      description = "File audit log strutturato jsonl.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Bootstrap CA interna al primo boot
    systemd.services.solem-ca-bootstrap = {
      description = "Bootstrap CA interna per zero-trust SOLEM";
      wantedBy = [ "multi-user.target" ];
      before = [ "caddy.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail
        CA_DIR="${cfg.caDir}"
        mkdir -p "$CA_DIR"
        chmod 700 "$CA_DIR"
        cd "$CA_DIR"

        OSSL="${pkgs.openssl}/bin/openssl"

        # CA root (RSA 4096, valid 10 anni). Generata UNA volta.
        if [ ! -f ca.key ]; then
          umask 077
          $OSSL genrsa -out ca.key 4096
          $OSSL req -x509 -new -nodes -key ca.key -sha256 -days 3650 \
            -subj "/CN=SOLEM Internal CA/O=SOLEM" \
            -out ca.crt
          chmod 600 ca.key
          chmod 644 ca.crt
        fi

        # Cert server (per Caddy). Rinnovo automatico se vicino a scadenza.
        if [ ! -f server.crt ] || ! $OSSL x509 -in server.crt -noout -checkend $((86400*30)); then
          umask 077
          $OSSL genrsa -out server.key 2048
          $OSSL req -new -key server.key \
            -subj "/CN=${cfg.hostname}/O=SOLEM" \
            -out server.csr
          cat > server.ext <<EOF
        subjectAltName = DNS:${cfg.hostname}, DNS:localhost, IP:127.0.0.1, IP:10.42.0.1
        EOF
          $OSSL x509 -req -in server.csr -CA ca.crt -CAkey ca.key \
            -CAcreateserial -out server.crt -days 365 -sha256 \
            -extfile server.ext
          chmod 600 server.key
          chmod 644 server.crt
          rm -f server.csr server.ext
        fi

        # Permessi: caddy può leggere server.crt + server.key, NON ca.key
        chown -R root:root "$CA_DIR"
        chgrp caddy "$CA_DIR/server.key" "$CA_DIR/server.crt" "$CA_DIR/ca.crt"
        chmod 640 "$CA_DIR/server.key" "$CA_DIR/server.crt" "$CA_DIR/ca.crt"
      '';
    };

    # Caddy come reverse proxy mTLS
    services.caddy = {
      enable = true;
      virtualHosts."${cfg.hostname}:${toString cfg.port}" = {
        extraConfig = ''
          tls ${cfg.caDir}/server.crt ${cfg.caDir}/server.key {
            client_auth {
              mode require_and_verify
              trust_pool file {
                pem_file ${cfg.caDir}/ca.crt
              }
            }
          }

          log {
            output file ${cfg.auditLogPath} {
              roll_size 100mb
              roll_keep 10
            }
            format json
          }

          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: upstream: ''
            handle_path /api/${name}/* {
              reverse_proxy ${upstream}
            }
          '') cfg.upstreams)}

          handle {
            respond "SOLEM Zero-Trust gateway" 200
          }
        '';
      };
    };

    # Apri porta HTTPS mTLS
    networking.firewall.allowedTCPPorts = [ cfg.port ];

    # Directory log audit
    systemd.tmpfiles.rules = [
      "d /var/log/solem 0750 caddy caddy -"
    ];

    # Pacchetti utili per gestione CA (ispezione cert, rinnovo manuale)
    environment.systemPackages = with pkgs; [ openssl ];
  };
}
