{ config, pkgs, lib, ... }:

let
  cfg = config.solem.supabaseBackup;

  backupScript = pkgs.writeShellScript "solem-supabase-backup" ''
    set -uo pipefail
    # NON usare 'set -e': vogliamo log dell'errore anche in caso di fail

    BACKUP_DIR="${cfg.outputDir}"
    mkdir -p "$BACKUP_DIR"
    chmod 0700 "$BACKUP_DIR"

    # Source env file con credenziali Supabase (NON committato in git)
    ENV_FILE="${cfg.envFile}"
    if [ ! -r "$ENV_FILE" ]; then
      echo "[supabase-backup] env file mancante: $ENV_FILE"
      echo "[supabase-backup] crea con: SUPABASE_DB_URL=postgresql://..."
      exit 0  # non fail hard — primo boot è OK senza credenziali
    fi
    # shellcheck source=/dev/null
    . "$ENV_FILE"

    if [ -z "''${SUPABASE_DB_URL:-}" ]; then
      echo "[supabase-backup] SUPABASE_DB_URL non settata, skip"
      exit 0
    fi

    TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
    OUT_BASE="$BACKUP_DIR/supabase-$TIMESTAMP"
    OUT_DUMP="$OUT_BASE.sql"
    OUT_COMPRESSED="$OUT_BASE.sql.zst"

    echo "[supabase-backup] dump → $OUT_COMPRESSED"

    # pg_dump custom format (più portabile) + zstd compress
    ${pkgs.postgresql_16}/bin/pg_dump \
      --no-owner \
      --no-acl \
      --format=plain \
      "$SUPABASE_DB_URL" > "$OUT_DUMP" 2>>"$BACKUP_DIR/backup.log"

    if [ ! -s "$OUT_DUMP" ]; then
      echo "[supabase-backup] dump vuoto/fallito (vedi $BACKUP_DIR/backup.log)"
      rm -f "$OUT_DUMP"
      exit 1
    fi

    ${pkgs.zstd}/bin/zstd -3 --rm "$OUT_DUMP" -o "$OUT_COMPRESSED"
    chmod 0600 "$OUT_COMPRESSED"

    # Retention: tieni ultimi N backup (default 12 = ~3 mesi settimanali)
    ls -1t "$BACKUP_DIR"/supabase-*.sql.zst 2>/dev/null \
      | tail -n +$((${toString cfg.retentionCount} + 1)) \
      | xargs -r rm -v

    echo "[supabase-backup] done. Backup esistenti:"
    ls -lh "$BACKUP_DIR"/supabase-*.sql.zst 2>/dev/null | tail -5
  '';
in {
  # ──────────────────────────────────────────────────────────────────────
  # SOLEM SUPABASE BACKUP — export pg_dump settimanale (ADR-004)
  # ──────────────────────────────────────────────────────────────────────
  # Esporta DB Supabase free tier → backup locale zstd.
  # Permette migrazione futura a self-host Postgres senza panic.
  # Strong default OFF — l'utente abilita con: solem.supabaseBackup.enable = true;

  options.solem.supabaseBackup = {
    enable = lib.mkEnableOption "Backup pg_dump settimanale di Supabase verso storage locale";

    schedule = lib.mkOption {
      type = lib.types.str;
      default = "weekly";
      description = "OnCalendar systemd (weekly default, oppure 'Mon 03:00').";
    };

    outputDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/backups/solem/supabase";
      description = "Directory dove salvare i dump (mode 0700).";
    };

    envFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/gavio/env";
      description = "Path env file con SUPABASE_DB_URL=postgresql://...";
    };

    retentionCount = lib.mkOption {
      type = lib.types.int;
      default = 12;
      description = "Numero backup da tenere (12 settimanali ≈ 3 mesi).";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.solem-supabase-backup = {
      description = "SOLEM — backup Supabase pg_dump settimanale (ADR-004)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = with pkgs; [ postgresql_16 zstd coreutils ];
      serviceConfig = {
        Type = "oneshot";
        User = "gavio";
        Group = "users";
        ExecStart = backupScript;
        Nice = 19;
        IOSchedulingClass = "idle";
        # Hardening basic
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ cfg.outputDir ];
        ProtectHome = "tmpfs";
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
      };
    };

    systemd.timers.solem-supabase-backup = {
      description = "SOLEM Supabase backup timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
        RandomizedDelaySec = "30m";
      };
    };

    # Directory backup pre-creata con permessi corretti
    systemd.tmpfiles.rules = [
      "d ${cfg.outputDir} 0700 gavio users -"
    ];

    # Aggiungi env example documentation
    environment.etc."solem/supabase-backup-config.json".text = builtins.toJSON {
      enabled = cfg.enable;
      schedule = cfg.schedule;
      output_dir = cfg.outputDir;
      retention_count = cfg.retentionCount;
      env_file = cfg.envFile;
      env_var_required = "SUPABASE_DB_URL=postgresql://user:pass@host:port/db";
      manual_trigger = "sudo systemctl start solem-supabase-backup.service";
      adr = "ADR-004";
    };
  };
}
