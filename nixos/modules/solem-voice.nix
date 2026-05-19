{ config, pkgs, lib, ... }:

let
  cfg = config.solem.voice;
in {
  # ──────────────────────────────────────────────────────────────────────
  # SOLEM VOICE — STT + TTS locali (M2.2 anticipato)
  # ──────────────────────────────────────────────────────────────────────
  # whisper.cpp (STT) + piper (TTS) tutto on-device, no cloud, FOSS.
  # Rispetta direttiva utente "solo gratuito + on-device first".
  #
  # Sostituisce: edge-tts cloud (era usato da GAVIO).
  # API endpoint via solem-api: /solem/voice/stt + /solem/voice/tts (Step 2).
  #
  # Default OFF (modelli aggiuntivi ~500MB-2GB).
  # Attivare: solem.voice.enable = true;

  options.solem.voice = {
    enable = lib.mkEnableOption "Voice STT (whisper.cpp) + TTS (piper) locali";

    sttModel = lib.mkOption {
      type = lib.types.enum [ "tiny" "base" "small" "medium" "large-v3" ];
      default = "base";
      description = "Modello whisper.cpp. base=140MB, small=460MB, medium=1.5GB.";
    };

    ttsVoice = lib.mkOption {
      type = lib.types.str;
      default = "it_IT-paola-medium";
      description = "Voce piper. it_IT-* per italiano, en_US-* per inglese.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Pacchetti core voice
    environment.systemPackages = with pkgs; [
      whisper-cpp        # STT, ~5MB binary
      piper-tts          # TTS
      ffmpeg             # già installato da gavio.nix
      sox                # audio processing
    ];

    # Directory per modelli voice
    systemd.tmpfiles.rules = [
      "d /var/lib/solem-voice              0755 gavio users -"
      "d /var/lib/solem-voice/whisper      0755 gavio users -"
      "d /var/lib/solem-voice/piper        0755 gavio users -"
    ];

    # Pre-download modelli al primo boot (idempotente)
    systemd.services.solem-voice-models = {
      description = "SOLEM Voice — pre-download whisper.cpp + piper models";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "gavio";
        Group = "users";
        Nice = 19;
        IOSchedulingClass = "idle";
        TimeoutStartSec = "0";
      };

      script = ''
        MARKER=/var/lib/solem-voice/.models-pulled
        if [ -f "$MARKER" ]; then exit 0; fi

        # Whisper.cpp model (GGML format dal repo HuggingFace ggerganov)
        WHISPER_DIR=/var/lib/solem-voice/whisper
        WHISPER_MODEL=ggml-${cfg.sttModel}.bin
        if [ ! -f "$WHISPER_DIR/$WHISPER_MODEL" ]; then
          echo "[voice] download whisper $WHISPER_MODEL..."
          ${pkgs.curl}/bin/curl -fsSL \
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$WHISPER_MODEL" \
            -o "$WHISPER_DIR/$WHISPER_MODEL" || echo "[voice] WARN whisper fallito"
        fi

        # Piper voice (.onnx + .onnx.json)
        PIPER_DIR=/var/lib/solem-voice/piper
        VOICE=${cfg.ttsVoice}
        if [ ! -f "$PIPER_DIR/$VOICE.onnx" ]; then
          echo "[voice] download piper voice $VOICE..."
          # Piper voices su HuggingFace rhasspy/piper-voices
          # Struttura repo: it/it_IT/paola/medium/...
          LANG_CODE=$(echo "$VOICE" | cut -d_ -f1)
          REGION=$(echo "$VOICE" | cut -d- -f1)
          SPEAKER=$(echo "$VOICE" | cut -d- -f2)
          QUALITY=$(echo "$VOICE" | cut -d- -f3)
          BASE_URL="https://huggingface.co/rhasspy/piper-voices/resolve/main/$LANG_CODE/$REGION/$SPEAKER/$QUALITY"
          ${pkgs.curl}/bin/curl -fsSL "$BASE_URL/$VOICE.onnx" -o "$PIPER_DIR/$VOICE.onnx" || echo "[voice] WARN piper model fallito"
          ${pkgs.curl}/bin/curl -fsSL "$BASE_URL/$VOICE.onnx.json" -o "$PIPER_DIR/$VOICE.onnx.json" || echo "[voice] WARN piper config fallito"
        fi

        touch "$MARKER"
        echo "[voice] modelli pronti."
      '';
    };

    # Export config path for API consumption
    environment.etc."solem/voice-config.json".text = builtins.toJSON {
      enabled = cfg.enable;
      stt = {
        engine = "whisper.cpp";
        model = cfg.sttModel;
        model_path = "/var/lib/solem-voice/whisper/ggml-${cfg.sttModel}.bin";
        binary = "${pkgs.whisper-cpp}/bin/whisper-cli";
      };
      tts = {
        engine = "piper";
        voice = cfg.ttsVoice;
        voice_path = "/var/lib/solem-voice/piper/${cfg.ttsVoice}.onnx";
        binary = "${pkgs.piper-tts}/bin/piper";
      };
      api_endpoints = {
        stt = "POST /solem/voice/stt (multipart audio file)";
        tts = "POST /solem/voice/tts (json text)";
      };
    };
  };
}
