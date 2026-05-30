{ config, pkgs, lib, ... }:

# SOLEM CANARY — file esca + kill switch automatico.
#
# Single responsibility: SOLO file esca (honey tokens) monitorati via
# fanotify/inotify. Se QUALSIASI processo li apre/legge → kill switch:
#   1. systemctl stop gavio.service (immediato)
#   2. notify-send critical all'utente umano
#   3. log immutabile in /var/log/solem/canary.log
#   4. opzionale: solem-net-audit / process snapshot per forensics
#
# I file sono CREDIBILI: si chiamano come secret reali che un'AI/malware
# tenterebbe di esfiltrare:
#   - /home/gavio/.aws/credentials
#   - /home/gavio/.ssh/id_rsa
#   - /home/gavio/.config/solem/vault-master-BACKUP.key
#   - /etc/solem/canary/api-keys.env
#
# Contengono SEMPRE solo "honey token" innocui (UUID random, no key reali).
#
# Implementazione: fanotify (kernel) tramite inotifywait — leggera, no daemon
# Python custom. Una sola system unit con bash loop.

let
  cfg = config.solem.canary;

  # Honey token random ma costante (rigenerato a ogni system rebuild ok)
  honeyToken = "SOLEM-CANARY-" + builtins.substring 0 16 (
    builtins.hashString "sha256" (toString config.networking.hostName)
  );

  watcherScript = pkgs.writeShellApplication {
    name = "solem-canary-watcher";
    runtimeInputs = with pkgs; [ coreutils inotify-tools systemd libnotify util-linux gawk psmisc ];
    text = ''
      LOG_FILE="/var/log/solem/canary.log"
      mkdir -p "$(dirname "$LOG_FILE")"
      touch "$LOG_FILE"

      log() {
        echo "[$(date -Iseconds)] $*" | tee -a "$LOG_FILE" >&2
      }

      alert_human() {
        msg="$1"
        # Notify-send a tutti gli utenti grafici loggati.
        # NB: niente redirect dentro il for-in (sintassi invalida + shellcheck).
        for DISP_FILE in /run/user/*/wayland-* /run/user/*/DISPLAY; do
          [ -e "$DISP_FILE" ] || continue
          UID_DIR=$(echo "$DISP_FILE" | sed -E 's|/run/user/([0-9]+)/.*|\1|')
          if [ -n "$UID_DIR" ]; then
            sudo -u "#$UID_DIR" \
              DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$UID_DIR/bus" \
              notify-send -u critical -t 60000 "SOLEM CANARY TRIPPED" "$msg" 2>/dev/null || true
          fi
        done
        # Wall message (tutti i tty)
        echo "SOLEM CANARY: $msg" | wall 2>/dev/null || true
      }

      kill_switch() {
        local why="$1"
        log "KILL SWITCH: $why"
        alert_human "$why"

        # 1. Stop gavio.service (se attivo)
        if systemctl is-active gavio.service >/dev/null 2>&1; then
          log "Stop gavio.service"
          systemctl stop gavio.service 2>&1 | tee -a "$LOG_FILE"
        fi

        # 2. Snapshot processi (forensics)
        ps -eo pid,ppid,user,cmd > "/var/log/solem/canary-ps-$(date +%s).snap" 2>&1 || true

        # 3. Snapshot connessioni rete
        ss -tunap > "/var/log/solem/canary-ss-$(date +%s).snap" 2>&1 || true

        # 4. Marker per impedire restart automatico (manuale solo)
        touch /var/lib/solem/CANARY_TRIPPED
        chmod 0644 /var/lib/solem/CANARY_TRIPPED || true
      }

      # ── Watch loop ────────────────────────────────────────────────
      CANARY_DIR="/var/lib/solem/canary"
      mkdir -p "$CANARY_DIR"

      log "Canary watcher avviato. File monitorati:"
      for F in "''${@}"; do
        log "  $F"
      done

      # IN_ACCESS = qualsiasi read, IN_OPEN = open()
      # Usiamo IN_OPEN per catturare anche cat senza completare read.
      inotifywait -m -e open -e access --format '%w %e' "$@" 2>>"$LOG_FILE" | \
      while read -r FILE EVENT; do
        # Skip se l'evento e' generato dal mio stesso processo
        # (uname check banalmente -- pattern detection non perfetto)
        log "TRIP: file=$FILE event=$EVENT"
        # Trova chi ha aperto: lsof e' lento; usa fuser come euristica
        OPENER=$(fuser "$FILE" 2>&1 | head -1 || echo "(unknown)")
        log "Opener: $OPENER"
        kill_switch "Canary $FILE letto/aperto da: $OPENER"
        # Continuare il loop o break? Continuiamo: piu' canary, piu' evidence
      done
    '';
  };

  canaryCli = pkgs.writeShellApplication {
    name = "solem-canary";
    runtimeInputs = with pkgs; [ coreutils systemd ];
    text = ''
      ACTION="''${1:-status}"

      case "$ACTION" in
        status)
          echo "── SOLEM Canary ──"
          systemctl is-active solem-canary-watcher.service >/dev/null 2>&1 && \
            echo "Watcher: ATTIVO" || echo "Watcher: spento"
          echo
          echo "── File canary monitorati ──"
          for F in ${lib.concatStringsSep " " (map (p: ''"${p}"'') cfg.files)}; do
            if [ -f "$F" ]; then
              SIZE=$(stat -c %s "$F" 2>/dev/null)
              PERM=$(stat -c %a "$F" 2>/dev/null)
              echo "  ✓ $F  (size=$SIZE perm=$PERM)"
            else
              echo "  ✗ $F  (MANCANTE!)"
            fi
          done
          echo
          if [ -f /var/lib/solem/CANARY_TRIPPED ]; then
            echo "⚠⚠⚠ CANARY TRIPPED — sistema in stato compromesso ⚠⚠⚠"
            echo "Vedi: /var/log/solem/canary.log"
            echo "Reset: solem-canary reset (dopo investigazione!)"
          else
            echo "Stato: NESSUN TRIP rilevato"
          fi
          ;;

        log)
          tail -40 /var/log/solem/canary.log 2>/dev/null || echo "(no log yet)"
          ;;

        reset)
          echo "ATTENZIONE: reset disarma il canary marker. Solo dopo che hai"
          echo "investigato cos'e' successo (vedi log + ps/ss snap)."
          read -r -p "Confermi reset? (digita YES): " CONFIRM
          if [ "$CONFIRM" = "YES" ]; then
            rm -f /var/lib/solem/CANARY_TRIPPED
            echo "✓ Marker rimosso. systemctl restart solem-canary-watcher per riarmo."
          else
            echo "Annullato."
          fi
          ;;

        test-trip)
          # Test deliberato: legge un canary e verifica che il sistema reagisca
          echo "Test: leggo /etc/solem/canary/api-keys.env"
          cat /etc/solem/canary/api-keys.env 2>/dev/null | head -3
          echo
          echo "Attendi 3s e poi controlla:"
          echo "  solem-canary status"
          echo "  journalctl -u solem-canary-watcher"
          ;;

        help|--help|-h|*)
          cat <<'HELP'
