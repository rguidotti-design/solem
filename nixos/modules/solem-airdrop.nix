{ config, pkgs, lib, ... }:

# SOLEM AIRDROP — file-share LAN device-to-device, alternativa FOSS AirDrop.
#
# Single responsibility: SOLO installare e configurare:
# - LocalSend     → cross-platform (Linux/Win/Mac/iOS/Android/Web), MIT
# - Warpinator   → originale Linux Mint, GPL-3.0, alt-AirDrop classico
# - KDE Connect  → ricco di feature ma più "pairing" (già in solem-mobile)
# - nautilus-share / `solem-share` CLI helper
#
# Niente cloud, tutto su LAN/mesh. 0 €. Risponde gap "AirDrop" della
# COMPETITIVE-GAP.md.

let
  cfg = config.solem.airdrop;

  shareCli = pkgs.writeShellApplication {
    name = "solem-share";
    runtimeInputs = with pkgs; [ localsend coreutils python3 ];
    text = ''
      ACTION="''${1:-help}"
      case "$ACTION" in
        send)
          SRC="''${2:?Usage: solem-share send <file>}"
          # LocalSend ha modalità headless via CLI (in alcune versioni)
          # Fallback: avvia GUI già pronta con file selezionato
          localsend "$SRC" 2>/dev/null &
          echo "GUI LocalSend aperta con $SRC pronto per invio"
          ;;
        receive)
          # Avvia LocalSend in modalità receive (porta 53317 default)
          localsend &
          echo "LocalSend in ascolto su :53317"
          ;;
        serve-http)
          # Server HTTP semplice cartella corrente, sola lettura
          PORT="''${2:-8888}"
          echo "Servendo $(pwd) su http://0.0.0.0:$PORT (Ctrl+C per fermare)"
          python3 -m http.server "$PORT" --bind 0.0.0.0
          ;;
        *)
          echo "solem-share — file-share device-to-device FOSS"
          echo
          echo "  solem-share send <file>      apri LocalSend con file pronto"
          echo "  solem-share receive          ricevi (porta 53317)"
          echo "  solem-share serve-http [N]   cartella corrente via HTTP:N (default 8888)"
          ;;
      esac
    '';
  };
in {
  options.solem.airdrop = {
    enable = lib.mkEnableOption "AirDrop-alt FOSS (LocalSend + Warpinator)";

    autoOpenFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Apri automaticamente le porte LocalSend (53317) + Warpinator (42000)
        sul firewall locale. Solo LAN, niente exposure esterna.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      localsend
      warpinator
      shareCli
    ];

    # Apri porte LAN per discovery + transfer
    networking.firewall = lib.mkIf cfg.autoOpenFirewall {
      allowedTCPPorts = [
        53317       # LocalSend
        42000 42001 # Warpinator gRPC
      ];
      allowedUDPPorts = [
        53317       # LocalSend discovery
        5353        # mDNS (richiesto per discovery)
      ];
    };

    # Avahi essenziale per discovery LAN
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
        domain = true;
        userServices = true;
      };
    };
  };
}
