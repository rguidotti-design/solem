{ config, pkgs, lib, ... }:

# SOLEM MULTI-MONITOR — auto-profile multi-display Wayland.
#
# Single responsibility: SOLO orchestrare kanshi + wlr-randr + wdisplays
# per cambio profilo automatico (laptop chiuso → monitor esterno, dock
# attached → 3 schermi, etc).
#
# Tutto FOSS, 0 €. Risponde gap "Multi-monitor + HiDPI" COMPETITIVE-GAP.md.

let
  cfg = config.solem.multiMonitor;

  monCli = pkgs.writeShellApplication {
    name = "solem-monitor";
    runtimeInputs = with pkgs; [ wlr-randr coreutils ];
    text = ''
      ACTION="''${1:-list}"
      case "$ACTION" in
        list)
          echo "── Monitor connessi ──"
          wlr-randr
          ;;
        save-profile)
          NAME="''${2:?Usage: solem-monitor save-profile <name>}"
          DIR="$HOME/.config/kanshi"
          mkdir -p "$DIR"
          # Genera profilo kanshi dall'attuale stato
          FILE="$DIR/$NAME.conf"
          echo "profile $NAME {" > "$FILE"
          wlr-randr | grep -E "^\S" | while read -r line; do
            OUT=$(echo "$line" | awk '{print $1}')
            echo "  output $OUT enable" >> "$FILE"
          done
          echo "}" >> "$FILE"
          echo "Profilo salvato: $FILE"
          ;;
        gui)
          # wdisplays = GUI drag-and-drop monitor (wlroots)
          wdisplays &
          ;;
        *)
          echo "solem-monitor — gestione multi-monitor"
          echo "  solem-monitor list                    monitor + risoluzioni"
          echo "  solem-monitor save-profile <name>     salva config attuale"
          echo "  solem-monitor gui                     apri wdisplays GUI"
          ;;
      esac
    '';
  };

  # Profilo kanshi default: docked = 2 monitor, undocked = solo eDP
  defaultKanshiConfig = pkgs.writeText "solem-kanshi.conf" ''
    # SOLEM kanshi default profiles
    # Personalizza per i tuoi monitor reali via `solem-monitor save-profile`

    profile docked {
      output eDP-1 enable scale 1.0
      output * enable position 1920,0
    }

    profile undocked {
      output eDP-1 enable scale 1.0 position 0,0
    }

    profile laptop-closed {
      output eDP-1 disable
      output * enable position 0,0
    }
  '';
in {
  options.solem.multiMonitor = {
    enable = lib.mkEnableOption "Multi-monitor auto-profile (kanshi + wdisplays + CLI)";

    kanshiAutoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Avvia kanshi automaticamente come servizio user al login Wayland";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      monCli
      kanshi          # auto-profile da `output identify`
      wdisplays       # GUI drag-and-drop monitor
      wlr-randr       # CLI like xrandr per wlroots
      wayland-utils   # wayland-info
    ];

    # Config kanshi base (utente può sostituirla)
    environment.etc."xdg/solem/kanshi/config".source = defaultKanshiConfig;

    # kanshi come servizio user (richiede Wayland già up; lo gestisce il desktop)
    # systemd.user.services.kanshi = lib.mkIf cfg.kanshiAutoStart {
    #   description = "Auto-detect outputs and apply kanshi profile";
    #   wantedBy = [ "graphical-session.target" ];
    #   partOf = [ "graphical-session.target" ];
    #   serviceConfig = {
    #     Type = "simple";
    #     ExecStart = "${pkgs.kanshi}/bin/kanshi -c /etc/xdg/solem/kanshi/config";
    #     Restart = "on-failure";
    #   };
    # };
    # Note: lasciato commentato — alcuni desktop manager autoavviano kanshi
    # via home-manager. Evitiamo doppio avvio.
  };
}
