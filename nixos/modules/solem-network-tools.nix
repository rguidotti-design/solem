{ config, pkgs, lib, ... }:

# SOLEM NETWORK TOOLS — WiFi analyzer + speed test + diagnostica.
#
# Single responsibility: SOLO installazione tool diagnostici + CLI
# `solem-net` con sub-comando user-friendly.

let
  cfg = config.solem.networkTools;

  netCli = pkgs.writeShellApplication {
    name = "solem-net";
    runtimeInputs = with pkgs; [ iw iputils iproute2 mtr speedtest-cli dig ];
    text = ''
      ACTION="''${1:-status}"
      case "$ACTION" in
        status|now)
          echo "── Interfaces ──"
          ip -brief addr show
          echo
          echo "── Default route ──"
          ip route show default
          ;;
        wifi|scan)
          IFACE="''${2:-$(${pkgs.iw}/bin/iw dev | awk '/Interface/{print $2; exit}')}"
          if [ -z "$IFACE" ]; then
            echo "Nessuna interfaccia WiFi"
            exit 1
          fi
          echo "Scan WiFi su $IFACE..."
          sudo iw dev "$IFACE" scan | awk -v RS="BSS " '
            NR > 1 {
              bssid = $1
              ssid = ""; signal = ""; freq = ""
              for (i = 1; i <= NF; i++) {
                if ($i == "SSID:") ssid = $(i+1)
                if ($i == "signal:") signal = $(i+1)
                if ($i == "freq:") freq = $(i+1)
              }
              printf "  %-30s  %s dBm  freq %s MHz\n", ssid, signal, freq
            }
          ' | sort -u | head -20
          ;;
        speedtest|speed)
          speedtest-cli --simple
          ;;
        ping)
          TARGET="''${2:-1.1.1.1}"
          ping -c 5 "$TARGET"
          ;;
        trace|mtr)
          TARGET="''${2:-1.1.1.1}"
          mtr -r -c 10 "$TARGET"
          ;;
        dns)
          DOMAIN="''${2:-cloudflare.com}"
          echo "── A record ──"
          dig +short A "$DOMAIN"
          echo "── AAAA record ──"
          dig +short AAAA "$DOMAIN"
          echo "── Resolver in use ──"
          dig +short "$DOMAIN" | head -1
          ;;
        leak|dns-leak)
          echo "DNS leak test (verifica che il tuo DNS sia quello attesa)..."
          dig +short @resolver1.opendns.com myip.opendns.com
          ;;
        *)
          echo "solem-net — diagnostica rete"
          echo
          echo "  solem-net status         interfacce + route"
          echo "  solem-net wifi           scan WiFi nearby"
          echo "  solem-net speed          speedtest"
          echo "  solem-net ping [host]    ping (default 1.1.1.1)"
          echo "  solem-net trace [host]   mtr trace"
          echo "  solem-net dns [domain]   resolve A/AAAA"
          echo "  solem-net leak           test DNS leak"
          ;;
      esac
    '';
  };
in {
  options.solem.networkTools = {
    enable = lib.mkEnableOption "Network diagnostics CLI (solem-net)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      netCli
      iw iputils iproute2 mtr speedtest-cli dnsutils
      tcpdump nmap iperf3 ethtool
      whois traceroute
    ];
  };
}
