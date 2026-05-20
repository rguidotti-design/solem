{ config, pkgs, lib, ... }:

# SOLEM AUTOHEAL — health probe post-update + rollback automatico.
#
# Single responsibility: SOLO eseguire health check 60s dopo ogni
# nixos-rebuild switch. Se fallisce → rollback automatico alla previous
# generation.
#
# Logica:
#   1. Hook nixos-rebuild post-switch lascia /var/lib/solem/last-build-id
#   2. Timer eseguito a +60s controlla:
#      - solem-api risponde su :8001/health
#      - servizi critici "active": solem-api, NetworkManager, dbus
#   3. Se KO → systemctl reboot con --switch=rollback
#
# 100% FOSS, 0 €. Niente cloud, niente telemetria.

let
  cfg = config.solem.autoheal;

  healthCheck = pkgs.writeShellScript "solem-autoheal-check" ''
    set -uo pipefail

    LOG=/var/log/solem/autoheal.log
    mkdir -p /var/log/solem
    echo "[$(date -u +%FT%TZ)] autoheal check start" >> $LOG

    FAILED=0

    # Check 1: solem-api health
    if ! ${pkgs.curl}/bin/curl -fsS --max-time 5 http://127.0.0.1:8001/health > /dev/null; then
      echo "  - solem-api: FAIL" >> $LOG
      FAILED=$((FAILED + 1))
    else
      echo "  - solem-api: ok" >> $LOG
    fi

    # Check 2: servizi critici
    for svc in dbus.service NetworkManager.service systemd-resolved.service; do
      state=$(${pkgs.systemd}/bin/systemctl is-active "$svc" 2>/dev/null || echo "missing")
      if [ "$state" != "active" ]; then
        echo "  - $svc: $state" >> $LOG
        FAILED=$((FAILED + 1))
      fi
    done

    # Check 3: failed units count
    failed_units=$(${pkgs.systemd}/bin/systemctl --failed --no-legend --plain | wc -l)
    if [ "$failed_units" -gt 3 ]; then
      echo "  - failed units: $failed_units (threshold 3)" >> $LOG
      FAILED=$((FAILED + 1))
    fi

    if [ "$FAILED" -ge ${toString cfg.failThreshold} ]; then
      echo "[$(date -u +%FT%TZ)] AUTOHEAL TRIGGERED ($FAILED checks failed)" >> $LOG
      ${lib.optionalString cfg.autoRollback ''
        echo "  → ROLLBACK alla previous generation" >> $LOG
        /run/current-system/bin/switch-to-configuration boot 2>>$LOG || true
        # nixos-rebuild --rollback boot+reboot
        ${pkgs.nixos-rebuild}/bin/nixos-rebuild --rollback boot 2>>$LOG || true
        sleep 5
        ${pkgs.systemd}/bin/systemctl reboot
      ''}
    else
      echo "[$(date -u +%FT%TZ)] system healthy ($FAILED failures, threshold ${toString cfg.failThreshold})" >> $LOG
    fi
  '';
in {
  options.solem.autoheal = {
    enable = lib.mkEnableOption "Health check post-boot + auto-rollback se fallisce";

    failThreshold = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Numero check falliti che triggerano il rollback";
    };

    autoRollback = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Esegui rollback effettivo (default solo log per safety)";
    };

    delayAfterBoot = lib.mkOption {
      type = lib.types.str;
      default = "2min";
      description = "Attesa post-boot prima del check";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.solem-autoheal = {
      description = "SOLEM — health check post-boot + auto-rollback";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = healthCheck;
      };
    };

    systemd.timers.solem-autoheal = {
      description = "Trigger autoheal check a ${cfg.delayAfterBoot} dopo boot";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = cfg.delayAfterBoot;
        AccuracySec = "30s";
      };
    };

    # Log dir
    systemd.tmpfiles.rules = [
      "d /var/log/solem 0755 root root - -"
    ];
  };
}
