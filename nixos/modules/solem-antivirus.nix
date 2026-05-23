{ config, pkgs, lib, ... }:

# SOLEM ANTIVIRUS — ClamAV scan on-demand opt-in (FOSS).
#
# Single responsibility: SOLO config ClamAV daemon + freshclam updater +
# CLI `solem-scan <path>`. Niente real-time scanning (overhead alto),
# solo scan manuale o timer schedulato.
#
# Caso d'uso: scansionare allegati email scaricati, USB nuove, file
# condivisi via Syncthing. Specialmente utile per file che andranno
# poi su Windows tramite Samba.

let
  cfg = config.solem.antivirus;

  scanCli = pkgs.writeShellApplication {
    name = "solem-scan";
    runtimeInputs = with pkgs; [ clamav coreutils ];
    text = ''
      ACTION="''${1:-help}"
      case "$ACTION" in
        update)
          sudo freshclam
          ;;
        path|file|dir)
          shift
          TARGET="''${1:-.}"
          clamscan --recursive --infected --bell "$TARGET"
          ;;
        downloads|home)
          clamscan --recursive --infected "$HOME/Downloads"
          ;;
        full|system)
          echo "Scan completo /home + /tmp (può durare ore)..."
          sudo clamscan --recursive --infected --quiet /home /tmp
          ;;
        *)
          echo "solem-scan — scansione antivirus on-demand"
          echo
          echo "  solem-scan update         aggiorna definizioni virus"
          echo "  solem-scan path <dir>     scan ricorsivo"
          echo "  solem-scan downloads      scan ~/Downloads"
          echo "  solem-scan full           scan /home + /tmp"
          ;;
      esac
    '';
  };
in {
  options.solem.antivirus = {
    enable = lib.mkEnableOption "ClamAV scan on-demand (FOSS antivirus)";

    weeklyAutoScan = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Timer settimanale scan ~/Downloads (notifica se infected)";
    };
  };

  config = lib.mkIf cfg.enable {
    services.clamav = {
      daemon.enable = false;     # on-demand only, no real-time
      updater = {
        enable = true;
        frequency = 24;          # check definizioni ogni 24h
      };
    };

    environment.systemPackages = with pkgs; [ clamav scanCli ];

    # Timer scan settimanale opt-in
    systemd.services.solem-weekly-scan = lib.mkIf cfg.weeklyAutoScan {
      description = "SOLEM — scan settimanale ~/Downloads";
      serviceConfig = {
        Type = "oneshot";
        User = "gavio";
        ExecStart = "${pkgs.clamav}/bin/clamscan --recursive --infected /home/gavio/Downloads";
      };
    };

    systemd.timers.solem-weekly-scan = lib.mkIf cfg.weeklyAutoScan {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Sun 03:00";
        Persistent = true;
        RandomizedDelaySec = "30m";
      };
    };
  };
}
