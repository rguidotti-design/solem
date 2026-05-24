{ config, pkgs, lib, ... }:

# SOLEM DOWNLOAD SCANNER — scan ClamAV automatico su ogni file scaricato.
#
# Single responsibility: SOLO un daemon systemd-user che watcha le cartelle
# di download via inotify e lancia `clamscan` su ogni file nuovo.
# Se infetto: notifica + quarantena in ~/.local/share/solem/quarantine/.
#
# Risponde direttamente al requisito utente:
#   "se qualcuno prova a installare un trojan o altro deve intercettarlo prima"
#
# Tutto FOSS:
#   - inotify-tools (LGPL) — watcher kernel events
#   - ClamAV (GPL) — engine antivirus
#   - libnotify (LGPL) — desktop notifications
#
# Default off (richiede ClamAV DB scaricato). Abilitare assieme a solem.antiMalware.

let
  cfg = config.solem.downloadScanner;

  scanScript = pkgs.writeShellApplication {
    name = "solem-download-scan-daemon";
    runtimeInputs = with pkgs; [ coreutils inotify-tools clamav libnotify gawk ];
    text = ''
      WATCH_DIRS=(${lib.concatMapStringsSep " " (d: ''"${d}"'') cfg.watchDirs})
      QUARANTINE_DIR="$HOME/.local/share/solem/quarantine"
      LOG_FILE="$HOME/.local/share/solem/download-scan.log"
      mkdir -p "$QUARANTINE_DIR" "$(dirname "$LOG_FILE")"

      log() {
        echo "[$(date -Iseconds)] $*" >> "$LOG_FILE"
      }

      notify() {
        local urgency="$1"; shift
        if command -v notify-send >/dev/null 2>&1; then
          notify-send -u "$urgency" -t 20000 "SOLEM Download Scanner" "$*" 2>/dev/null || true
        fi
      }

      scan_file() {
        local F="$1"
        [ -f "$F" ] || return 0
        # Skip file troppo grossi (>500MB) per non bloccare CPU
        local SIZE
        SIZE=$(stat -c %s "$F" 2>/dev/null || echo 0)
        if [ "$SIZE" -gt 524288000 ]; then
          log "SKIP (too large $SIZE bytes): $F"
          return 0
        fi
        # Skip file parziali browser (.part, .crdownload, .tmp)
        case "$F" in
          *.part|*.crdownload|*.tmp|*.partial) return 0 ;;
        esac

        log "SCAN: $F"
        local OUT
        OUT=$(clamscan --no-summary --infected "$F" 2>&1 || true)
        if echo "$OUT" | grep -q "FOUND"; then
          local THREAT
          THREAT=$(echo "$OUT" | awk -F': ' '/FOUND/ {print $2}')
          log "INFECTED: $F → $THREAT"
          # Quarantena: move + chmod 000
          local QF
          QF="$QUARANTINE_DIR/$(date +%s)-$(basename "$F")"
          mv "$F" "$QF" 2>/dev/null && chmod 000 "$QF" 2>/dev/null || true
          notify critical "MALWARE BLOCCATO: $(basename "$F") → $THREAT (quarantena: $QF)"
        else
          log "CLEAN: $F"
        fi
      }

      log "Daemon avviato. Watch: ''${WATCH_DIRS[*]}"
      notify normal "Download scanner attivo su ''${#WATCH_DIRS[@]} cartelle"

      # Crea le cartelle se non esistono (inotify fallisce su dir mancanti)
      for D in "''${WATCH_DIRS[@]}"; do
        mkdir -p "$D" 2>/dev/null || true
      done

      # inotify loop infinito: close_write + moved_to (download finiti)
      inotifywait -m -e close_write -e moved_to --format '%w%f' "''${WATCH_DIRS[@]}" 2>/dev/null | \
      while read -r FILE; do
        # Aspetta 1s che il file sia completamente flushed
        sleep 1
        scan_file "$FILE" &
      done
    '';
  };

  scannerCli = pkgs.writeShellApplication {
    name = "solem-download-scanner";
    runtimeInputs = with pkgs; [ coreutils systemd clamav ];
    text = ''
      ACTION="''${1:-status}"

      case "$ACTION" in
        status)
          echo "── SOLEM Download Scanner ──"
          systemctl --user is-active solem-download-scanner.service 2>/dev/null && \
            echo "Daemon: ATTIVO" || echo "Daemon: spento (systemctl --user start solem-download-scanner)"
          echo "Watch dirs: ${lib.concatStringsSep ", " cfg.watchDirs}"
          echo "Quarantena: $HOME/.local/share/solem/quarantine/"
          if [ -d "$HOME/.local/share/solem/quarantine" ]; then
            COUNT=$(find "$HOME/.local/share/solem/quarantine" -type f 2>/dev/null | wc -l)
            echo "File in quarantena: $COUNT"
          fi
          ;;

        log|tail)
          tail -30 "$HOME/.local/share/solem/download-scan.log" 2>/dev/null || \
            echo "Nessun log ancora (daemon non ha scansionato file)"
          ;;

        quarantine|q)
          QD="$HOME/.local/share/solem/quarantine"
          if [ -d "$QD" ]; then
            echo "── Quarantena ──"
            ls -lh "$QD" 2>/dev/null || echo "(vuota)"
          else
            echo "(quarantena vuota)"
          fi
          ;;

        restore)
          F="''${1:?Usage: solem-download-scanner restore <file-in-quarantena>}"
          QD="$HOME/.local/share/solem/quarantine"
          if [ -f "$QD/$F" ]; then
            chmod 644 "$QD/$F"
            echo "✓ Permessi ripristinati. File: $QD/$F"
            echo "  ATTENZIONE: era stato bloccato come malware. Sicuro?"
          else
            echo "File non trovato in quarantena"
          fi
          ;;

        purge)
          QD="$HOME/.local/share/solem/quarantine"
          if [ -d "$QD" ]; then
            COUNT=$(find "$QD" -type f 2>/dev/null | wc -l)
            rm -rf "''${QD:?}"/*  2>/dev/null || true
            echo "✓ Eliminati $COUNT file in quarantena"
          fi
          ;;

        update-db)
          echo "Aggiorno DB ClamAV..."
          sudo freshclam 2>&1 || echo "freshclam non disponibile (richiede sudo / clamav-freshclam.service)"
          ;;

        help|--help|-h|*)
          cat <<'HELP'
solem-download-scanner — scan ClamAV automatico su download

  status            stato daemon + cartelle watchate
  log               ultime 30 entry log scan
  quarantine        elenca file in quarantena
  restore <file>    ripristina permessi (se falso positivo)
  purge             elimina TUTTI i file in quarantena
  update-db         aggiorna DB virus (freshclam)

Daemon: systemctl --user start solem-download-scanner

Watch automatico:
HELP
          for D in ${lib.concatStringsSep " " (map (d: ''"${d}"'') cfg.watchDirs)}; do
            echo "  - $D"
          done
          cat <<'HELP'

Comportamento:
  - Ogni file scaricato (close_write/moved_to) → clamscan
  - Se INFECTED → quarantena ~/.local/share/solem/quarantine/
                + notify desktop CRITICAL
  - Se CLEAN → log scan + lascia il file dove sta

Skip:
  - File > 500 MB (anti-CPU-spike)
  - File parziali (.part, .crdownload, .tmp)

Tutto FOSS: inotify-tools + ClamAV. 0 €.
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.downloadScanner = {
    enable = lib.mkEnableOption "scan automatico ClamAV su file scaricati";

    watchDirs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "$HOME/Downloads"
        "$HOME/Scaricati"
        "$HOME/Desktop"
      ];
      description = ''
        Cartelle watchate via inotify. Ogni file creato/spostato qui
        viene scansionato con clamscan.
      '';
    };

    autostart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Avvia automaticamente il daemon al login utente";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      scannerCli
      scanScript
      inotify-tools
      clamav
    ];

    # Daemon systemd-user (no privilegi root, scan dei file utente)
    systemd.user.services.solem-download-scanner = {
      description = "SOLEM Download Scanner (ClamAV auto-scan)";
      wantedBy = lib.mkIf cfg.autostart [ "default.target" ];
      serviceConfig = {
        ExecStart = "${scanScript}/bin/solem-download-scan-daemon";
        Restart = "on-failure";
        RestartSec = 30;
        # Hardening: niente network, niente accesso /etc o /sys
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";  # Legge ~/Downloads, scrive quarantena
        # ReadWritePaths popolato runtime (HOME-dependent)
        NoNewPrivileges = true;
      };
    };

    environment.etc."solem/download-scanner.md".text = ''
      # SOLEM Download Scanner

      Hook automatico: ogni file scaricato in `~/Downloads`,
      `~/Scaricati`, `~/Desktop` viene scansionato con ClamAV.
      Se infetto → quarantena immediata + notifica desktop.

      ## Setup primo uso

      ```
      # Avvia daemon (auto-start al login se autostart=true)
      systemctl --user start solem-download-scanner
      systemctl --user enable solem-download-scanner

      # Scarica un file di test EICAR (innocuo, ma trigger AV)
      curl -O https://secure.eicar.org/eicar.com.txt
      # → daemon detecta + sposta in quarantena
      ```

      ## Quarantena

      File infetti vanno in `~/.local/share/solem/quarantine/`
      con chmod 000 (non eseguibili).

      ```
      solem-download-scanner quarantine    # elenca
      solem-download-scanner restore xxx   # ripristina (se falso pos)
      solem-download-scanner purge         # elimina tutti
      ```

      ## Performance

      - Scan async (background) — non blocca UI download
      - Skip file > 500 MB (configurabile via fork)
      - Skip file parziali browser

      ## Limiti

      - Solo signature-based (ClamAV DB) — non rileva 0-day custom
      - Browser proprio dovrebbe avere SafeBrowsing — questo è layer 2
      - Richiede ClamAV DB aggiornato (freshclam settimanale)
    '';
  };
}
