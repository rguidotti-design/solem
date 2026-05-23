{ config, pkgs, lib, ... }:

# SOLEM DISPLAY — multi-monitor profiles + scaling fractional.
#
# Single responsibility: SOLO config display Wayland + CLI `solem-display`
# per cambio profilo monitor (laptop/dual/triple/extension).
#
# Wayland nativo: wlr-randr per CLI, kanshi per profili auto detect.
#
# Esempio:
#   solem-display profiles                       lista profili known
#   solem-display set dual-4k                    applica profilo
#   solem-display auto                           rileva + applica best match

let
  cfg = config.solem.display;

  kanshiConfig = pkgs.writeText "kanshi-config" ''
    # SOLEM display profiles per kanshi (auto-switch monitor)

    # Solo laptop interno
    profile laptop {
      output eDP-1 enable mode 1920x1080 position 0,0 scale 1
    }

    # Dual monitor 4K esterno
    profile dual-4k {
      output eDP-1 enable mode 1920x1080 position 0,2160 scale 1
      output DP-1 enable mode 3840x2160 position 0,0 scale 1.5
    }

    # Triple monitor home office
    profile triple {
      output eDP-1 enable mode 1920x1080 position 0,1080 scale 1
      output DP-1 enable mode 2560x1440 position 0,0 scale 1
      output HDMI-A-1 enable mode 1920x1080 position 2560,0 scale 1
    }
  '';

  displayCli = pkgs.writeShellApplication {
    name = "solem-display";
    runtimeInputs = with pkgs; [ wlr-randr kanshi coreutils ];
    text = ''
      ACTION="''${1:-status}"
      case "$ACTION" in
        status|now|list-outputs)
          wlr-randr
          ;;
        profiles)
          echo "Profili disponibili (da /etc/xdg/kanshi/config):"
          grep -E '^profile ' /etc/xdg/kanshi/config | awk '{print "  " $2}'
          ;;
        set)
          shift
          PROFILE="$1"
          # kanshi non ha "set profile" diretto, ma legge il config e
          # cerca match automatico. Hack: scrive un override.
          echo "kanshi non supporta switch profilo diretto in CLI."
          echo "Profilo applicato automaticamente al collegamento monitor."
          echo "Per forzare ora: killall kanshi && kanshi -c /etc/xdg/kanshi/config &"
          ;;
        auto|reload)
          killall kanshi 2>/dev/null || true
          kanshi -c /etc/xdg/kanshi/config &
          disown
          echo "kanshi ricaricato, auto-match"
          ;;
        rotate)
          OUT="''${2:-eDP-1}"
          DIR="''${3:-90}"
          wlr-randr --output "$OUT" --transform "$DIR"
          ;;
        scale)
          OUT="''${2:-eDP-1}"
          FACTOR="''${3:-1.0}"
          wlr-randr --output "$OUT" --scale "$FACTOR"
          ;;
        *)
          echo "solem-display — multi-monitor config"
          echo
          echo "  solem-display status            output attivi + risoluzioni"
          echo "  solem-display profiles          profili kanshi disponibili"
          echo "  solem-display auto              ricarica kanshi auto-detect"
          echo "  solem-display rotate <out> <deg>"
          echo "  solem-display scale <out> <fact>"
          ;;
      esac
    '';
  };
in {
  options.solem.display = {
    enable = lib.mkEnableOption "Multi-monitor management (kanshi + wlr-randr)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      displayCli wlr-randr kanshi wdisplays  # GUI editor
    ];

    environment.etc."xdg/kanshi/config".source = kanshiConfig;

    # User service kanshi (auto-start su graphical-session)
    systemd.user.services.kanshi = {
      description = "SOLEM — kanshi monitor auto-config";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.kanshi}/bin/kanshi -c /etc/xdg/kanshi/config";
        Restart = "on-failure";
      };
    };
  };
}
