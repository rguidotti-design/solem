{ config, pkgs, lib, ... }:

# SOLEM GAVIO CONTEXT — context-aware GAVIO (app attiva + selezione testo).
#
# Single responsibility: SOLO installare i tool CLI che permettono a GAVIO
# di ricevere automaticamente:
# - finestra/app attualmente in focus (hyprctl activewindow)
# - selezione testo corrente (wl-paste -p)
# - clipboard regular (wl-paste)
# - screenshot regione (grim + slurp) → OCR opzionale
#
# Più keybind Hyprland per:
#   Super+G        → query GAVIO con clipboard come contesto
#   Super+Shift+G  → query GAVIO con selezione testo come contesto
#   Super+Alt+G    → screenshot OCR + query GAVIO
#
# Trasporto via socket localhost al servizio GAVIO. 0 €. Vantaggio
# competitivo unico vs macOS/Win (no Apple Intelligence equivalent FOSS).

let
  cfg = config.solem.gavioContext;

  contextCli = pkgs.writeShellApplication {
    name = "solem-gavio-ctx";
    runtimeInputs = with pkgs; [ curl jq wl-clipboard hyprland grim slurp tesseract coreutils ];
    text = ''
      GAVIO_URL="''${GAVIO_API_URL:-http://127.0.0.1:8000}"
      MODE="''${1:-clipboard}"

      # Raccogli contesto in base al modo
      case "$MODE" in
        clipboard)
          CONTEXT=$(wl-paste 2>/dev/null || true)
          QUESTION="''${2:-Spiegami questo}"
          ;;
        selection)
          CONTEXT=$(wl-paste -p 2>/dev/null || true)
          QUESTION="''${2:-Spiegami questo}"
          ;;
        screen-ocr)
          TMP=$(mktemp --suffix=.png)
          # User seleziona regione, screenshot, OCR
          grim -g "$(slurp)" "$TMP" 2>/dev/null
          CONTEXT=$(tesseract "$TMP" - -l ita+eng 2>/dev/null)
          rm -f "$TMP"
          QUESTION="''${2:-Cosa c'è in questa schermata?}"
          ;;
        active-window)
          INFO=$(hyprctl activewindow -j 2>/dev/null || echo '{}')
          CONTEXT="App: $(echo "$INFO" | jq -r '.class') | Titolo: $(echo "$INFO" | jq -r '.title')"
          QUESTION="''${2:-Aiutami con questa app}"
          ;;
        *)
          echo "solem-gavio-ctx — invia contesto a GAVIO"
          echo
          echo "  solem-gavio-ctx clipboard [domanda]      contesto = clipboard"
          echo "  solem-gavio-ctx selection [domanda]      contesto = selezione corrente"
          echo "  solem-gavio-ctx screen-ocr [domanda]     screenshot regione + OCR"
          echo "  solem-gavio-ctx active-window [domanda]  contesto = finestra attiva"
          exit 0
          ;;
      esac

      # Query GAVIO con contesto
      PAYLOAD=$(jq -n --arg q "$QUESTION" --arg c "$CONTEXT" '{query: $q, context: $c}')
      RESPONSE=$(curl -sS -X POST "$GAVIO_URL/v2/agent/query" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" 2>/dev/null || echo '{"response":"GAVIO offline"}')

      # Estrai risposta
      ANSWER=$(echo "$RESPONSE" | jq -r '.response // .answer // "(no response)"')

      # Notifica con risposta (mako)
      if command -v notify-send >/dev/null; then
        notify-send -a "GAVIO" -t 15000 "GAVIO" "$ANSWER"
      fi

      # Anche stdout per script
      echo "$ANSWER"

      # Copia risposta in clipboard
      echo "$ANSWER" | wl-copy
    '';
  };

  hyprBinds = pkgs.writeText "solem-gavio-binds.conf" ''
    # ── SOLEM GAVIO context-aware binds ─────────────────────────────
    # Aggiungi al tuo ~/.config/hypr/hyprland.conf con:
    #   source = /etc/xdg/solem/hypr-gavio-binds.conf

    bind = SUPER, G,       exec, solem-gavio-ctx clipboard
    bind = SUPER SHIFT, G, exec, solem-gavio-ctx selection
    bind = SUPER ALT, G,   exec, solem-gavio-ctx screen-ocr
    bind = SUPER CTRL, G,  exec, solem-gavio-ctx active-window
  '';
in {
  options.solem.gavioContext = {
    enable = lib.mkEnableOption "GAVIO context-aware (clipboard/selezione/OCR/app attiva)";

    ocrLanguages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "ita" "eng" ];
      description = "Lingue Tesseract per screen-OCR";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      contextCli
      wl-clipboard         # wl-copy / wl-paste
      grim                 # screenshot Wayland
      slurp                # selezione regione
      tesseract            # OCR FOSS
      libnotify            # notify-send
      jq
      curl
    ];

    # Tesseract: lingue extra
    environment.variables.TESSDATA_PREFIX = "${pkgs.tesseract}/share/tessdata";

    # Hyprland binds suggeriti (utente li include via source =)
    environment.etc."xdg/solem/hypr-gavio-binds.conf".source = hyprBinds;
  };
}
