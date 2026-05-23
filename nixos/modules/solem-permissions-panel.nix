{ config, pkgs, lib, ... }:

# SOLEM PERMISSIONS PANEL — UI runtime per camera/mic/location/screen.
#
# Single responsibility: SOLO installare:
# - xdg-desktop-portal + portal-hyprland / portal-gtk (richiesta permission)
# - flatpak-permissions (resetta override per Flatpak)
# - Picosnitch / Opensnitch (interactive firewall outbound)
# - CLI `solem-perm` per audit/revoca permission
#
# 0 €. Risponde gap "Runtime permissions UI iOS-like" COMPETITIVE-GAP.md.

let
  cfg = config.solem.permissionsPanel;

  permCli = pkgs.writeShellApplication {
    name = "solem-perm";
    runtimeInputs = with pkgs; [ flatpak coreutils gawk ];
    text = ''
      ACTION="''${1:-status}"
      case "$ACTION" in
        status)
          echo "── Permessi Flatpak runtime ──"
          for app in $(flatpak list --app --columns=application 2>/dev/null); do
            CAM=$(flatpak permission-show "$app" 2>/dev/null | grep -q "camera" && echo "📷" || echo "—")
            MIC=$(flatpak permission-show "$app" 2>/dev/null | grep -q "microphone" && echo "🎤" || echo "—")
            LOC=$(flatpak permission-show "$app" 2>/dev/null | grep -q "location" && echo "📍" || echo "—")
            printf "  %-40s %s %s %s\n" "$app" "$CAM" "$MIC" "$LOC"
          done
          ;;
        camera)
          # Lista chi sta usando la camera ORA
          echo "── Processi che usano /dev/video* ──"
          for dev in /dev/video*; do
            [[ -e "$dev" ]] || continue
            USERS=$(fuser "$dev" 2>/dev/null || true)
            if [[ -n "$USERS" ]]; then
              echo "$dev → PID:$USERS"
              for pid in $USERS; do
                CMD=$(ps -p "$pid" -o comm= 2>/dev/null || true)
                echo "    $pid → $CMD"
              done
            fi
          done
          ;;
        mic|microphone)
          echo "── Sink/source audio attivi ──"
          if command -v pw-cli >/dev/null; then
            pw-cli list-objects Node | grep -E "media.class|node.name" | paste - - | grep -i input
          else
            echo "PipeWire non disponibile"
          fi
          ;;
        revoke)
          # Revoca tutti i permission Flatpak (reset)
          APP="''${2:?Usage: solem-perm revoke <app-id>}"
          flatpak permission-reset "$APP"
          echo "Reset permission per $APP"
          ;;
        revoke-all)
          if [[ "''${2:-}" == "--yes" ]]; then
            for app in $(flatpak list --app --columns=application); do
              flatpak permission-reset "$app"
            done
            echo "Tutti i permission Flatpak resettati"
          else
            echo "Conferma con: solem-perm revoke-all --yes"
          fi
          ;;
        kill-camera)
          # Termina processi che stanno usando la camera
          for dev in /dev/video*; do
            [[ -e "$dev" ]] || continue
            USERS=$(fuser "$dev" 2>/dev/null || true)
            for pid in $USERS; do
              kill -TERM "$pid" 2>/dev/null && echo "Terminato PID $pid"
            done
          done
          ;;
        *)
          echo "solem-perm — runtime permissions panel FOSS"
          echo
          echo "  solem-perm status          stato camera/mic/location per Flatpak"
          echo "  solem-perm camera          chi sta usando la camera ORA"
          echo "  solem-perm mic             chi sta usando il mic ORA"
          echo "  solem-perm revoke <app>    reset permessi singola app"
          echo "  solem-perm revoke-all      reset tutti (richiede --yes)"
          echo "  solem-perm kill-camera     termina chi usa /dev/video*"
          ;;
      esac
    '';
  };
in {
  options.solem.permissionsPanel = {
    enable = lib.mkEnableOption "Runtime permissions UI (xdg-portal + opensnitch + CLI)";

    opensnitch = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Opensnitch — firewall outbound interattivo (clone Little Snitch FOSS)";
    };

    portals = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "xdg-desktop-portal completo (camera/mic/location/screen via prompt)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; lib.flatten [
      [
        permCli
        flatpak             # base per permission-show
        psmisc              # fuser
        lsof
      ]

      (lib.optionals cfg.opensnitch [
        opensnitch
        opensnitch-ui
      ])
    ];

    # xdg-desktop-portal: chiede sempre permission GUI prima di accedere
    # a camera/mic/location/screencast.
    xdg.portal = lib.mkIf cfg.portals {
      enable = true;
      wlr.enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
        xdg-desktop-portal-hyprland
      ];
      config.common.default = "*";
    };

    # Opensnitch daemon
    services.opensnitch = lib.mkIf cfg.opensnitch {
      enable = true;
      settings = {
        DefaultAction = "deny";       # default: nega outbound nuovo
        DefaultDuration = "until restart";
        InterceptUnknown = true;
        LogLevel = 2;
      };
    };
  };
}
