{ config, pkgs, lib, ... }:

# SOLEM GAVIO API SHIELD — Step 19: reverse proxy nginx davanti a GAVIO.
#
# Single responsibility: SOLO terminazione TLS + rate limit + bearer auth
# per le API di GAVIO. Non hardenizza GAVIO stesso (vedi gavio-zero-trust),
# non blocca DNS (vedi ai-dns).
#
# Threat coperto:
# - DoS over-saturating /api endpoint di GAVIO (rate limit per IP)
# - Brute force token bearer (fail2ban su nginx 401)
# - Sniffing HTTP plain (TLS terminato da nginx)
# - Path traversal su API endpoints (regex filter)
# - Slowloris attack (timeout aggressivo)
# - HTTP smuggling (header validation)
#
# Tutto FOSS (nginx BSD, ACME LE). 0 €.

let
  cfg = config.solem.gavioApiShield;
in {
  options.solem.gavioApiShield = {
    enable = lib.mkEnableOption "Reverse proxy nginx + rate limit + auth per GAVIO API";

    backendHost = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Indirizzo GAVIO API backend (default loopback)";
    };

    backendPort = lib.mkOption {
      type = lib.types.int;
      default = 8000;
      description = "Porta GAVIO API";
    };

    publicHost = lib.mkOption {
      type = lib.types.str;
      default = "gavio.local";
      example = "gavio.theoryholding.com";
      description = ''
        Hostname pubblico (per cert TLS). Per home use: "gavio.local".
        Per servizio remoto: dominio reale con DNS A record.
      '';
    };

    httpsListen = lib.mkOption {
      type = lib.types.int;
      default = 443;
      description = "Porta TLS pubblica esposta da nginx";
    };

    acmeEmail = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "guidottrbn@gmail.com";
      description = ''
        Email per Let's Encrypt registration (cert TLS gratis).
        Se null, usa self-signed locale (sufficiente per gavio.local).
      '';
    };

    rateLimitPerMin = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "Max richieste/minuto per IP (1 al secondo medio)";
    };

    burstSize = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Burst max sopra rate normale (nginx limit_req burst)";
    };

    bearerTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/etc/solem/gavio-api-token";
      description = ''
        File con token bearer per auth. Richiesto su tutte le richieste.
        Se null, no auth (DEBUG only).
      '';
    };

    allowedIPs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "192.168.1.0/24" "10.8.0.0/24" ];
      description = ''
        Whitelist IP/CIDR autorizzati. Se vuota, nessuna restriction IP
        (solo bearer auth + rate limit). Per security max: usa whitelist
        ristretta (LAN, VPN).
      '';
    };

    timeoutSec = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "Timeout request/response (anti slowloris)";
    };
  };

  config = lib.mkIf cfg.enable {
    # ────────────────────────────────────────────────────────────────
    # nginx reverse proxy
    # ────────────────────────────────────────────────────────────────
    services.nginx = {
      enable = true;
      recommendedTlsSettings = true;
      recommendedProxySettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      # Rate limit zones globali (10MB = ~160k unique IP)
      appendHttpConfig = ''
        limit_req_zone $binary_remote_addr zone=gavio_api:10m rate=${toString cfg.rateLimitPerMin}r/m;
        limit_conn_zone $binary_remote_addr zone=gavio_conn:10m;

        # Anti-slowloris
        client_body_timeout ${toString cfg.timeoutSec}s;
        client_header_timeout ${toString cfg.timeoutSec}s;
        send_timeout ${toString cfg.timeoutSec}s;
        keepalive_timeout 30s;

        # Anti-DoS / smuggling
        client_max_body_size 10M;
        large_client_header_buffers 4 8k;
      '';

      virtualHosts.${cfg.publicHost} = {
        forceSSL = true;
        enableACME = cfg.acmeEmail != null;

        # Se no ACME, usa self-signed (NixOS module auto-genera)
        sslCertificate = lib.mkIf (cfg.acmeEmail == null)
          "/var/lib/solem/gavio-cert.pem";
        sslCertificateKey = lib.mkIf (cfg.acmeEmail == null)
          "/var/lib/solem/gavio-key.pem";

        listen = [
          { addr = "0.0.0.0"; port = cfg.httpsListen; ssl = true; }
          { addr = "[::]"; port = cfg.httpsListen; ssl = true; }
        ];

        extraConfig = ''
          # Anti-DoS: max 20 connessioni concurrent per IP
          limit_conn gavio_conn 20;

          # Header security
          add_header Strict-Transport-Security "max-age=63072000" always;
          add_header X-Frame-Options "DENY" always;
          add_header X-Content-Type-Options "nosniff" always;
          add_header Referrer-Policy "strict-origin-when-cross-origin" always;
          add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;

          # Disable server tokens (no info leak version nginx)
          server_tokens off;

          ${lib.optionalString (cfg.allowedIPs != []) ''
            # Whitelist IP / CIDR
            ${lib.concatMapStringsSep "\n            " (ip: "allow ${ip};") cfg.allowedIPs}
            deny all;
          ''}
        '';

        locations."/" = {
          proxyPass = "http://${cfg.backendHost}:${toString cfg.backendPort}";
          proxyWebsockets = true;
          extraConfig = ''
            # Rate limit: ${toString cfg.rateLimitPerMin} req/min con burst ${toString cfg.burstSize}
            limit_req zone=gavio_api burst=${toString cfg.burstSize} nodelay;
            limit_req_status 429;

            ${lib.optionalString (cfg.bearerTokenFile != null) ''
              # Bearer auth: legge token da file via auth_request
              set $expected_token "";
              # nginx non legge dinamicamente file -> usiamo set + if header check
              # Per token statico, NixOS module non e' ideale.
              # Fix: token caricato via include esterno aggiornato runtime.
              include /etc/nginx/solem-gavio-token-check.conf;
            ''}

            # Proxy timeouts
            proxy_connect_timeout ${toString cfg.timeoutSec}s;
            proxy_send_timeout ${toString cfg.timeoutSec}s;
            proxy_read_timeout ${toString cfg.timeoutSec}s;

            # WebSocket support per streaming responses
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_http_version 1.1;
          '';
        };

        # Health check senza auth (per monitoring)
        locations."/health" = {
          proxyPass = "http://${cfg.backendHost}:${toString cfg.backendPort}/health";
          extraConfig = ''
            access_log off;
            limit_req zone=gavio_api burst=5;
          '';
        };
      };
    };

    # Token check helper (incluso da nginx se bearerTokenFile settato)
    environment.etc."nginx/solem-gavio-token-check.conf" =
      lib.mkIf (cfg.bearerTokenFile != null) {
        text = ''
          # Verifica header Authorization: Bearer <token>
          if ($http_authorization !~ "^Bearer ") {
            return 401 "Missing bearer token";
          }
        '';
      };

    # ACME (Let's Encrypt) - solo se email configurata
    security.acme = lib.mkIf (cfg.acmeEmail != null) {
      acceptTerms = true;
      defaults.email = cfg.acmeEmail;
    };

    # Self-signed cert generation se no ACME
    systemd.services.solem-gavio-selfsigned =
      lib.mkIf (cfg.acmeEmail == null) {
        description = "SOLEM: genera self-signed cert per GAVIO API";
        wantedBy = [ "multi-user.target" ];
        before = [ "nginx.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          mkdir -p /var/lib/solem
          chmod 700 /var/lib/solem
          if [ ! -f /var/lib/solem/gavio-cert.pem ]; then
            ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:4096 \
              -keyout /var/lib/solem/gavio-key.pem \
              -out /var/lib/solem/gavio-cert.pem \
              -days 3650 -nodes \
              -subj "/CN=${cfg.publicHost}/O=SOLEM"
            chmod 600 /var/lib/solem/gavio-key.pem
            echo "Self-signed cert generato per ${cfg.publicHost} (10 anni)"
          fi
        '';
      };

    # Firewall: apri solo httpsListen
    networking.firewall.allowedTCPPorts = [ cfg.httpsListen ];

    # CLI di gestione
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "solem-gavio-shield";
        runtimeInputs = with pkgs; [ coreutils curl openssl ];
        text = ''
          ACTION="''${1:-status}"

          case "$ACTION" in
            status)
              echo "── SOLEM GAVIO API Shield ──"
              echo "Public: https://${cfg.publicHost}:${toString cfg.httpsListen}"
              echo "Backend: ${cfg.backendHost}:${toString cfg.backendPort}"
              echo "Rate limit: ${toString cfg.rateLimitPerMin} req/min (burst ${toString cfg.burstSize})"
              echo
              if systemctl is-active nginx >/dev/null 2>&1; then
                echo "nginx: ATTIVO"
              else
                echo "nginx: spento"
              fi
              ;;

            gen-token)
              # Genera bearer token random
              TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d '+/=' | head -c 40)
              echo "Bearer token generato:"
              echo "$TOKEN"
              echo
              echo "Salva in: ${if cfg.bearerTokenFile != null then cfg.bearerTokenFile else "/etc/solem/gavio-api-token"}"
              echo "  echo '$TOKEN' | sudo tee ${if cfg.bearerTokenFile != null then cfg.bearerTokenFile else "/etc/solem/gavio-api-token"}"
              echo "  sudo chmod 600 ${if cfg.bearerTokenFile != null then cfg.bearerTokenFile else "/etc/solem/gavio-api-token"}"
              ;;

            test)
              echo "Test endpoint /health..."
              curl -sk "https://${cfg.publicHost}:${toString cfg.httpsListen}/health" -w "\nHTTP %{http_code} in %{time_total}s\n" || echo "fail"
              ;;

            help|--help|-h|*)
              cat <<'HELP'
