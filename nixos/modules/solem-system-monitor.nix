{ config, pkgs, lib, ... }:

# SOLEM SYSTEM MONITOR — collezione tool monitoring (TUI + GUI).
#
# Single responsibility: SOLO install dei tool monitoring + accorpamento
# CLI `solem-mon`. Niente daemon dedicato (è in netdata/prometheus).
#
# Tool inclusi:
#   - btop      → CPU/RAM/disk/network/process colorato
#   - bandwhich → connessioni network top per processo
#   - dust      → disk usage tree (du moderno)
#   - duf       → df moderno
#   - bottom    → alternativa btop, Rust nativo
#   - lazygit   → git TUI
#   - lazydocker→ docker TUI
#   - gtop      → cross-platform system monitor (Node)

let
  cfg = config.solem.systemMonitor;

  monCli = pkgs.writeShellApplication {
    name = "solem-mon";
    runtimeInputs = with pkgs; [ btop bandwhich dust duf bottom ];
    text = ''
      ACTION="''${1:-overview}"
      case "$ACTION" in
        overview|now|top)
          btop
          ;;
        net|network)
          sudo bandwhich
          ;;
        disk|du)
          dust
          ;;
        fs|df)
          duf
          ;;
        gpu)
          if command -v nvtop >/dev/null 2>&1; then
            nvtop
          else
            echo "nvtop non installato"
          fi
          ;;
        all|bottom)
          btm
          ;;
        *)
          echo "solem-mon — system monitor"
          echo
          echo "  solem-mon overview    btop CPU/RAM/proc"
          echo "  solem-mon net         bandwidth per processo"
          echo "  solem-mon disk        du tree"
          echo "  solem-mon fs          df moderno"
          echo "  solem-mon gpu         nvtop (se installato)"
          echo "  solem-mon all         bottom (Rust alternative)"
          ;;
      esac
    '';
  };
in {
  options.solem.systemMonitor = {
    enable = lib.mkEnableOption "Tool monitoring TUI (btop, bandwhich, dust, duf)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      monCli btop bandwhich dust duf bottom
      iotop nethogs htop
      ncdu lazygit
    ];
  };
}
