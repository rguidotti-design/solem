{ config, pkgs, lib, ... }:

# SOLEM WIFI CAPTIVE — captive portal detect + auto-open browser.
#
# Single responsibility: SOLO CLI `solem-wifi-captive` che detecta captive
# portal (hotel/aeroporto Wi-Fi che richiede login) e apre il browser
# sulla URL di login.

let
  cfg = config.solem.wifiCaptive;

  captiveCli = pkgs.writeShellApplication {
    name = "solem-wifi-captive";
    runtimeInputs = with pkgs; [ coreutils curl xdg-utils ];
    text = ''
      ACTION="''${1:-detect}"

      case "$ACTION" in
        detect|check)
          # NCSI test (Microsoft) — risponde 'Microsoft NCSI' se internet libero
          NCSI=$(curl -s -m 3 "http://www.msftncsi.com/ncsi.txt" 2>/dev/null || echo "")
          if [ "$NCSI" = "Microsoft NCSI" ]; then
            echo "✓ Internet libero (no captive)"
          else
            # Captive detect: la richiesta a un URL noto ritorna redirect 302
            HEADERS=$(curl -sI -m 3 "http://detectportal.firefox.com/canonical.html" 2>/dev/null)
            if echo "$HEADERS" | grep -qi "Location:"; then
              PORTAL=$(echo "$HEADERS" | grep -i "Location:" | awk '{print $2}' | tr -d '\r')
              echo "⚠ Captive portal detected: $PORTAL"
              echo "$PORTAL"
            else
              echo "⚠ Possibile captive (no redirect) — controlla manualmente"
            fi
          fi
          ;;

        open)
          PORTAL=$(solem-wifi-captive detect | tail -1)
          if [ -n "$PORTAL" ] && [[ "$PORTAL" == http* ]]; then
            echo "Apro browser su: $PORTAL"
            xdg-open "$PORTAL"
          else
            echo "Nessun captive portal detected"
          fi
          ;;

        help|--help|-h|*)
          cat <<'HELP'
solem-wifi-captive — captive portal detect + open browser

  detect             verifica se sei dietro a captive portal
  open               se captive, apri browser sulla URL login

Uso tipico (hotel/aeroporto):
  1. Connetti Wi-Fi
  2. solem-wifi-captive open      → si apre browser su login portal
  3. Login → sei online

Detection via:
  - http://www.msftncsi.com/ncsi.txt (Microsoft NCSI standard)
  - http://detectportal.firefox.com/canonical.html (Firefox)

Tutto FOSS. 0 €.
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.wifiCaptive = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa `solem-wifi-captive` captive portal handler";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ captiveCli ];
  };
}
