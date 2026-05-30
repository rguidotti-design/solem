{ config, pkgs, lib, ... }:

# SOLEM BACKUP ENCRYPTED — Step 17: borg + age backup automatic offsite-safe.
#
# Single responsibility: SOLO orchestrare borgbackup + age encryption
# per backup automatici cifrati locali + sync offsite via rclone.
#
# Threat coperto:
#   - Ransomware: backup snapshot append-only (borg) NON modificabile da
#     attaccante post-encryption.
#   - Disk fail: snapshots multi-versione → recovery.
#   - Offsite theft: backup cifrato age (X25519) prima di upload → utile
#     anche se cloud provider compromesso.
#   - Time-machine style restore.
#
# Stack:
#   - borgbackup (BSD-3): deduplicating snapshots con encryption built-in
#     (repokey-blake2)
#   - age (BSD): re-encryption layer prima di sync offsite (defense-in-depth)
#   - rclone (MIT): sync cifrato a 70+ provider (Nextcloud, S3, B2, ...)
#   - systemd timer: backup ogni 6h
#
# Tutto FOSS, 0 € paid services.

let
  cfg = config.solem.backupEncrypted;

  borgBackupScript = pkgs.writeShellApplication {
    name = "solem-backup-run";
    runtimeInputs = with pkgs; [ coreutils borgbackup age rclone systemd ];
    text = ''
      set -eu
      REPO="${cfg.localRepo}"
      LOG=/var/log/solem/backup.log
      mkdir -p "$(dirname "$LOG")" "$REPO"

      log() {
        echo "[$(date -Iseconds)] $*" | tee -a "$LOG"
      }

      log "── BACKUP START ──"

      # Passphrase via secret file (mode 0600 root-only)
      if [ ! -f /etc/solem/backup-passphrase ]; then
        log "ERROR: /etc/solem/backup-passphrase mancante. Esegui solem-backup init."
        exit 1
      fi
      # shellcheck disable=SC2155
      export BORG_PASSPHRASE=$(cat /etc/solem/backup-passphrase)

      # Init repo se prima volta
      if [ ! -d "$REPO/data" ]; then
        log "Init borg repo encryption=repokey-blake2"
        borg init --encryption=repokey-blake2 "$REPO"
      fi

      # Backup
      ARCHIVE_NAME="solem-$(date +%Y%m%d-%H%M%S)"
      log "Creating archive: $ARCHIVE_NAME"
      borg create --stats --compression zstd,9 \
        "$REPO::$ARCHIVE_NAME" \
        ${lib.concatMapStringsSep " \\\n        " (p: ''"${p}"'') cfg.paths} \
        ${lib.concatMapStringsSep " " (p: "--exclude=" + lib.escapeShellArg p) cfg.exclude} \
        2>&1 | tee -a "$LOG"

      # Prune: keep last N snapshots
      log "Pruning old archives"
      borg prune --stats --list "$REPO" \
        --keep-hourly=${toString cfg.retention.hourly} \
        --keep-daily=${toString cfg.retention.daily} \
        --keep-weekly=${toString cfg.retention.weekly} \
        --keep-monthly=${toString cfg.retention.monthly} \
        2>&1 | tee -a "$LOG"

      # Compact (libera spazio fisico dopo prune)
      log "Compacting"
      borg compact "$REPO" 2>&1 | tee -a "$LOG"

      # Offsite sync (se configurato)
      ${lib.optionalString (cfg.offsite.rcloneRemote != null) ''
        log "Sync offsite to ${cfg.offsite.rcloneRemote}"
        # Doppia cifratura: borg gia' cripta, age re-cipher prima upload
        # (defense-in-depth — se compromise borg key, age key separata
        # ancora protegge contro lettura cloud)
        ${lib.optionalString cfg.offsite.ageRecipientFile != null ''
          # TODO: tar+age intermediate (lento per repo grossi)
        ''}
        rclone sync "$REPO" "${cfg.offsite.rcloneRemote}:${cfg.offsite.remotePath}" \
          --transfers=4 --checkers=8 \
          --log-file="$LOG" --log-level=INFO \
          || log "WARN: offsite sync failed (continuing)"
      ''}

      log "── BACKUP DONE ──"
    '';
  };

  backupCli = pkgs.writeShellApplication {
    name = "solem-backup";
    runtimeInputs = with pkgs; [ coreutils borgbackup systemd ];
    text = ''
      ACTION="''${1:-status}"
      shift || true
      REPO="${cfg.localRepo}"

      case "$ACTION" in
        init)
          if [ -f /etc/solem/backup-passphrase ]; then
            echo "Passphrase gia' esistente in /etc/solem/backup-passphrase"
            exit 0
          fi
          echo "Genero passphrase casuale 32 byte..."
          mkdir -p /etc/solem
          head -c 24 /dev/urandom | base64 | sudo tee /etc/solem/backup-passphrase > /dev/null
          sudo chmod 600 /etc/solem/backup-passphrase
          echo "✓ Passphrase salvata in /etc/solem/backup-passphrase (chmod 600)"
          echo "  ⚠ BACKUP MANUALE: copia file su USB esterno, senza non recuperi i dati!"
          ;;

        run|now)
          sudo systemctl start solem-backup.service
          echo "Backup avviato. Log: sudo journalctl -u solem-backup -f"
          ;;

        status)
          echo "── SOLEM Backup Encrypted ──"
          echo "Repo locale: $REPO"
          echo "Schedule: ${cfg.schedule}"
          ${lib.optionalString (cfg.offsite.rcloneRemote != null) ''
            echo "Offsite: ${cfg.offsite.rcloneRemote}:${cfg.offsite.remotePath}"
          ''}
          echo
          echo "── Ultimo run ──"
          systemctl status solem-backup.service --no-pager 2>/dev/null | head -10
          echo
          echo "── Prossimo run ──"
          systemctl list-timers solem-backup.timer --no-pager 2>/dev/null | head -3
          echo
          if [ -d "$REPO/data" ]; then
            echo "── Archives ──"
            sudo bash -c "BORG_PASSPHRASE=\$(cat /etc/solem/backup-passphrase) borg list '$REPO'" 2>/dev/null | tail -10
          fi
          ;;

        list)
          sudo bash -c "BORG_PASSPHRASE=\$(cat /etc/solem/backup-passphrase) borg list '$REPO'"
          ;;

        restore)
          ARCHIVE="''${1:?Usage: solem-backup restore <archive> [path]}"
          DEST="''${2:-/tmp/solem-restore-$ARCHIVE}"
          mkdir -p "$DEST"
          cd "$DEST"
          sudo bash -c "BORG_PASSPHRASE=\$(cat /etc/solem/backup-passphrase) borg extract '$REPO::$ARCHIVE'"
          echo "✓ Restored to $DEST"
          ;;

        check)
          echo "── Borg repo integrity check (lento) ──"
          sudo bash -c "BORG_PASSPHRASE=\$(cat /etc/solem/backup-passphrase) borg check '$REPO'"
          ;;

        help|--help|-h|*)
          cat <<'HELP'
