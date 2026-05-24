{ config, pkgs, lib, ... }:

# SOLEM NET MONITOR — speed/bandwidth/latency live in CLI.
#
# Single responsibility: SOLO CLI `solem-net` con sub-comandi per:
#   - speed: speedtest (FOSS librespeed-cli o vendor speedtest-cli)
#   - bandwidth: live bandwidth per interfaccia (bandwhich)
#   - latency: ping continuo
#   - dns: query DNS time
#   - public-ip: tuo IP esterno

let
  cfg = config.solem.netMonitor;

  netCli = pkgs.writeShellApplication {
    name = "solem-net";
    runtimeInputs = with pkgs; [ coreutils curl iputils iproute2 bandwhich speedtest-rs dig ];
    text = ''
      ACTION="''${1:-help}"
      shift || true

      case "$ACTION" in
        speed|speedtest)
          # speedtest-rs è Rust FOSS, alternativa a speedtest-cli closed
          speedtest-rs
          ;;

        bandwidth|bw|live)
          # bandwhich per traffico live per processo
          sudo bandwhich
          ;;

        latency|ping)
          HOST="''${1:-8.8.8.8}"
          ping -c 10 "$HOST"
          ;;

        dns)
          HOST="''${1:-github.com}"
          dnsutils  # include dig +stats "$HOST" | grep -E "Query time|SERVER"
          ;;

        public-ip|myip)
          echo "Public IP: $(curl -s https://api.ipify.org)"
          echo "Geo info:"
          curl -s "https://ipapi.co/json/" | grep -E '"city"|"country"|"org"|"asn"' | head -5
          ;;

        interfaces|if)
          ip -brief addr show
          ;;

        routes)
          ip route show
          ;;

        connections|conn)
          ss -tunap 2>/dev/null | head -30
          ;;

        wifi-list|wifi)
          if command -v nmcli >/dev/null 2>&1; then
            nmcli device wifi list
          else
            echo "NetworkManager non disponibile"
          fi
          ;;

        wifi-signal)
          if command -v nmcli >/dev/null 2>&1; then
            nmcli -t -f IN-USE,SIGNAL,SSID device wifi | grep "^\*"
          fi
          ;;

        help|--help|-h|*)
          cat <<'HELP'
solem-net — network monitoring CLI (tutto FOSS)

  speed                speedtest-rs (Rust FOSS)
  bandwidth            traffico live per processo (bandwhich, sudo)
  latency [host]       ping (default 8.8.8.8)
  dns [host]           tempo risoluzione DNS (default github.com)
  public-ip            tuo IP + geolocation
  interfaces           lista interfacce + IP
  routes               routing table
  connections          connessioni TCP/UDP attive
  wifi-list            lista reti Wi-Fi visibili
  wifi-signal          forza segnale rete corrente

Tutti FOSS. 0 €.
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.netMonitor = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa `solem-net` monitoring CLI";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      netCli
      bandwhich
      speedtest-rs
      dnsutils  # include dig
    ];
  };
}