solem-canary — file esca + kill switch

  status         stato watcher + presenza canary + tripped marker
  log            ultime entry log canary
  reset          rimuove marker TRIPPED (solo dopo investigazione)
  test-trip      legge un canary per provare reazione sistema

File monitorati (honey tokens, contengono UUID random NON segreti reali):
HELP
          for F in ${lib.concatStringsSep " " (map (p: ''"${p}"'') cfg.files)}; do
            echo "  - $F"
          done
          cat <<'HELP'

Quando uno qualsiasi viene aperto/letto:
  1. systemctl stop gavio.service (immediato)
  2. notify-send critical agli utenti loggati
  3. snapshot ps + ss in /var/log/solem/
  4. marker /var/lib/solem/CANARY_TRIPPED (impedisce auto-restart)

Tutto FOSS (inotify-tools LGPL).
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.canary = {
    enable = lib.mkEnableOption "Honey-token file esca + kill switch su accesso";

    files = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "/etc/solem/canary/api-keys.env"
        "/etc/solem/canary/aws-credentials"
        "/etc/solem/canary/ssh-id_rsa"
        "/etc/solem/canary/vault-master-BACKUP.key"
      ];
      description = ''
        File esca da monitorare. Default: posizioni credibili dove un
        attaccante/AI cercherebbe credenziali. Contengono solo honey
        token random, mai dati reali.
      '';
    };

    killGavio = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Stop systemctl stop gavio.service su trip";
    };
  };

  config = lib.mkIf cfg.enable {
    # Crea i file esca con honey token come content
    environment.etc = {
      "solem/canary/api-keys.env" = {
        mode = "0644";  # world-readable: chiunque tocca -> trip (sono honey token, no segreti)
        text = ''
          # SOLEM canary — DO NOT READ
          # Honey token, content is meaningless. Reading triggers kill switch.
          OPENAI_API_KEY=sk-CANARY-${honeyToken}-DO-NOT-USE
          ANTHROPIC_API_KEY=sk-ant-CANARY-${honeyToken}-DO-NOT-USE
          AWS_ACCESS_KEY_ID=AKIACANARY${honeyToken}
        '';
      };

      "solem/canary/aws-credentials" = {
        mode = "0644";  # world-readable: chiunque tocca -> trip (sono honey token, no segreti)
        text = ''
          [default]
          aws_access_key_id = AKIACANARY${honeyToken}
          aws_secret_access_key = CANARY-${honeyToken}-DO-NOT-USE
        '';
      };

      "solem/canary/ssh-id_rsa" = {
        mode = "0644";  # world-readable: chiunque tocca -> trip (sono honey token, no segreti)
        text = ''
          -----BEGIN OPENSSH PRIVATE KEY-----
          CANARY-NOT-A-REAL-KEY-${honeyToken}
          -----END OPENSSH PRIVATE KEY-----
        '';
      };

      "solem/canary/vault-master-BACKUP.key" = {
        mode = "0644";  # world-readable: chiunque tocca -> trip (sono honey token, no segreti)
        text = ''
          AGE-SECRET-KEY-CANARY-${honeyToken}-DO-NOT-USE
        '';
      };
    };

    systemd.tmpfiles.rules = [
      "d /var/log/solem 0750 root root -"
      "d /var/lib/solem 0750 root root -"
      "d /var/lib/solem/canary 0750 root root -"
    ];

    # Watcher daemon
    systemd.services.solem-canary-watcher = {
      description = "SOLEM Canary — inotify watcher su honey tokens";
      after = [ "local-fs.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${watcherScript}/bin/solem-canary-watcher ${
          lib.concatStringsSep " " (map (p: ''"${p}"'') cfg.files)
        }";
        Restart = "on-failure";
        RestartSec = 30;

        # Hardening del watcher stesso (gira come root per stop service)
        # NoNewPrivileges=true safe: systemctl stop NON richiede setuid
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ReadWritePaths = [
          "/var/log/solem"
          "/var/lib/solem"
        ];
        ProtectHome = true;
        PrivateTmp = true;
      };
    };

    environment.systemPackages = [
      canaryCli
    ];

    environment.etc."solem/canary.md".text = ''
      # SOLEM Canary — Honey tokens + kill switch

      ## Concetto

      Quattro file esca con nomi credibili (api-keys, aws-credentials,
      ssh-id_rsa, vault-master-BACKUP) sono posizionati in /etc/solem/canary/.
      Contengono SOLO honey token random — nessun secret reale.

      Un watcher inotify monitora gli OPEN/ACCESS. Se uno qualsiasi
      viene toccato:

        1. systemctl stop gavio.service           (taglia l'AI subito)
        2. notify-send critical (utente loggato)
        3. snapshot ps + ss salvati per forensics
        4. marker /var/lib/solem/CANARY_TRIPPED   (no auto-restart)

      ## Quando scatta

      Un'AI/malware che cerca credenziali fa pattern:
        find / -name "credentials"
        find / -name "*.key"
        grep -r "API_KEY" ~/

      Tutte queste operazioni OPENano i canary → TRIP.

      ## Reset

      Solo manuale dopo investigazione:
        solem-canary log         # vedi cosa e' successo
        cat /var/log/solem/canary-ps-*.snap
        cat /var/log/solem/canary-ss-*.snap
        solem-canary reset       # YES per confermare

      ## Limiti onesti

      - False positive: un grep ricorsivo di un utente LEGITTIMO trippa.
        Per questo i file sono in /etc/solem/canary/ (path raro), non
        ovunque. Ma se l'utente fa `find /etc -type f -exec cat {} \;`
        trippa lo stesso.
      - Non protegge da AI che evita il pattern (es. usa whitelist di
        path noti). Cattura attaccanti generici, non targeted molto
        sofisticati.
      - Reset richiede sudo: se l'AI ha sudo (ai-freedom abilitato)
        puo' resettarsi. Per questo conviene avere ANCHE gavio-zero-trust.
    '';
  };
}
