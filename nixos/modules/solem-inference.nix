{ config, pkgs, lib, ... }:

# SOLEM INFERENCE — backend di inferenza locali (zero-cloud, 100% FOSS).
#
# Single responsibility: SOLO installazione dei binari di inferenza
# (whisper-cpp, piper, llama-cpp). I server FastAPI che li espongono
# vivono in solem-voice.nix / solem-llm.nix.
#
# ADR-014 → Ollama resta il default per LLM; questo modulo aggiunge:
#   - whisper-cpp  → STT offline (ggml models)
#   - piper        → TTS offline (voci scaricabili)
#   - llama-cpp    → runtime alternativo (GGUF, no daemon)
#
# Modelli NON inclusi nel build (sono grandi): si scaricano al primo uso
# in /var/lib/solem-models/ tramite solem-models-fetch.service.

let
  cfg = config.solem.inference;

  modelDir = "/var/lib/solem-models";

  fetchScript = pkgs.writeShellScript "solem-models-fetch" ''
    set -euo pipefail
    mkdir -p ${modelDir}/whisper ${modelDir}/piper ${modelDir}/llama
    cd ${modelDir}

    # whisper.cpp — base.en (74 MB, multilingual ottimo per IT)
    if [ ! -f whisper/ggml-base.bin ]; then
      ${pkgs.curl}/bin/curl -fL --retry 3 \
        -o whisper/ggml-base.bin \
        https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
    fi

    # piper — voce IT it_IT-paola-medium (~ 60 MB)
    if [ ! -f piper/it_IT-paola-medium.onnx ]; then
      ${pkgs.curl}/bin/curl -fL --retry 3 \
        -o piper/it_IT-paola-medium.onnx \
        https://huggingface.co/rhasspy/piper-voices/resolve/main/it/it_IT/paola/medium/it_IT-paola-medium.onnx
      ${pkgs.curl}/bin/curl -fL --retry 3 \
        -o piper/it_IT-paola-medium.onnx.json \
        https://huggingface.co/rhasspy/piper-voices/resolve/main/it/it_IT/paola/medium/it_IT-paola-medium.onnx.json
    fi

    chown -R gavio:users ${modelDir}
    chmod -R 755 ${modelDir}
  '';
in {
  options.solem.inference = {
    enable = lib.mkEnableOption "SOLEM inference backends (whisper+piper+llama)";

    autoFetchModels = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Scarica modelli base al primo boot (whisper base + piper IT)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      openai-whisper-cpp     # whisper-cli binary
      piper-tts              # piper binary + voci CLI
      llama-cpp              # llama-server + llama-cli
    ];

    systemd.tmpfiles.rules = [
      "d ${modelDir}             0755 gavio users - -"
      "d ${modelDir}/whisper     0755 gavio users - -"
      "d ${modelDir}/piper       0755 gavio users - -"
      "d ${modelDir}/llama       0755 gavio users - -"
    ];

    # Fetch modelli al primo boot (idempotente, re-fetch se mancano)
    systemd.services.solem-models-fetch = lib.mkIf cfg.autoFetchModels {
      description = "SOLEM — download modelli inference (whisper/piper)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = fetchScript;
        # Non bloccare il boot: fail silenzioso, retry al reboot
        TimeoutStartSec = "10min";
        Restart = "no";
      };
    };

    # Espongo path modelli via env
    environment.sessionVariables = {
      SOLEM_MODELS_DIR = modelDir;
      WHISPER_MODEL_PATH = "${modelDir}/whisper/ggml-base.bin";
      PIPER_MODEL_PATH = "${modelDir}/piper/it_IT-paola-medium.onnx";
    };
  };
}
