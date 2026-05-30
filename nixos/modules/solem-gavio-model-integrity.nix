{ config, pkgs, lib, ... }:

# SOLEM GAVIO MODEL INTEGRITY — Step 20: verifica hash modelli Ollama.
#
# Single responsibility: SOLO verificare l'hash SHA256 dei modelli LLM
# scaricati in /var/lib/ollama/models prima che GAVIO li carichi.
#
# Threat coperto:
#   - Tampering modelli a riposo: attacker con accesso fs modifica weight
#     files. GAVIO caricherebbe modello compromesso (es. backdoor LLM:
#     risponde normalmente MA su trigger specifico esegue payload).
#   - Supply chain attack su Ollama registry: modello scaricato malicious.
#   - Tampering metadata manifest: modifica del manifest punta a sha
#     diverso → blob malicious sostituito.
#
# Approccio:
#   1. systemd-timer ogni ora calcola sha256 dei file in /var/lib/ollama/
#   2. Compara con manifest "expected hash" in /etc/solem/model-hashes.json
#   3. Se mismatch: ALERT + kill ollama + notify utente
#
# Workflow:
#   - Setup: dopo primo download, esegui `solem-model-integrity snapshot`
#     per salvare hash baseline.
#   - Runtime: timer verifica + alert se mismatch.
#   - Update modello: snapshot di nuovo.
#
# Tutto FOSS (coreutils sha256sum + jq).

