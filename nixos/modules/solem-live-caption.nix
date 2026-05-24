{ config, pkgs, lib, ... }:

# SOLEM LIVE CAPTION — sottotitoli live mic via whisper.cpp (FOSS).
#
# Single responsibility: SOLO CLI `solem-caption` che:
# - Cattura audio mic in chunks 5s
# - Trascrive con whisper.cpp (offline)
# - Display sottotitoli a console + notifica
#
# Equivale a Apple Live Captions / Windows Live Captions.

let
  cfg = config.solem.liveCaption;

  captionCli = pkgs.writeShellApplication {
    name = "solem-caption";
    runtimeInputs = with pkgs; [ coreutils ffmpeg openai-whisper-cpp wl-clipboard libnotify ];
    text = ''
      MODEL="''${SOLEM_CAPTION_MODEL:-base}"
      LANG="''${SOLEM_CAPTION_LANG:-it}"
      CHUNK="''${SOLEM_CAPTION_CHUNK:-5}"
      MODELS_DIR="$HOME/.local/share/solem/whisper-models"
      MODEL_FILE="$MODELS_DIR/ggml-$MODEL.bin"

      if [ ! -f "$MODEL_FILE" ]; then
        echo "Modello whisper mancante: $MODEL_FILE"
        echo "Scarica con: solem-dictate download $MODEL"
        exit 1
      fi

      echo "── SOLEM Live Caption ──"
      echo "Lingua: $LANG, modello: $MODEL, chunk: ''${CHUNK}s"
      echo "Premi Ctrl+C per fermare."
      echo

      TMPDIR="''${TMPDIR:-/tmp}"
      while true; do
        WAV="$TMPDIR/caption-$$.wav"
        ffmpeg -hide_banner -loglevel error -f pulse -i default -t "$CHUNK" -ar 16000 -ac 1 -y "$WAV" 2>/dev/null
        TEXT=$(whisper-cpp -m "$MODEL_FILE" -l "$LANG" -f "$WAV" -nt -otxt 2>/dev/null | sed 's/^\[.*\]\s*//' | tr -d '\r' | tr '\n' ' ')
        rm -f "$WAV"
        if [ -n "$TEXT" ] && [ "$TEXT" != " " ]; then
          echo "▸ $TEXT"
          if command -v notify-send >/dev/null 2>&1; then
            notify-send -t 3000 -a "SOLEM Caption" "$TEXT"
          fi
        fi
      done
    '';
  };
in {
  options.solem.liveCaption = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Installa `solem-caption` live STT mic (richiede whisper model)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      captionCli
      openai-whisper-cpp
      ffmpeg
      libnotify
    ];
  };
}
