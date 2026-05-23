{ config, pkgs, lib, ... }:

# SOLEM POWER PROFILES — switch live tra performance/balanced/power-save.
#
# Single responsibility: SOLO orchestrare power-profiles-daemon (GNOME) +
# CLI `solem-power [performance|balanced|saver]`.
#
# Estende solem-power.nix (config statica laptop/desktop/server) con
# switch RUNTIME (no reboot). Power-profiles-daemon è il sistema standard.

let
  cfg = config.solem.powerProfiles;

  powerCli = pkgs.writeShellApplication {
    name = "solem-power";
    runtimeInputs = with pkgs; [ power-profiles-daemon coreutils ];
    text = ''
      ACTION="''${1:-status}"
      case "$ACTION" in
        status|now)
          powerprofilesctl get
          ;;
        list)
          powerprofilesctl list
          ;;
        performance|perf|max)
          powerprofilesctl set performance
          echo "→ performance"
          ;;
        balanced|normal)
          powerprofilesctl set balanced
          echo "→ balanced"
          ;;
        saver|save|battery|low)
          powerprofilesctl set power-saver
          echo "→ power-saver"
          ;;
        *)
          echo "solem-power — switch power profile live (no reboot)"
          echo
          echo "Comandi:"
          echo "  solem-power status         → profilo attuale"
          echo "  solem-power list           → profili disponibili"
          echo "  solem-power performance    → CPU max + ventole on"
          echo "  solem-power balanced       → bilanciato (default)"
          echo "  solem-power saver          → battery save"
          ;;
      esac
    '';
  };
in {
  options.solem.powerProfiles = {
    enable = lib.mkEnableOption "Power profile live switcher (power-profiles-daemon + CLI)";
  };

  config = lib.mkIf cfg.enable {
    services.power-profiles-daemon.enable = true;
    environment.systemPackages = [ powerCli ];
  };
}
