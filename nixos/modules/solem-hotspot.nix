{ config, pkgs, lib, ... }:

# SOLEM HOTSPOT — CLI per condividere la connessione WiFi.
#
# Single responsibility: SOLO wrapper su `nmcli device wifi hotspot` con
# parametri sensati (WPA2-PSK, SSID branded, password generata).
#
# Uso:
#   solem-hotspot start             → SSID solem-<host>, password random
#   solem-hotspot start --pass=foo  → custom password
#   solem-hotspot stop
#   solem-hotspot status

let
  cfg = config.solem.hotspot;

  hotspotCli = pkgs.writeShellApplication {
    name = "solem-hotspot";
    runtimeInputs = with pkgs; [ networkmanager coreutils qrencode ];
    text = ''
      HOSTNAME=$(hostname)
      DEFAULT_SSID="solem-$HOSTNAME"
      DEFAULT_PASS=""

      action="''${1:-status}"
      shift || true
      for arg in "$@"; do
        case "$arg" in
          --ssid=*) DEFAULT_SSID="''${arg#--ssid=}" ;;
          --pass=*) DEFAULT_PASS="''${arg#--pass=}" ;;
        esac
      done

      case "$action" in
        start)
          # Genera password se non passata
          if [ -z "$DEFAULT_PASS" ]; then
            DEFAULT_PASS=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
          fi
          echo "Avvio hotspot..."
          sudo nmcli device wifi hotspot \
            ssid "$DEFAULT_SSID" \
            password "$DEFAULT_PASS" 2>&1 || {
              echo "ERRORE: probabilmente serve un'interfaccia wifi disponibile"
              exit 1
            }
          echo
          echo "  SSID:     $DEFAULT_SSID"
          echo "  Password: $DEFAULT_PASS"
          echo
          # QR code per scansione smartphone
          qrencode -t ANSI256UTF8 "WIFI:T:WPA;S:$DEFAULT_SSID;P:$DEFAULT_PASS;;"
          ;;
        stop)
          sudo nmcli connection down Hotspot 2>/dev/null || true
          echo "Hotspot stopped"
          ;;
        status|show)
          nmcli connection show --active | grep -E "^Hotspot|wifi" || echo "Nessun hotspot attivo"
          ;;
        *)
          echo "solem-hotspot — condividi WiFi"
          echo
          echo "  solem-hotspot start [--ssid=X] [--pass=Y]    avvia con QR code"
          echo "  solem-hotspot stop                            ferma"
          echo "  solem-hotspot status                          stato"
          ;;
      esac
    '';
  };
in {
  options.solem.hotspot = {
    enable = lib.mkEnableOption "WiFi hotspot CLI (solem-hotspot)";
  };

  config = lib.mkIf cfg.enable {
    networking.networkmanager.enable = true;
    environment.systemPackages = [ hotspotCli pkgs.qrencode ];
  };
}
