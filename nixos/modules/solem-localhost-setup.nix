{ config, pkgs, lib, ... }:

# SOLEM LOCALHOST SETUP — Step 53: tutto-in-locale + URL/comandi.
#
# Single responsibility: SOLO un comando `solem-localhost` che:
#   - Lista TUTTI gli endpoint locali disponibili (web HUD, PWA, Grafana,
#     Prometheus, Loki, GAVIO API, prompt filter)
#   - Mostra stato per ogni endpoint
#   - Apre in browser quelli pingabili
#   - One-shot setup: abilita web HUD + start service se non già attivo

let
  cfg = config.solem.localhostSetup;
in {
  options.solem.localhostSetup = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa solem-localhost CLI (tutto-in-locale dashboard)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      (pkgs.writeShellApplication {
        name = "solem-localhost";
        runtimeInputs = with pkgs; [ coreutils curl xdg-utils systemd ];
        text = ''
          ACTION="''${1:-list}"

          # Endpoint table (name | url | service-unit | description)
          ENDPOINTS=$(cat <<'EOF'
web-hud         | http://127.0.0.1:8088          | solem-dashboard.service     | Friday HUD navy/gold (Step 36)
pwa             | http://127.0.0.1:8089          | nginx.service               | Mobile companion PWA (Step 47)
grafana         | http://127.0.0.1:3001          | grafana.service             | Monitoring dashboards (Step 33)
prometheus      | http://127.0.0.1:9090          | prometheus.service          | Metrics TSDB
loki            | http://127.0.0.1:3100          | loki.service                | Logs aggregator
gavio-api       | http://127.0.0.1:8000          | gavio.service               | GAVIO backend AI (Step 30/51)
prompt-filter   | http://127.0.0.1:8001          | solem-prompt-filter.service | Anti injection (Step 21)
api-shield      | https://gavio.local            | nginx.service               | TLS reverse proxy (Step 19)
ollama          | http://127.0.0.1:11434         | ollama.service              | LLM runtime
unbound-dns     | 127.0.0.1:5353                 | unbound.service             | DNS allowlist (Step 7)
wg-mesh         | 10.100.0.1:51820 (UDP)         | wg-quick-wg-solem.service   | WireGuard server (Step 24)
tor-onion       | (.onion address)               | tor.service                 | Hidden service (Step 29)
EOF
)

          case "$ACTION" in
            list|ls)
              echo "╔════════════════════════════════════════════════════════════════════════╗"
              echo "║                  SOLEM — Tutto-in-locale Dashboard                     ║"
              echo "╚════════════════════════════════════════════════════════════════════════╝"
              echo
              printf "%-16s %-30s %s\n" "NAME" "URL" "STATUS"
              echo "────────────────────────────────────────────────────────────────────────"
              echo "$ENDPOINTS" | while IFS='|' read -r NAME URL SVC DESC; do
                NAME=$(echo "$NAME" | xargs)
                URL=$(echo "$URL" | xargs)
                SVC=$(echo "$SVC" | xargs)
                if systemctl is-active "$SVC" >/dev/null 2>&1; then
                  STAT="✓ active"
                else
                  STAT="○ inactive"
                fi
                printf "%-16s %-30s %s\n" "$NAME" "$URL" "$STAT"
              done
              echo
              echo "Comandi:"
              echo "  solem-localhost open <name>      apre URL nel browser"
              echo "  solem-localhost ping             ping HTTP a tutti gli endpoint"
              echo "  solem-localhost enable-essentials abilita web-hud + nginx (rapid setup)"
              echo "  solem-localhost help             help completo"
              ;;

            open|browse)
              NAME="''${1:?Usage: solem-localhost open <name>}"
              URL=$(echo "$ENDPOINTS" | grep "^$NAME " | awk -F'|' '{print $2}' | xargs)
              if [ -z "$URL" ]; then
                echo "Endpoint '$NAME' non trovato. Lista: solem-localhost list"
                exit 1
              fi
              echo "Apro $URL ..."
              xdg-open "$URL" 2>/dev/null || echo "Visita manualmente: $URL"
              ;;

            ping)
              echo "── Ping HTTP endpoints (timeout 2s) ──"
              echo "$ENDPOINTS" | while IFS='|' read -r NAME URL SVC DESC; do
                NAME=$(echo "$NAME" | xargs)
                URL=$(echo "$URL" | xargs)
                # Solo URL HTTP/HTTPS
                if [[ "$URL" =~ ^https?:// ]]; then
                  CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 2 "$URL" 2>/dev/null || echo "---")
                  printf "  %-16s %-30s HTTP %s\n" "$NAME" "$URL" "$CODE"
                else
                  printf "  %-16s %-30s (non-HTTP)\n" "$NAME" "$URL"
                fi
              done
              ;;

            enable-essentials)
              echo "── Setup rapid SOLEM localhost ──"
              echo "Questo comando STAMPA gli step da aggiungere a configuration.nix:"
              echo
              cat <<'NIX'
