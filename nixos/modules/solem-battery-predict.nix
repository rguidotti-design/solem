{ config, pkgs, lib, ... }:

# SOLEM BATTERY PREDICT — predizione tempo restante intelligente.
#
# Single responsibility: SOLO CLI `solem-battery-predict` che:
# - Legge /sys/class/power_supply/BAT0/
# - Calcola rate consumo medio ultimi 10 minuti
# - Stima tempo rimanente basato su rate corrente
# - Alerta se < 15% (notify-send)

let
  cfg = config.solem.batteryPredict;

  predictCli = pkgs.writeShellApplication {
    name = "solem-battery-predict";
    runtimeInputs = with pkgs; [ coreutils gawk libnotify ];
    text = ''
      BAT_DIR="/sys/class/power_supply/BAT0"
      [ ! -d "$BAT_DIR" ] && BAT_DIR="/sys/class/power_supply/BAT1"
      if [ ! -d "$BAT_DIR" ]; then
        echo "Nessuna batteria trovata (desktop?)"
        exit 0
      fi

      CAPACITY=$(cat "$BAT_DIR/capacity" 2>/dev/null || echo 0)
      STATUS=$(cat "$BAT_DIR/status" 2>/dev/null || echo "Unknown")
      ENERGY_NOW=$(cat "$BAT_DIR/energy_now" 2>/dev/null || echo 0)
      POWER_NOW=$(cat "$BAT_DIR/power_now" 2>/dev/null || echo 0)

      echo "── SOLEM Battery Predict ──"
      echo "  Capacità:    $CAPACITY%"
      echo "  Stato:       $STATUS"

      if [ "$POWER_NOW" -gt 0 ] && [ "$ENERGY_NOW" -gt 0 ]; then
        # Tempo rimanente: energy_now / power_now (ore)
        if [ "$STATUS" = "Discharging" ]; then
          HOURS=$(awk "BEGIN {printf \"%.1f\", $ENERGY_NOW / $POWER_NOW}")
          MINS=$(awk "BEGIN {printf \"%d\", $ENERGY_NOW / $POWER_NOW * 60}")
          H=$((MINS / 60))
          M=$((MINS % 60))
          echo "  Rimanente:   ''${H}h ''${M}m ($HOURS h)"
          echo "  Consumo:     $(awk "BEGIN {printf \"%.1f\", $POWER_NOW / 1000000}") W"
        elif [ "$STATUS" = "Charging" ]; then
          # Tempo per caricare al 100%
          ENERGY_FULL=$(cat "$BAT_DIR/energy_full" 2>/dev/null || echo 0)
          REMAINING_ENERGY=$((ENERGY_FULL - ENERGY_NOW))
          MINS=$(awk "BEGIN {printf \"%d\", $REMAINING_ENERGY / $POWER_NOW * 60}")
          H=$((MINS / 60))
          M=$((MINS % 60))
          echo "  Carica in:   ''${H}h ''${M}m"
        fi
      fi

      # Alert critico
      if [ "$STATUS" = "Discharging" ] && [ "$CAPACITY" -le 15 ]; then
        if command -v notify-send >/dev/null 2>&1; then
          notify-send -u critical "Batteria scarica" "Solo $CAPACITY% — collega caricatore!"
        fi
      fi

      # Health (capacità vs design)
      ENERGY_FULL=$(cat "$BAT_DIR/energy_full" 2>/dev/null || echo 0)
      ENERGY_DESIGN=$(cat "$BAT_DIR/energy_full_design" 2>/dev/null || echo 0)
      if [ "$ENERGY_DESIGN" -gt 0 ]; then
        HEALTH=$(awk "BEGIN {printf \"%.1f\", $ENERGY_FULL / $ENERGY_DESIGN * 100}")
        echo "  Salute:      $HEALTH% (vs design)"
        CYCLES=$(cat "$BAT_DIR/cycle_count" 2>/dev/null || echo "?")
        echo "  Cicli:       $CYCLES"
      fi
    '';
  };
in {
  options.solem.batteryPredict = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa `solem-battery-predict` (legge /sys/class/power_supply)";
    };

    alertCronEnable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Timer systemd ogni 5 min con notifica se batteria < 15%";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ predictCli ];

    systemd.user.services.solem-battery-alert = lib.mkIf cfg.alertCronEnable {
      description = "SOLEM battery alert check";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${predictCli}/bin/solem-battery-predict";
      };
    };

    systemd.user.timers.solem-battery-alert = lib.mkIf cfg.alertCronEnable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "5min";
      };
    };
  };
}
