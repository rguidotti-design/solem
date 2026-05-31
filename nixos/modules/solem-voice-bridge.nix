{ config, pkgs, lib, ... }:

# SOLEM VOICE BRIDGE — Step 41: TTS + STT come Friday/JARVIS naturale.
#
# Single responsibility: SOLO orchestrazione voice in/out per SOLEM,
# bridge a GAVIO API per query naturali.
#
# Friday/JARVIS pattern:
#   - Premi hotkey (Super+Space) -> STT registra 5s -> testo
#   - Testo -> GAVIO API via prompt filter -> risposta
#   - Risposta -> TTS -> speaker
#   - Tutto LOCALE, no cloud (whisper.cpp + piper-tts)
#
# Stack FOSS:
#   - whisper.cpp (MIT): STT modello GGML, modello small ~250MB
#   - piper-tts (MIT): TTS neural fast, voci italiane disponibili
#   - sox: registrazione audio
#   - pw-cat: PipeWire audio playback
#
# 100% LOCALE — nessuna API esterna. 0 €.

let
  cfg = config.solem.voiceBridge;

  voiceScript = pkgs.writeShellApplication {
    name = "solem-voice";
    runtimeInputs = with pkgs; [ coreutils sox pipewire alsa-utils curl jq libnotify ];
    text = ''
      ACTION="''${1:-ask}"
      shift || true

      MODELS_DIR="${cfg.modelsDir}"
      WHISPER_MODEL="$MODELS_DIR/ggml-${cfg.whisperModel}.bin"
      PIPER_MODEL="$MODELS_DIR/${cfg.piperVoice}.onnx"
      PIPER_CONFIG="$MODELS_DIR/${cfg.piperVoice}.onnx.json"

      TMPDIR=$(mktemp -d)
      trap 'rm -rf "$TMPDIR"' EXIT

      check_models() {
        if [ ! -f "$WHISPER_MODEL" ]; then
          notify-send -u critical "SOLEM Voice" "Whisper model mancante: $WHISPER_MODEL — esegui: solem-voice download-models" 2>/dev/null || true
          echo "ERROR: $WHISPER_MODEL non trovato"
          echo "Esegui: solem-voice download-models"
          exit 1
        fi
        if [ ! -f "$PIPER_MODEL" ]; then
          notify-send -u critical "SOLEM Voice" "Piper voice mancante" 2>/dev/null || true
          echo "ERROR: $PIPER_MODEL non trovato"
          exit 1
        fi
      }

      case "$ACTION" in
        listen)
          # Registra N secondi mic + STT whisper.cpp
          check_models
          DUR="''${1:-5}"
          notify-send "SOLEM" "In ascolto $DUR sec..." 2>/dev/null || true
          rec -q -t wav -r 16000 -c 1 "$TMPDIR/in.wav" trim 0 "$DUR" 2>/dev/null
          # whisper.cpp via nix-shell o binary preinstallato
          TEXT=$(${pkgs.openai-whisper-cpp}/bin/whisper-cli \
            -m "$WHISPER_MODEL" \
            -f "$TMPDIR/in.wav" \
            -l ${cfg.language} \
            --no-timestamps 2>/dev/null | tail -1)
          echo "$TEXT"
          ;;

        speak|tts)
          # Text -> speech via piper
          check_models
          TEXT="''${1:-}"
          if [ -z "$TEXT" ]; then
            TEXT=$(cat)  # stdin
          fi
          echo "$TEXT" | ${pkgs.piper-tts}/bin/piper \
            --model "$PIPER_MODEL" \
            --config "$PIPER_CONFIG" \
            --output_file "$TMPDIR/out.wav" 2>/dev/null
          ${pkgs.pipewire}/bin/pw-cat -p "$TMPDIR/out.wav" 2>/dev/null
          ;;

        ask)
          # Workflow completo: listen -> GAVIO API -> speak
          notify-send "SOLEM" "Friday in ascolto..." 2>/dev/null || true

          # 1. STT
          rec -q -t wav -r 16000 -c 1 "$TMPDIR/in.wav" trim 0 "''${1:-5}" 2>/dev/null
          QUERY=$(${pkgs.openai-whisper-cpp}/bin/whisper-cli \
            -m "$WHISPER_MODEL" \
            -f "$TMPDIR/in.wav" \
            -l ${cfg.language} \
            --no-timestamps 2>/dev/null | tail -1 | xargs)

          if [ -z "$QUERY" ]; then
            echo "(no speech rilevato)"
            exit 1
          fi
          echo "Tu: $QUERY"
          notify-send "SOLEM Friday" "Hai detto: $QUERY" 2>/dev/null || true

          # 2. Bridge a GAVIO via prompt filter (Step 21)
          GAVIO_URL="${cfg.gavioEndpoint}"
          RESPONSE=$(curl -s --max-time 30 -X POST "$GAVIO_URL" \
            -H "Content-Type: application/json" \
            -d "{\"message\":$(echo "$QUERY" | jq -Rs .)}" 2>/dev/null | \
            jq -r '.response // .text // .message // "no response"' 2>/dev/null || echo "GAVIO non disponibile")

          echo "GAVIO: $RESPONSE"
          notify-send "GAVIO" "$RESPONSE" 2>/dev/null || true

          # 3. TTS risposta
          echo "$RESPONSE" | ${pkgs.piper-tts}/bin/piper \
            --model "$PIPER_MODEL" \
            --config "$PIPER_CONFIG" \
            --output_file "$TMPDIR/out.wav" 2>/dev/null
          ${pkgs.pipewire}/bin/pw-cat -p "$TMPDIR/out.wav" 2>/dev/null
          ;;

        download-models)
          # Scarica modelli whisper + piper italiano
          mkdir -p "$MODELS_DIR"
          if [ ! -f "$WHISPER_MODEL" ]; then
            echo "Downloading whisper ${cfg.whisperModel} (~250MB)..."
            curl -L -o "$WHISPER_MODEL" \
              "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${cfg.whisperModel}.bin"
          fi
          if [ ! -f "$PIPER_MODEL" ]; then
            echo "Downloading piper voice ${cfg.piperVoice} (~60MB)..."
            curl -L -o "$PIPER_MODEL" \
              "https://huggingface.co/rhasspy/piper-voices/resolve/main/it/it_IT/${cfg.piperVoice}/medium/${cfg.piperVoice}.onnx"
            curl -L -o "$PIPER_CONFIG" \
              "https://huggingface.co/rhasspy/piper-voices/resolve/main/it/it_IT/${cfg.piperVoice}/medium/${cfg.piperVoice}.onnx.json"
          fi
          echo "✓ Modelli scaricati in $MODELS_DIR"
          ;;

        status)
          echo "── SOLEM Voice Bridge ──"
          echo "Whisper model: $WHISPER_MODEL"
          [ -f "$WHISPER_MODEL" ] && echo "  ✓ presente ($(du -h "$WHISPER_MODEL" | cut -f1))" || echo "  ✗ MANCANTE"
          echo "Piper voice:   $PIPER_MODEL"
          [ -f "$PIPER_MODEL" ] && echo "  ✓ presente" || echo "  ✗ MANCANTE"
          echo "GAVIO endpoint: ${cfg.gavioEndpoint}"
          EP="${cfg.gavioEndpoint}"
          BASE_URL=$(echo "$EP" | sed 's|/api/.*||')
          if curl -s -m 2 "$BASE_URL/health" >/dev/null 2>&1; then
            echo "  ✓ raggiungibile"
          else
            echo "  ✗ non risponde"
          fi
          ;;

        help|--help|-h|*)
          cat <<'HELP'
