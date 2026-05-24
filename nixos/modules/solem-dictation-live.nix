{ config, pkgs, lib, ... }:

# SOLEM DICTATION LIVE — speech-to-text con whisper.cpp.
#
# Single responsibility: SOLO CLI `solem-dictate` che:
# - Registra audio dal mic per 30s default
# - Trascrive con whisper.cpp (offline, FOSS)
# - Output testo a stdout o copia clipboard via wl-copy
#
# Modelli FOSS: tiny (~ 75 MB, veloce, 5 lingue) → base (~ 142 MB,
# 99 lingue, accurato) → small (~ 466 MB, top quality).
#
# Tutto offline, no API cloud, no telemetria.

let
  cfg = config.solem.dictationLive;

  dictateCli = pkgs.writeShellApplication {
    name = "solem-dictate";
    runtimeInputs = with pkgs; [ coreutils ffmpeg openai-whisper-cpp wl-clipboard ];
    text = ''
      ACTION="''${1:-record}"
      shift || true

      MODEL="''${SOLEM_DICTATE_MODEL:-base}"
      LANG="''${SOLEM_DICTATE_LANG:-it}"
      DURATION="''${SOLEM_DICTATE_SECONDS:-15}"
      TMPDIR="''${TMPDIR:-/tmp}"
      MODELS_DIR="$HOME/.local/share/solem/whisper-models"
      mkdir -p "$MODELS_DIR"

      MODEL_FILE="$MODELS_DIR/ggml-$MODEL.bin"

      case "$ACTION" in

        # ── Scarica modello FOSS Whisper ──────────────────────────────
        download|dl)
          MODEL_NAME="''${1:-base}"
          URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$MODEL_NAME.bin"
          echo "Download whisper model: $MODEL_NAME (~ 142 MB for base)"
          curl -L "$URL" -o "$MODELS_DIR/ggml-$MODEL_NAME.bin"
          echo "Salvato: $MODELS_DIR/ggml-$MODEL_NAME.bin"
          ;;

        # ── Registra + trascrivi ─────────────────────────────────────
        record|r|"")
          if [ ! -f "$MODEL_FILE" ]; then
            echo "Modello mancante: $MODEL_FILE"
            echo "Scarica con: solem-dictate download base"
            exit 1
          fi

          WAV="$TMPDIR/solem-dictate-$$.wav"
          echo "Registro $DURATION secondi dal mic..."
          ffmpeg -hide_banner -loglevel error -f pulse -i default -t "$DURATION" -ar 16000 -ac 1 -y "$WAV"

          echo "Trascrizione in corso (whisper.cpp, $MODEL, $LANG)..."
          TEXT=$(whisper-cpp -m "$MODEL_FILE" -l "$LANG" -f "$WAV" -nt -otxt 2>/dev/null | sed 's/^\[.*\]\s*//' | tr -d '\r')
          rm -f "$WAV"

          echo "──"
          echo "$TEXT"
          echo "──"

          # Copia in clipboard se wl-copy disponibile
          if command -v wl-copy >/dev/null 2>&1; then
            echo "$TEXT" | wl-copy
            echo "(copiato in clipboard)"
          fi
          ;;

        # ── Trascrivi file audio esistente ────────────────────────────
        file|transcribe)
          AUDIO="''${1:?Usage: solem-dictate file <audio>}"
          if [ ! -f "$MODEL_FILE" ]; then
            echo "Modello mancante. Scarica: solem-dictate download $MODEL"
            exit 1
          fi
          # Convert se non WAV 16kHz mono
          WAV="$TMPDIR/transcribe-$$.wav"
          ffmpeg -hide_banner -loglevel error -i "$AUDIO" -ar 16000 -ac 1 -y "$WAV"
          whisper-cpp -m "$MODEL_FILE" -l "$LANG" -f "$WAV" -nt -otxt 2>/dev/null
          rm -f "$WAV"
          ;;

        # ── Lista modelli scaricati ───────────────────────────────────
        models)
          echo "Modelli whisper disponibili in $MODELS_DIR:"
          ls -lh "$MODELS_DIR"/*.bin 2>/dev/null || echo "(nessuno scaricato)"
          echo
          echo "Modelli scaricabili:"
          echo "  tiny      ~ 75 MB   (veloce, 5 lingue, qualità bassa)"
          echo "  base      ~ 142 MB  (raccomandato, 99 lingue)"
          echo "  small     ~ 466 MB  (qualità alta)"
          echo "  medium    ~ 1.5 GB  (qualità top, lento)"
          echo "  large     ~ 3 GB    (best quality, molto lento)"
          ;;

        # ── HELP ─────────────────────────────────────────────────────
        help|--help|-h|*)
          cat <<'HELP'
solem-dictate — speech-to-text offline FOSS (whisper.cpp)

  Setup (una tantum):
    solem-dictate download base       scarica modello (~ 142 MB)

  Uso:
    solem-dictate                     registra 15s + trascrivi + clipboard
    solem-dictate record              idem
    solem-dictate file audio.mp3      trascrivi file audio
    solem-dictate models              lista modelli installati

  Variabili env:
    SOLEM_DICTATE_MODEL=base           tiny|base|small|medium|large
    SOLEM_DICTATE_LANG=it              en|it|fr|de|...
    SOLEM_DICTATE_SECONDS=15           durata registrazione

Tutto offline. Nessuna API cloud. 0 €.
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.dictationLive = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Installa `solem-dictate` speech-to-text whisper.cpp (richiede ~ 200 MB modello)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      dictateCli
      openai-whisper-cpp
      ffmpeg
      wl-clipboard
    ];
  };
}
