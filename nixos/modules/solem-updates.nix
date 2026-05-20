{ config, pkgs, lib, ... }:

# SOLEM UPDATES — channel + auto-check timer.
#
# Single responsibility: SOLO timer settimanale di check update + scrivere
# canale corrente in /etc/solem/channel. L'apply effettivo passa per API
# (solem-api /updates/apply) o manuale.
#
# Canali (vedi backend layers/updates.py):
#   - stable   (default)
#   - testing
#   - nightly

let
  cfg = config.solem.updates;
in {
  options.solem.updates = {
    channel = lib.mkOption {
      type = lib.types.enum [ "stable" "testing" "nightly" ];
      default = "stable";
      description = "Canale update SOLEM";
    };

    autoCheckEnable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Check settimanale update via timer (no apply automatico)";
    };

    autoApplyEnable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "PERICOLO: nixos-rebuild switch automatico (default off)";
    };
  };

  config = {
    # Scrivi canale in /etc/solem/channel
    environment.etc."solem/channel".text = cfg.channel;

    # Timer check settimanale (no apply)
    systemd.services.solem-update-check = lib.mkIf cfg.autoCheckEnable {
      description = "SOLEM — check update settimanale";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = with pkgs; [ curl jq ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = pkgs.writeShellScript "solem-update-check" ''
          set -euo pipefail
          ${pkgs.curl}/bin/curl -fsS -X POST http://127.0.0.1:8001/solem/updates/check \
            -H 'Content-Type: application/json' \
            > /var/lib/solem/last-update-check.json 2>&1 || true
        '';
      };
    };

    systemd.timers.solem-update-check = lib.mkIf cfg.autoCheckEnable {
      description = "Trigger update check ogni domenica 04:00";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Sun *-*-* 04:00:00";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };

    # Auto-apply opt-in (off by default)
    systemd.services.solem-update-apply = lib.mkIf cfg.autoApplyEnable {
      description = "SOLEM — auto-apply update (PERICOLO)";
      after = [ "solem-update-check.service" ];
      path = with pkgs; [ curl ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = pkgs.writeShellScript "solem-update-apply" ''
          set -euo pipefail
          ${pkgs.curl}/bin/curl -fsS -X POST http://127.0.0.1:8001/solem/updates/apply \
            >> /var/log/solem/auto-update.log 2>&1 || true
        '';
      };
    };

    systemd.timers.solem-update-apply = lib.mkIf cfg.autoApplyEnable {
      description = "Auto-apply update ogni domenica 05:00";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Sun *-*-* 05:00:00";
        Persistent = true;
        RandomizedDelaySec = "30min";
      };
    };
  };
}