solem-voice — TTS + STT + bridge GAVIO (Friday voice)

  ask [sec]          Friday loop: listen → GAVIO → speak (default 5s)
  listen [sec]       STT solo: registra + trascrive
  speak <text>       TTS solo: testo → audio
  download-models    scarica whisper + piper italiano
  status             verifica modelli + GAVIO endpoint

Workflow Friday:
  1. Hotkey Super+Space → invoca: solem-voice ask
  2. Microfono registra 5s
  3. whisper.cpp trascrive (italiano)
  4. Testo → GAVIO API via prompt filter
  5. Risposta → piper TTS → speaker
  6. Notify-send su desktop

Tutto LOCALE: whisper.cpp + piper-tts. No cloud. 0 €.
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.voiceBridge = {
    enable = lib.mkEnableOption "Voice bridge GAVIO (STT whisper + TTS piper italiano)";

    modelsDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/solem/voice-models";
      description = "Directory per modelli whisper + piper";
    };

    whisperModel = lib.mkOption {
      type = lib.types.enum [ "tiny" "base" "small" "medium" "large-v3" ];
      default = "small";
      description = ''
        Modello Whisper:
          - tiny   (~75MB, ~10x realtime, italiano scarso)
          - base   (~140MB, ~5x realtime)
          - small  (~250MB, ~2x realtime, RACCOMANDATO)
          - medium (~770MB, ~1x realtime)
          - large-v3 (~3GB, slow but best)
      '';
    };

    piperVoice = lib.mkOption {
      type = lib.types.str;
      default = "it_IT-paola-medium";
      description = "Voce piper italiana (paola, riccardo, milena disponibili)";
    };

    language = lib.mkOption {
      type = lib.types.str;
      default = "it";
      description = "Lingua per Whisper (it, en, fr, ...)";
    };

    gavioEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:8001/api/chat";
      description = "URL GAVIO API (default via prompt filter Step 21)";
    };

    hotkey = lib.mkOption {
      type = lib.types.str;
      default = "SUPER+space";
      description = ''
        Hotkey Hyprland per invocare "solem-voice ask".
        Configurare manualmente in hyprland.conf:
          bind = SUPER, space, exec, alacritty -e solem-voice ask
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d /var/lib/solem 0755 root root - -"
      "d /var/lib/solem/voice-models 0755 root root - -"
    ];

    environment.systemPackages = with pkgs; [
      voiceScript
      sox                  # registrazione audio
      pipewire             # playback
      openai-whisper-cpp   # STT
      piper-tts            # TTS
      curl jq libnotify
    ];

    # Hyprland binding (informativo: user deve editare hyprland.conf)
    environment.etc."solem/hyprland-voice-binding.conf".text = ''
      # SOLEM Voice — aggiungi a ~/.config/hypr/hyprland.conf
      bind = ${cfg.hotkey}, exec, alacritty -e solem-voice ask
      bind = SUPER SHIFT, space, exec, alacritty -e solem-voice listen
    '';

    environment.etc."solem/voice-bridge.md".text = ''
      # SOLEM Voice Bridge (Step 41)

      Friday/JARVIS-style voice interface: hotkey → mic → STT → GAVIO →
      TTS → speaker. Tutto LOCALE.

      ## Stack FOSS
      - **whisper.cpp** (MIT): STT, modello ${cfg.whisperModel} (italiano)
      - **piper-tts** (MIT): TTS neurale, voce ${cfg.piperVoice}
      - **sox**: capture mic
      - **pw-cat** (PipeWire): playback

      ## Setup primo uso

      ```bash
      # 1. Download modelli (one-time, ~310MB)
      sudo solem-voice download-models

      # 2. Verifica
      solem-voice status

      # 3. Test
      solem-voice ask 5
      # → "Ciao GAVIO" → trascrive → invia GAVIO → risposta vocale
      ```

      ## Hotkey Hyprland
      Aggiungi a ~/.config/hypr/hyprland.conf:
      ```
      bind = ${cfg.hotkey}, exec, alacritty -e solem-voice ask
      ```

      ## Comandi
      - `solem-voice ask` — full Friday loop
      - `solem-voice listen` — solo STT (debug)
      - `solem-voice speak "ciao"` — solo TTS (debug)

      ## Limiti onesti
      - Whisper modello small: italiano OK ma accento forte/dialetti
        falliscono. Per max accuracy: medium o large-v3 (lento).
      - GAVIO bridge richiede Step 21 prompt filter attivo + GAVIO
        packaged (Step 30) per risposte reali.
      - Latency totale tipica: 5s rec + 2-5s whisper + 1-3s GAVIO + 1s TTS
        = 9-14s. NON e' realtime.
      - Hotkey: utente deve editare hyprland.conf manualmente.
        SOLUZIONE futura: hyprland-config modulo che inietta binding.
    '';
  };
}
