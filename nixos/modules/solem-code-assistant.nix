{ config, pkgs, lib, ... }:

# SOLEM CODE ASSISTANT — Continue.dev + Aider via Ollama locale.
#
# Single responsibility: SOLO installazione editor + config Continue.dev
# che punta a Ollama locale (autocomplete inline + chat in-editor).
#
# 100% FOSS, 0 €:
#   - Continue.dev   (Apache-2.0) plugin VS Code/JetBrains
#   - Aider          (Apache-2.0) AI pair-programmer CLI
#   - VSCodium       (MIT, no telemetria)
#   - Ollama         (local LLM, già installato)
#
# Modelli code raccomandati (auto-pull al primo uso):
#   - qwen2.5-coder:7b   (autocomplete)
#   - deepseek-coder-v2:16b (chat code)

let
  cfg = config.solem.codeAssistant;

  continueConfig = pkgs.writeText "continue-config.json" (builtins.toJSON {
    models = [
      {
        title = "Qwen Coder (local)";
        provider = "ollama";
        model = "qwen2.5-coder:7b";
        apiBase = "http://127.0.0.1:11434";
      }
      {
        title = "DeepSeek Coder (local)";
        provider = "ollama";
        model = "deepseek-coder-v2:16b";
        apiBase = "http://127.0.0.1:11434";
      }
    ];
    tabAutocompleteModel = {
      title = "Qwen Coder autocomplete";
      provider = "ollama";
      model = "qwen2.5-coder:7b";
      apiBase = "http://127.0.0.1:11434";
    };
    embeddingsProvider = {
      provider = "ollama";
      model = "nomic-embed-text";
      apiBase = "http://127.0.0.1:11434";
    };
    contextProviders = [
      { name = "code"; }
      { name = "docs"; }
      { name = "diff"; }
      { name = "terminal"; }
      { name = "problems"; }
      { name = "folder"; }
      { name = "codebase"; }
    ];
    allowAnonymousTelemetry = false;
  });
in {
  options.solem.codeAssistant = {
    enable = lib.mkEnableOption "Code assistant locale (Continue.dev + Aider + VSCodium)";

    autoPullModels = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Scarica qwen2.5-coder + nomic-embed al primo boot";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      vscodium
      aider-chat
    ];

    # Config Continue.dev system-wide (utenti possono override in ~/.continue/)
    environment.etc."xdg/continue/config.json".source = continueConfig;

    # Auto-pull modelli ollama al primo boot
    systemd.services.solem-code-models-pull = lib.mkIf cfg.autoPullModels {
      description = "SOLEM — pull modelli code (qwen-coder + nomic-embed)";
      after = [ "ollama.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [ ollama curl ];
      serviceConfig = {
        Type = "oneshot";
        User = "ollama";
        TimeoutStartSec = "30min";
        Restart = "no";
        ExecStart = pkgs.writeShellScript "solem-code-models-pull" ''
          set -euo pipefail
          for m in qwen2.5-coder:7b nomic-embed-text; do
            if ! ${pkgs.ollama}/bin/ollama list | grep -q "$m"; then
              ${pkgs.ollama}/bin/ollama pull "$m" || true
            fi
          done
        '';
      };
    };
  };
}
