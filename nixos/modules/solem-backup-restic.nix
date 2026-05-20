{ config, pkgs, lib, ... }:

# SOLEM BACKUP RESTIC — backup encrypted con restic (alternativa al
# solem-backup base tar+zstd).
#
# Single responsibility: SOLO orchestrare timer + restic encrypted.
# Coesiste con solem-backup.nix (tar+zstd snapshot rapido). Restic
# aggiunge: encryption, dedup, retention policy, destinazioni remote.
#
# Tutto FOSS. Costo: 0 € (storage può essere locale, NAS, o S3-compat).

let
  cfg = config.solem.backupRestic;
in {
  options.solem.backupRestic = {
    enable = lib.mkEnableOption "Backup encrypted restic giornaliero";

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "/var/lib/solem"
        "/var/lib/gavio"
        "/etc/solem"
        "/home/gavio/Documents"
      ];
    };

    excludePatterns = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "*.cache" "*.tmp" "__pycache__" "node_modules" "*.log" ];
    };

    repository = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/solem-backups-restic";
      description = "Path locale o URL: s3:..., sftp:..., rclone:...";
    };

    passwordFile = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/solem-secrets/restic.pass";
    };

    schedule = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 03:00:00";
    };

    keepDaily   = lib.mkOption { type = lib.types.int; default = 7; };
    keepWeekly  = lib.mkOption { type = lib.types.int; default = 4; };
    keepMonthly = lib.mkOption { type = lib.types.int; default = 12; };
    keepYearly  = lib.mkOption { type = lib.types.int; default = 3; };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.restic ];

    systemd.tmpfiles.rules = [
      "d /var/lib/solem-backups-restic 0700 root root - -"
      "d /var/lib/solem-secrets        0700 root root - -"
    ];

    systemd.services.solem-backup-restic = {
      description = "SOLEM — backup encrypted (restic snapshot)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = with pkgs; [ restic openssh ];
      environment = {
        RESTIC_REPOSITORY = cfg.repository;
        RESTIC_PASSWORD_FILE = toString cfg.passwordFile;
      };
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Nice = 19;
        IOSchedulingClass = "idle";
        ExecStart = pkgs.writeShellScript "solem-backup-restic-run" ''
          set -euo pipefail
          if [ ! -f "$RESTIC_PASSWORD_FILE" ]; then
            echo "[solem-backup-restic] password file mancante: $RESTIC_PASSWORD_FILE"
            exit 1
          fi
          if ! ${pkgs.restic}/bin/restic snapshots >/dev/null 2>&1; then
            ${pkgs.restic}/bin/restic init
          fi
          ${pkgs.restic}/bin/restic backup \
            ${lib.concatStringsSep " " (map (p: "'${p}'") cfg.paths)} \
            ${lib.concatStringsSep " " (map (e: "--exclude='${e}'") cfg.excludePatterns)} \
            --tag solem-auto --tag $(date +%Y-%m-%d)
          ${pkgs.restic}/bin/restic forget --prune \
            --keep-daily   ${toString cfg.keepDaily} \
            --keep-weekly  ${toString cfg.keepWeekly} \
            --keep-monthly ${toString cfg.keepMonthly} \
            --keep-yearly  ${toString cfg.keepYearly}
        '';
      };
    };

    systemd.timers.solem-backup-restic = {
      description = "Trigger backup restic giornaliero";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
        RandomizedDelaySec = "30min";
      };
    };
  };
}
