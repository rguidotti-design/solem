{ config, pkgs, lib, ... }:

# SOLEM UPDATE NOTIFIER — notifica grafica quando ci sono update.
#
# Single responsibility: SOLO CLI `solem-update-check` + timer che:
# - Check ogni 24h se ci sono update SOLEM (git pull dry-run)
# - Notifica con notify-send se trovati
# - Click → apre terminale con istruzioni update

let
  cfg = config.solem.updateNotifier;

  checkCli = pkgs.writeShellApplication {
    name = "solem-update-check";
    runtimeInputs = with pkgs; [ coreutils git libnotify ];
    text = ''
      FLAKE_DIR="''${SOLEM_FLAKE_DIR:-/etc/nixos/solem}"
      if [ ! -d "$FLAKE_DIR/.git" ]; then
        echo "Flake dir non Git: $FLAKE_DIR"
        echo "Setup: clone https://github.com/rguidotti-design/solem in /etc/nixos/solem"
        exit 1
      fi

      cd "$FLAKE_DIR"
      git fetch origin main --quiet 2>/dev/null || {
        echo "Fetch fallito (offline?)"
        exit 0
      }

      BEHIND=$(git rev-list HEAD..origin/main --count 2>/dev/null || echo 0)
      if [ "$BEHIND" -gt 0 ]; then
        LATEST=$(git log --oneline origin/main | head -1)
        echo "▸ $BEHIND nuovi commit dietro:"
        git log --oneline HEAD..origin/main | head -5
        if command -v notify-send >/dev/null 2>&1; then
          notify-send -t 30000 -a "SOLEM Update" \
            "$BEHIND nuovi aggiornamenti" \
            "Ultimo: $LATEST\n\nEsegui: sudo nixos-rebuild boot --flake $FLAKE_DIR#solem-vm"
        fi
      else
        echo "✓ SOLEM aggiornato"
      fi
    '';
  };
in {
  options.solem.updateNotifier = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa `solem-update-check` + timer notifica update";
    };

    schedule = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "OnCalendar systemd (daily, hourly, weekly, ...)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ checkCli ];

    systemd.user.services.solem-update-check = {
      description = "SOLEM Update Check";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${checkCli}/bin/solem-update-check";
      };
    };

    systemd.user.timers.solem-update-check = {
      description = "Check SOLEM update ${cfg.schedule}";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };
  };
}
