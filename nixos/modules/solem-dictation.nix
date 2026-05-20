{ config, pkgs, lib, ... }:

# SOLEM DICTATION — voice-to-text system-wide via whisper + wtype.
#
# Single responsibility: SOLO orchestrazione: hotkey → record → whisper-cli
# → wtype del testo nel campo focus.
#
# Workflow:
#   1. User preme SUPER+CTRL+SPACE (configurabile)
#   2. solem-dictate-start: record audio 30s max in /tmp
#   3. Premi STOP (stesso hotkey) o auto-stop dopo silenzio 2s
#   4. whisper-cli transcribe → testo
#   5. wtype digita il testo dove c'è il focus
#
# 100% offline, FOSS, 0 €.

let
  cfg = config.solem.dictation;

  dictateScript = pkgs.writeShellApplication {
    name = "solem-dictate";
    runtimeInputs = with pkgs; [
      sox openai-whisper-cpp wtype wl-clipboard libnotify coreutils
    ];
    text = ''
      LOCKFILE=/tmp/solem-dictate.pid
      AUDIO=/tmp/solem-dictate.wav
      MODEL="''${WHISPER_MODEL_PATH:-/var/lib/solem-models/whisper/ggml-base.bin}"
      LANG="''${SOLEM_DICTATE_LANG:-it}"

      # Toggle: se già in registrazione, stop
      if [ -f "$LOCKFILE" ]; then
        PID=$(cat "$LOCKFILE")
        kill "$PID" 2>/dev/null || true
        rm -f "$LOCKFILE"
        notify-send "SOLEM Dictation" "Trascrivo..."

        if [ ! -f "$AUDIO" ]; then
          notify-send -u critical "SOLEM Dictation" "Audio mancante"
          exit 1
        fi

        TXT=$(${pkgs.openai-whisper-cpp}/bin/whisper-cli \
          -m "$MODEL" -l "$LANG" -nt -f "$AUDIO" 2>/dev/null \
          | sed 's/^\[.*\] *//' | tr -d '\n')

        if [ -z "$TXT" ]; then
          notify-send -u critical "SOLEM Dictation" "Nessun testo riconosciuto"
          exit 1
        fi

        # Type nel focus corrente
        ${pkgs.wtype}/bin/wtype "$TXT"
        ${pkgs.wl-clipboard}/bin/wl-copy "$TXT"
        notify-send "SOLEM Dictation" "OK: $TXT"
        rm -f "$AUDIO"
        exit 0
      fi

      # Start recording
      notify-send "SOLEM Dictation" "Recording... (premi hotkey per STOP, max 30s)"
      ${pkgs.sox}/bin/rec -r 16000 -c 1 -b 16 "$AUDIO" trim 0 30 &
      echo $! > "$LOCKFILE"
    '';
  };
in {
  options.solem.dictation = {
    enable = lib.mkEnableOption "Voice dictation system-wide (whisper + wtype)";

    language = lib.mkOption {
      type = lib.types.str;
      default = "it";
      description = "Lingua whisper (it, en, es, fr...)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ dictateScript ];

    environment.sessionVariables = {
      SOLEM_DICTATE_LANG = cfg.language;
    };

    # NB: hotkey va dichiarata in hyprland-config:
    #   bind = SUPER CTRL, SPACE, exec, solem-dictate
  };
}
