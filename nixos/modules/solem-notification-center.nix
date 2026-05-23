{ config, pkgs, lib, ... }:

# SOLEM NOTIFICATION CENTER — mako + history + UI stilizzato.
#
# Single responsibility: SOLO orchestrare daemon notifiche Wayland (mako)
# + script per history + CLI per gestione (dismiss/list/replay) + tema
# brand SOLEM (navy + gold).
#
# Tutto FOSS, 0 €. Risponde gap "Notification center" COMPETITIVE-GAP.md.

let
  cfg = config.solem.notificationCenter;

  notifCli = pkgs.writeShellApplication {
    name = "solem-notify";
    runtimeInputs = with pkgs; [ mako libnotify coreutils jq ];
    text = ''
      ACTION="''${1:-list}"
      case "$ACTION" in
        list)
          # Mako non ha history nativa via CLI; usa il socket
          makoctl history | jq -r '.data[] | "\(.summary): \(.body)"' 2>/dev/null || echo "(nessuna notifica)"
          ;;
        dismiss-all)
          makoctl dismiss --all
          echo "Tutte le notifiche scartate"
          ;;
        restore)
          # Ripristina l'ultima notifica scartata
          makoctl restore
          ;;
        send)
          TITLE="''${2:?Usage: solem-notify send <title> <body>}"
          BODY="''${3:-}"
          notify-send -a "SOLEM" "$TITLE" "$BODY"
          ;;
        clear|wipe)
          makoctl dismiss --all
          # Sovrascrivi history file se esiste
          HISTORY="$XDG_RUNTIME_DIR/mako/history"
          [[ -f "$HISTORY" ]] && : > "$HISTORY"
          echo "History azzerata"
          ;;
        *)
          echo "solem-notify — notification center FOSS"
          echo
          echo "  solem-notify list           lista notifiche storiche"
          echo "  solem-notify restore        ripristina ultima scartata"
          echo "  solem-notify dismiss-all    dismiss tutte"
          echo "  solem-notify send <t> [b]   invia notifica di test"
          echo "  solem-notify clear          azzera history"
          ;;
      esac
    '';
  };

  # Tema mako SOLEM (navy + gold + Cormorant)
  makoConfig = pkgs.writeText "solem-mako.conf" ''
    # SOLEM mako theme — navy (#0B1426) + gold (#D4A24A)
    font=Inter 11
    width=400
    height=140
    padding=12,18
    border-size=2
    border-radius=10
    background-color=#0B1426E6
    border-color=#D4A24A
    text-color=#F5F5F5
    progress-color=over #D4A24A33
    layer=overlay
    anchor=top-right
    margin=12
    default-timeout=5000
    ignore-timeout=0
    sort=-time
    max-visible=5
    max-history=200
    group-by=app-name

    [urgency=low]
    border-color=#D4A24A77
    default-timeout=3000

    [urgency=normal]
    border-color=#D4A24A

    [urgency=critical]
    border-color=#FF5555
    default-timeout=0
    background-color=#1A0B0BE6

    [app-name=GAVIO]
    border-color=#7B9EFF
    icon-path=/etc/solem/icons/gavio.png
  '';
in {
  options.solem.notificationCenter = {
    enable = lib.mkEnableOption "Notification center Wayland (mako + theme SOLEM + history)";

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Avvia mako automaticamente nel graphical-session";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      notifCli
      mako
      libnotify         # notify-send
      swaynotificationcenter   # alt UI completa (opzionale, ha center GUI)
    ];

    # Config mako in /etc (utente la simlinka in ~/.config/mako/config)
    environment.etc."xdg/solem/mako/config".source = makoConfig;

    # Servizio user systemd (deve girare nel graphical-session utente)
    systemd.user.services.mako = lib.mkIf cfg.autoStart {
      description = "SOLEM Wayland notification daemon";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "dbus";
        BusName = "org.freedesktop.Notifications";
        ExecStart = "${pkgs.mako}/bin/mako --config /etc/xdg/solem/mako/config";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };
  };
}