# Aggiungi a configuration.nix o flake.nix module:

solem = {
  webDashboard.enable = true;       # http://127.0.0.1:8088
  unifiedCli.enable = true;          # comando `solem`
  demoWalkthrough.enable = true;     # comando `solem-demo`
  pwaCompanion.enable = true;        # http://127.0.0.1:8089
  localhostSetup.enable = true;      # questo CLI

  # Security loop autonomo
  selfRedteam.enable = true;
  selfHeal.enable = true;

  # Backup + update
  autoUpdate.enable = true;
};

# Poi:
#   sudo nixos-rebuild switch
#   solem-localhost ping
#   xdg-open http://127.0.0.1:8088
NIX
              ;;

            status|st)
              echo "── SOLEM Service Status (riepilogo) ──"
              for SVC in solem-dashboard nginx grafana prometheus loki gavio \
                         solem-prompt-filter ollama unbound tor \
                         wg-quick-wg-solem fail2ban suricata usbguard \
                         solem-canary-watcher solem-self-redteam.timer; do
                if systemctl is-active "$SVC" >/dev/null 2>&1; then
                  printf "  ✓ %s\n" "$SVC"
                elif systemctl list-unit-files --no-pager 2>/dev/null | grep -q "^$SVC"; then
                  printf "  ○ %s (inactive)\n" "$SVC"
                fi
              done
              ;;

            urls)
              # Output machine-readable: solo URL HTTP
              echo "$ENDPOINTS" | while IFS='|' read -r NAME URL SVC DESC; do
                URL=$(echo "$URL" | xargs)
                if [[ "$URL" =~ ^https?:// ]]; then
                  echo "$URL"
                fi
              done
              ;;

            help|--help|-h|*)
              cat <<'HELP'
solem-localhost — tutto-in-locale dashboard

  list / ls                  endpoint + active/inactive
  open <name>                apre URL nel browser
  ping                       HTTP ping a tutti gli endpoint
  status / st                riepilogo service systemd attivi
  urls                       lista URL HTTP (machine-readable)
  enable-essentials          stampa snippet config Nix per rapid setup

Endpoint disponibili:
  web-hud        http://127.0.0.1:8088    Friday HUD browser
  pwa            http://127.0.0.1:8089    Mobile companion
  grafana        http://127.0.0.1:3001    Monitoring dashboards
  prometheus     http://127.0.0.1:9090    Metrics TSDB
  loki           http://127.0.0.1:3100    Logs aggregator
  gavio-api      http://127.0.0.1:8000    GAVIO AI backend
  prompt-filter  http://127.0.0.1:8001    Anti prompt injection
  api-shield     https://gavio.local      TLS reverse proxy
  ollama         http://127.0.0.1:11434   LLM runtime
  unbound-dns    127.0.0.1:5353           DNS allowlist
  wg-mesh        10.100.0.1:51820         WireGuard server
  tor-onion      (.onion via solem-tor)   Hidden service

Esempio:
  solem-localhost                    # lista tutto
  solem-localhost open web-hud       # apre Firefox su HUD
  solem-localhost ping               # test connectivity
HELP
              ;;
          esac
        '';
      })
    ];

    environment.etc."solem/localhost-setup.md".text = ''
      # SOLEM Localhost Setup (Step 53)

      Comando unico per **vedere TUTTO localmente**.

      ## Quick start

      ```bash
      solem-localhost                    # cosa gira sulla mia macchina?
      solem-localhost ping               # test HTTP
      solem-localhost open web-hud       # apri Friday HUD nel browser
      solem-localhost status             # systemd units SOLEM
      ```

      ## Endpoint mappati

      | Name | URL | Modulo |
      |------|-----|--------|
      | web-hud | http://127.0.0.1:8088 | Step 36 dashboard |
      | pwa | http://127.0.0.1:8089 | Step 47 PWA mobile |
      | grafana | http://127.0.0.1:3001 | Step 33 monitoring |
      | prometheus | http://127.0.0.1:9090 | Step 33 metrics |
      | loki | http://127.0.0.1:3100 | Step 33 logs |
      | gavio-api | http://127.0.0.1:8000 | Step 30/51 GAVIO |
      | prompt-filter | http://127.0.0.1:8001 | Step 21 anti-injection |
      | api-shield | https://gavio.local | Step 19 TLS proxy |
      | ollama | http://127.0.0.1:11434 | LLM runtime |
      | unbound-dns | 127.0.0.1:5353 | Step 7 DNS allowlist |
      | wg-mesh | 10.100.0.1:51820 | Step 24 WireGuard |
      | tor-onion | (.onion) | Step 29 hidden service |

      ## Rapid setup
      ```bash
      solem-localhost enable-essentials   # stampa snippet config
      # Copia in configuration.nix
      sudo nixos-rebuild switch
      solem-localhost ping                # verifica
      ```
    '';
  };
}