let
  cfg = config.solem.gavioModelIntegrity;

  checkScript = pkgs.writeShellApplication {
    name = "solem-model-integrity-check";
    runtimeInputs = with pkgs; [ coreutils jq systemd libnotify findutils ];
    text = ''
      set -eu
      HASH_FILE="${cfg.hashFile}"
      MODEL_DIR="${cfg.modelDir}"
      LOG="/var/log/solem/model-integrity.log"
      mkdir -p "$(dirname "$LOG")"

      log() { echo "[$(date -Iseconds)] $*" | tee -a "$LOG" >&2; }

      if [ ! -f "$HASH_FILE" ]; then
        log "WARN: $HASH_FILE non esiste. Esegui: solem-model-integrity snapshot"
        exit 0
      fi

      log "── Model integrity check START ──"
      MISMATCH=0
      MISSING=0
      TOTAL=0

      while IFS=$'\t' read -r file expected; do
        TOTAL=$((TOTAL + 1))
        if [ ! -f "$file" ]; then
          log "MISSING: $file"
          MISSING=$((MISSING + 1))
          continue
        fi
        actual=$(sha256sum "$file" | awk '{print $1}')
        if [ "$actual" != "$expected" ]; then
          log "MISMATCH: $file expected=$expected actual=$actual"
          MISMATCH=$((MISMATCH + 1))
        fi
      done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' "$HASH_FILE")

      log "Total=$TOTAL Mismatch=$MISMATCH Missing=$MISSING"

      if [ "$MISMATCH" -gt 0 ]; then
        log "ALERT: tampering rilevato. Kill ollama + notify."
        systemctl stop ollama.service 2>&1 || true

        # Notify desktop users
        for D in /run/user/*; do
          [ -d "$D" ] || continue
          U=$(basename "$D")
          sudo -u "#$U" DBUS_SESSION_BUS_ADDRESS="unix:path=$D/bus" \
            notify-send -u critical -t 60000 \
            "SOLEM ALERT" \
            "GAVIO Model Integrity FAIL: $MISMATCH file modificati. Ollama stopped." 2>/dev/null || true
        done

        # Marker per blocco riavvio
        echo "$(date -Iseconds) $MISMATCH file tampered" > /var/lib/solem/MODEL_TAMPERED
        exit 1
      fi
      log "── Check OK ──"
    '';
  };

  cliApp = pkgs.writeShellApplication {
    name = "solem-model-integrity";
    runtimeInputs = with pkgs; [ coreutils jq findutils ];
    text = ''
      ACTION="''${1:-status}"
      HASH_FILE="${cfg.hashFile}"
      MODEL_DIR="${cfg.modelDir}"

      case "$ACTION" in
        snapshot)
          echo "── Snapshot model hash baseline ──"
          if [ ! -d "$MODEL_DIR" ]; then
            echo "ERROR: $MODEL_DIR non esiste. Installa Ollama prima."
            exit 1
          fi
          sudo mkdir -p "$(dirname "$HASH_FILE")"

          # Trova tutti i blob .bin / .gguf / sha256-* in MODEL_DIR
          # Ollama 0.x usa /var/lib/ollama/models/blobs/sha256-*
          TMPFILE=$(mktemp)
          {
            echo "{"
            FIRST=1
            while IFS= read -r f; do
              [ "$FIRST" -eq 1 ] || echo ","
              FIRST=0
              hash=$(sudo sha256sum "$f" | awk '{print $1}')
              printf '  %s: %s' \
                "$(jq -n --arg p "$f" '$p')" \
                "$(jq -n --arg h "$hash" '$h')"
            done < <(sudo find "$MODEL_DIR" -type f \( -name "sha256-*" -o -name "*.gguf" -o -name "*.bin" \) 2>/dev/null)
            echo
            echo "}"
          } > "$TMPFILE"

          sudo mv "$TMPFILE" "$HASH_FILE"
          sudo chmod 644 "$HASH_FILE"
          COUNT=$(jq 'length' "$HASH_FILE")
          echo "✓ $COUNT model file hashed in $HASH_FILE"
          ;;

        check|verify)
          echo "Esecuzione check..."
          sudo ${checkScript}/bin/solem-model-integrity-check
          ;;

        status)
          echo "── SOLEM Model Integrity ──"
          if [ -f "$HASH_FILE" ]; then
            COUNT=$(jq 'length' "$HASH_FILE")
            echo "Baseline: $COUNT modelli registrati ($HASH_FILE)"
            echo "Modified: $(date -r "$HASH_FILE" 2>/dev/null)"
          else
            echo "Baseline: NON configurato"
            echo "Setup: solem-model-integrity snapshot"
          fi
          echo
          echo "── Timer status ──"
          systemctl status solem-model-integrity.timer --no-pager 2>/dev/null | head -8 || echo "(timer spento)"
          echo
          if [ -f /var/lib/solem/MODEL_TAMPERED ]; then
            echo "⚠⚠ MODEL TAMPERED — ollama stopped ⚠⚠"
            cat /var/lib/solem/MODEL_TAMPERED
            echo "Reset: solem-model-integrity reset"
          fi
          ;;

        log)
          sudo tail -30 /var/log/solem/model-integrity.log 2>/dev/null || echo "(no log)"
          ;;

        reset)
          echo "ATTENZIONE: rimuovi marker tamper. Solo dopo investigazione."
          read -r -p "Confermi? (digita YES): " ANS
          if [ "$ANS" = "YES" ]; then
            sudo rm -f /var/lib/solem/MODEL_TAMPERED
            sudo systemctl start ollama 2>/dev/null
            echo "✓ Reset done."
          fi
          ;;

        help|--help|-h|*)
          cat <<'HELP'
solem-model-integrity — verifica hash modelli LLM (Ollama)

  snapshot      genera baseline hash da modelli attualmente installati
  check         esegui verify ADESSO (no aspetto timer)
  status        baseline + timer + marker tamper
  log           ultimi 30 eventi
  reset         rimuove marker tamper (dopo investigazione!)

Workflow:
  1. Installa modelli con `ollama pull <model>`
  2. solem-model-integrity snapshot     (PRIMO setup)
  3. Timer auto verifica ogni ora.
  4. Se MISMATCH: ollama killed + notify + marker.
  5. Update modello? Snapshot di nuovo dopo update.

Threat coperto: tampering weight files at-rest, backdoor LLM,
supply chain compromesso registry Ollama.
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.gavioModelIntegrity = {
    enable = lib.mkEnableOption "Hash verify dei modelli Ollama (anti-tampering)";

    modelDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/ollama/models";
      description = "Directory dei modelli Ollama";
    };

    hashFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/solem/model-hashes.json";
      description = "File JSON con mapping file→hash baseline";
    };

    schedule = lib.mkOption {
      type = lib.types.str;
      default = "hourly";
      description = "OnCalendar systemd: frequenza check";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d /var/log/solem 0750 root root - -"
      "d /var/lib/solem 0750 root root - -"
      "d /etc/solem 0755 root root - -"
    ];

    systemd.services.solem-model-integrity = {
      description = "SOLEM: verify hash dei modelli LLM (Ollama)";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${checkScript}/bin/solem-model-integrity-check";
        User = "root";
        Nice = 19;
        IOSchedulingClass = "idle";
      };
    };

    systemd.timers.solem-model-integrity = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
        RandomizedDelaySec = "5min";
      };
    };

    environment.systemPackages = [ cliApp ];

    environment.etc."solem/gavio-model-integrity.md".text = ''
      # SOLEM GAVIO Model Integrity

      Verifica hash SHA256 dei modelli LLM (Ollama) per detect tampering.

      ## Threat coperto
      - **At-rest tampering**: attaccante con fs access modifica weight files
        di un modello (backdoor LLM: comportamento normale tranne trigger).
      - **Supply chain Ollama registry**: blob malicious scaricato.
      - **Manifest tampering**: hash atteso modificato (non protetto
        completamente; serve verifica firma upstream — TODO).

      ## Workflow
      ```bash
      ollama pull llama3.2:3b              # installa modello
      solem-model-integrity snapshot        # PRIMO setup
      solem-model-integrity status          # verifica baseline
      # Timer auto check ogni ${cfg.schedule}
      ```

      ## Limiti onesti
      - Snapshot iniziale assume sistema NON gia' compromesso. Se il primo
        download era gia' malicious, baseline = malicious. SOLUZIONE:
        verifica hash con upstream Ollama (richiede signed releases — TODO).
      - Modello update richiede nuovo snapshot manuale.
      - Non protegge da prompt injection runtime (vedi Step 21).
      - Non protegge da LLM jailbreak (vedi solem-ai-guardrails layer).
    '';
  };
}
