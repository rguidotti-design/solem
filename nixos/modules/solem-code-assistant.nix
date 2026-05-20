{ config, pkgs, lib, ... }:

# SOLEM CODE ASSISTANT — editor configurato per usare GAVIO come AI backend.
#
# Single responsibility: SOLO installare VSCodium + script bash che parla
# con GAVIO. NIENTE Continue.dev autonomo, NIENTE Aider con LLM separato.
# L'unica AI è GAVIO.
#
# In editor l'utente apre la palette comandi e chiama `solem-ask-gavio`
# (vedi scripts/solem-ask-gavio.sh) che gira il codice selezionato + prompt
# alla API GAVIO via SOLEM proxy.
#
# 100% FOSS, 0 €.

let
  cfg = config.solem.codeAssistant;

  askGavioScript = pkgs.writeShellApplication {
    name = "solem-ask-gavio";
    runtimeInputs = with pkgs; [ curl jq wl-clipboard libnotify ];
    text = ''
      # Legge stdin (codice/testo) + arg = prompt e manda a GAVIO via SOLEM proxy.
      API="''${SOLEM_API_URL:-http://127.0.0.1:8001}"
      PROMPT="''${1:-Spiega questo codice in italiano.}"
      INPUT="$(cat)"

      body=$(${pkgs.jq}/bin/jq -n \
        --arg p "$PROMPT" \
        --arg i "$INPUT" \
        '{messages:[{role:"user",content:($p + "\n\n" + $i)}],hint:"code",max_tokens:1500,temperature:0.2}')

      RESP=$(${pkgs.curl}/bin/curl -fsS -X POST "$API/solem/ai/route" \
        -H 'Content-Type: application/json' -d "$body" \
        | ${pkgs.jq}/bin/jq -r .content)

      echo "$RESP" | ${pkgs.wl-clipboard}/bin/wl-copy
      notify-send "GAVIO" "Risposta in clipboard (Ctrl+V)"
      echo "$RESP"
    '';
  };
in {
  options.solem.codeAssistant = {
    enable = lib.mkEnableOption "Editor configurato per parlare con GAVIO (no AI separate)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      vscodium
      askGavioScript
    ];

    # Snippet doc per l'utente
    environment.etc."solem/code-assistant.md".text = ''
      # SOLEM Code Assistant — usa GAVIO

      In editor, seleziona codice e da terminale integrato:

        echo "<paste code>" | solem-ask-gavio "Refactor in modo idiomatico"
        cat file.py | solem-ask-gavio "Trova i bug"

      Tutto passa per GAVIO (l'unica AI di SOLEM). Nessun Continue.dev
      o assistente AI separato installato.
    '';
  };
}
