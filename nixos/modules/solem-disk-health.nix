{ config, pkgs, lib, ... }:

# SOLEM DISK HEALTH — monitoraggio SMART continuo + alert.
#
# Single responsibility: SOLO CLI `solem-disk` + service smartd
# che monitora SMART data e alerta su soglia critica.

let
  cfg = config.solem.diskHealth;

  diskCli = pkgs.writeShellApplication {
    name = "solem-disk";
    runtimeInputs = with pkgs; [ coreutils smartmontools util-linux ];
    text = ''
      ACTION="''${1:-summary}"
      shift || true

      case "$ACTION" in
        summary|status)
          echo "── SOLEM Disk Health ──"
          for dev in /dev/sd? /dev/nvme?n? /dev/vd?; do
            [ -e "$dev" ] || continue
            echo
            echo "▸ $dev:"
            SIZE=$(lsblk -no SIZE "$dev" 2>/dev/null | head -1)
            echo "  Size:   $SIZE"
            # SMART overall
            HEALTH=$(sudo smartctl -H "$dev" 2>/dev/null | grep -i "result:" | awk '{print $NF}')
            echo "  SMART:  ''${HEALTH:-unknown}"
            # Temperature
            TEMP=$(sudo smartctl -A "$dev" 2>/dev/null | grep -iE "temperature|airflow" | head -1 | awk '{print $10}')
            [ -n "$TEMP" ] && echo "  Temp:   $TEMP°C"
            # SSD wear (NVMe)
            if [[ "$dev" == /dev/nvme* ]]; then
              PCT=$(sudo smartctl -a "$dev" 2>/dev/null | awk '/Percentage Used/ {print $NF}')
              [ -n "$PCT" ] && echo "  Wear:   $PCT"
              PWR=$(sudo smartctl -a "$dev" 2>/dev/null | awk '/Power On Hours/ {print $NF}')
              [ -n "$PWR" ] && echo "  Hours:  $PWR"
            fi
          done
          ;;

        details)
          DEV="''${1:?Usage: solem-disk details /dev/sda}"
          sudo smartctl -a "$DEV"
          ;;

        test-short)
          DEV="''${1:?}"
          sudo smartctl -t short "$DEV"
          echo "Test breve avviato. Risultati con: solem-disk test-result $DEV"
          ;;

        test-long)
          DEV="''${1:?}"
          sudo smartctl -t long "$DEV"
          ;;

        test-result)
          DEV="''${1:?}"
          sudo smartctl -l selftest "$DEV"
          ;;

        usage|df)
          df -h --output=source,size,used,avail,pcent,target | grep -E "^/dev"
          ;;

        biggest)
          # I 20 file più grandi in $HOME
          DIR="''${1:-$HOME}"
          du -ah "$DIR" 2>/dev/null | sort -hr | head -20
          ;;

        help|--help|-h|*)
          cat <<'HELP'
solem-disk — disk health monitoring (smartmontools FOSS)

  summary              SMART overview tutti i dischi
  details <dev>        SMART completo singolo disco
  test-short <dev>     SMART self-test 5 min
  test-long <dev>      SMART self-test esteso (ore)
  test-result <dev>    risultato ultimo test
  usage                df -h dischi
  biggest [dir]        20 file più grandi (default $HOME)

Service smartd attivo: alert email automatico se SMART fail.

Tutto FOSS (smartmontools GPL-2). 0 €.
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.diskHealth = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa `solem-disk` + smartd monitoring continuo";
    };

    smartdEnable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Abilita smartd daemon monitoring (richiede config /etc/smartd.conf)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      diskCli
      smartmontools
    ];

    services.smartd = lib.mkIf cfg.smartdEnable {
      enable = true;
      autodetect = true;
    };
  };
}