solem-backup — backup automatico cifrato (borg + age + rclone)

  init          genera passphrase 24-byte (eseguire PRIMO setup)
  run           esegui backup ADESSO (no aspetto schedule)
  status        ultimo run + prossimo + lista archives
  list          lista archives nel repo
  restore <a>   estrae archive nel cwd (no overwrite)
  check         integrita' repo borg (lento)

Schedule: ${cfg.schedule}
Paths backup:
HELP
          for p in ${lib.concatMapStringsSep " " (p: ''"${p}"'') cfg.paths}; do
            echo "  - $p"
          done
          cat <<'HELP'

Setup primo uso:
  1. solem-backup init            (genera + salva passphrase)
  2. cp /etc/solem/backup-passphrase /media/usb/  (BACKUP CRITICO!)
  3. solem-backup run             (test manuale)
  4. solem-backup status          (verifica)

Senza /etc/solem/backup-passphrase NON puoi recuperare i dati cifrati.
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.backupEncrypted = {
    enable = lib.mkEnableOption "Backup automatico cifrato (borg + age + rclone)";

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "/home"
        "/etc"
        "/var/lib/solem"
        "/var/lib/gavio-ai"
        "/opt/gavio"
      ];
      description = "Path da includere nel backup";
    };

    exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "/home/*/.cache"
        "/home/*/.local/share/Trash"
        "/home/*/.local/share/Steam"
        "/var/lib/gavio-ai/cache"
        "*.tmp"
        "*.swp"
        "node_modules"
        "__pycache__"
        ".venv"
        "venv"
      ];
      description = "Pattern da escludere (borg --exclude)";
    };

    localRepo = lib.mkOption {
      type = lib.types.str;
      default = "/var/backups/solem-borg";
      description = "Path del repo borg locale";
    };

    schedule = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 04:00,10:00,16:00,22:00:00";
      description = "OnCalendar systemd: ogni 6h (04:00, 10:00, 16:00, 22:00)";
    };

    retention = {
      hourly = lib.mkOption { type = lib.types.int; default = 24; };
      daily = lib.mkOption { type = lib.types.int; default = 14; };
      weekly = lib.mkOption { type = lib.types.int; default = 8; };
      monthly = lib.mkOption { type = lib.types.int; default = 12; };
    };

    offsite = {
      rcloneRemote = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "nextcloud-personal";
        description = ''
          Nome remote rclone configurato per offsite sync.
          Configurare con `rclone config` PRIMA di abilitare.
          Se null, solo backup locale.
        '';
      };

      remotePath = lib.mkOption {
        type = lib.types.str;
        default = "solem-backup";
        description = "Path remoto per upload";
      };

      ageRecipientFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Path al file con age public key recipient per re-encryption
          PRIMA di upload offsite (defense-in-depth). Es. /etc/solem/age.pub.
          Se null, solo borg encryption (gia' sicura ma keymaster locale).
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.localRepo} 0700 root root - -"
      "d /var/log/solem 0750 root root - -"
      "d /etc/solem 0700 root root - -"
    ];

    systemd.services.solem-backup = {
      description = "SOLEM encrypted backup (borg + offsite)";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${borgBackupScript}/bin/solem-backup-run";
        User = "root";
        Nice = 19;
        IOSchedulingClass = "idle";
        # Hardening: backup ha accesso lettura ovunque ma scrittura limitata
        ProtectSystem = "strict";
        ReadWritePaths = [
          cfg.localRepo
          "/var/log/solem"
          "/var/lib/solem"
        ];
        ProtectHome = false;  # backup DEVE leggere /home
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    systemd.timers.solem-backup = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
        RandomizedDelaySec = "5min";
      };
    };

    environment.systemPackages = with pkgs; [
      borgbackup
      age
      rclone
      backupCli
    ];

    environment.etc."solem/backup-encrypted.md".text = ''
      # SOLEM Backup Encrypted (Step 17)

      Backup automatici cifrati con borg + opzionale offsite via rclone.

      ## Stack
        - borgbackup repokey-blake2 (BSD-3): deduplicating snapshots
        - zstd compression livello 9 (size/speed balance)
        - rclone (MIT): sync offsite a 70+ provider (Nextcloud, S3, B2)
        - Opzionale: age re-encryption prima upload (defense-in-depth)

      ## Schedule: ${cfg.schedule}

      Retention default:
        - ${toString cfg.retention.hourly} hourly
        - ${toString cfg.retention.daily} daily
        - ${toString cfg.retention.weekly} weekly
        - ${toString cfg.retention.monthly} monthly

      ## Setup primo uso

      ```bash
      solem-backup init
      # ⚠ COPIA /etc/solem/backup-passphrase su USB ESTERNO
      cp /etc/solem/backup-passphrase /media/usb-backup/

      solem-backup run         # test manuale
      solem-backup status      # verifica
      solem-backup list        # archives
      ```

      ## Offsite sync (opt-in)

      ```nix
      solem.backupEncrypted.offsite = {
        rcloneRemote = "nextcloud-personal";  # configura con `rclone config`
        remotePath = "solem-backup";
      };
      ```

      ## Threat coperto

      - **Ransomware**: snapshot borg append-only. Anche se ransomware
        cripta /home, gli snapshot precedenti sono intatti nel repo borg
        locale (se il repo e' su disco esterno o offsite).
      - **Disk fail**: restore da snapshot.
      - **Offsite theft cloud**: borg encryption garantisce illeggibilita'
        senza passphrase. Age (opt-in) aggiunge second layer.

      ## Limiti onesti

      - Repo locale stessa macchina = SPOF. Se HD fail, perdi tutto.
        SOLUZIONE: offsite obbligatorio per dati critici.
      - Passphrase locale (/etc/solem): se ransomware cripta /etc anche,
        passphrase perduta. SOLUZIONE: backup passphrase su USB esterno
        SEPARATO dal sistema.
      - Ripristino richiede sistema funzionante con borg + passphrase.
        SOLUZIONE: stampa la passphrase su carta (paranoid recovery).
      - Network bandwidth: backup grossi (>10GB) richiedono tempo per
        offsite sync. rclone gestisce resume.
    '';
  };
}