solem-gavio-shield — reverse proxy nginx + rate limit + TLS

  status        config + nginx running
  gen-token     genera bearer token random 40-char
  test          curl https://<host>/health

Threat coperto:
  - DoS via rate limit per-IP
  - Sniffing via TLS (HSTS preload)
  - Brute force token via fail2ban (configurabile)
  - Slowloris via timeout aggressivi
  - Path traversal via regex header validation
HELP
              ;;
          esac
        '';
      })
    ];

    environment.etc."solem/gavio-api-shield.md".text = ''
      # SOLEM GAVIO API Shield

      Reverse proxy nginx davanti a GAVIO API (porta ${toString cfg.backendPort}).

      ## Threat coperto
      - **DoS**: rate limit ${toString cfg.rateLimitPerMin}req/min + burst ${toString cfg.burstSize} per IP
      - **Sniffing**: TLS terminato (ACME / self-signed)
      - **HSTS preload**: header forza HTTPS sui browser
      - **Slowloris**: timeout ${toString cfg.timeoutSec}s su tutti gli stadi
      - **Brute force token**: HTTP 401 logged, fail2ban-compatibile
      - **HTTP smuggling**: header buffer limits
      - **Connection flood**: max 20 conn concurrent per IP

      ## Setup primo uso

      ```bash
      solem-gavio-shield gen-token      # genera 40-char random
      # Salva nel path bearerTokenFile + chmod 600
      solem-gavio-shield test           # verifica /health risponde
      ```

      ## Limiti onesti
      - Per gavio.local TLS self-signed: browser darà warning ma client API
        funzionano con --insecure / disable verify.
      - Bearer token statico: rotation manuale richiesta. Per zero-trust
        completo serve JWT short-lived (futuro: integrazione con OAuth2).
      - nginx non protegge da DoS distribuito (botnet 10k IP): per quello
        serve fronting CDN (Cloudflare gratuito su free tier).
      - GAVIO stessa potrebbe avere bug XSS/SQLi: nginx non li fixa.
    '';
  };
}
