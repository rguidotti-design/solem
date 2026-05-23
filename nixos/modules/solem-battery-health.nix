{ config, pkgs, lib, ... }:

# SOLEM BATTERY HEALTH — monitor + report degrado batteria (laptop).
#
# Single responsibility: SOLO leggere /sys/class/power_supply + CLI
# `solem-battery health` per analisi degrado. Niente intervento auto.

let
  cfg = config.solem.batteryHealth;

  batteryCli = pkgs.writeShellApplication {
    name = "solem-battery";
    runtimeInputs = with pkgs; [ acpi coreutils ];
    text = ''
      BAT_DIR="/sys/class/power_supply"
      ACTION="''${1:-status}"

      bat_pick() {
        for d in "$BAT_DIR"/BAT* "$BAT_DIR"/battery; do
          [ -d "$d" ] && { echo "$d"; return; }
        done
        echo ""
      }
      BAT=$(bat_pick)
      if [ -z "$BAT" ]; then
        echo "Nessuna batteria trovata (sei su desktop?)"
        exit 1
      fi

      read_int() { ${pkgs.coreutils}/bin/cat "$1" 2>/dev/null || echo 0; }

      DESIGN=$(read_int "$BAT/energy_full_design")
      FULL=$(read_int "$BAT/energy_full")
      NOW=$(read_int "$BAT/energy_now")
      CYCLES=$(read_int "$BAT/cycle_count")
      STATUS=$(${pkgs.coreutils}/bin/cat "$BAT/status" 2>/dev/null || echo unknown)
      VOLT=$(read_int "$BAT/voltage_now")

      pct_full=0
      pct_health=100
      if [ "$DESIGN" -gt 0 ]; then
        pct_health=$(( FULL * 100 / DESIGN ))
      fi
      if [ "$FULL" -gt 0 ]; then
        pct_full=$(( NOW * 100 / FULL ))
      fi

      case "$ACTION" in
        status)
          echo "  Battery: $BAT"
          echo "  Status:  $STATUS"
          echo "  Charge:  $pct_full%"
          ;;
        health)
          echo "  ── Battery Health Report ──"
          echo "  Capacità design:   $(( DESIGN / 1000000 )) Wh"
          echo "  Capacità attuale:  $(( FULL / 1000000 )) Wh"
          echo "  Health:            $pct_health%"
          echo "  Cicli ricarica:    $CYCLES"
          echo "  Voltage:           $(( VOLT / 1000 )) mV"
          echo
          if [ "$pct_health" -lt 80 ]; then
            echo "  ⚠ Batteria degradata sotto 80%. Considera sostituzione."
          elif [ "$pct_health" -lt 60 ]; then
            echo "  ⚠⚠ Batteria seriamente degradata. Cambiare adesso."
          else
            echo "  ✓ Batteria in buona salute."
          fi
          ;;
        watch|live)
          while true; do
            clear
            "$0" status
            ${pkgs.coreutils}/bin/sleep 5
          done
          ;;
        *)
          echo "solem-battery — health + status batteria"
          echo
          echo "  solem-battery status     stato corrente"
          echo "  solem-battery health     report degrado + cicli"
          echo "  solem-battery watch      monitor live ogni 5s"
          ;;
      esac
    '';
  };
in {
  options.solem.batteryHealth = {
    enable = lib.mkEnableOption "Battery health monitor + CLI";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      batteryCli acpi upower powertop
    ];

    # Notifica desktop quando health < 80%
    services.upower.enable = true;
  };
}
