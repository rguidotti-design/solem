{ config, pkgs, lib, ... }:

# SOLEM AI SHORTCUTS — keybind rapidi che chiamano solem-api/GAVIO.
#
# Single responsibility: SOLO bind Hyprland per shortcut AI rapidi:
#   Super + T  → traduci selezione (clipboard) IT↔EN via solem-api
#   Super + M  → meteo (chiede città se non fornita)
#   Super + W  → wiki sulla selezione
#   Super + D  → dizionario sulla parola selezionata
#   Super + R  → currency: ultimo cambio EUR/USD
#   Super + G  → query GAVIO con selezione come contesto
#
# CLI helper `solem-ai-shortcut <action>` chiamabile direttamente.

let
  cfg = config.solem.aiShortcuts;

  shortcutCli = pkgs.writeShellApplication {
    name = "solem-ai-shortcut";
    runtimeInputs = with pkgs; [ coreutils wl-clipboard libnotify curl jq ];
    text = ''
      ACTION="''${1:-help}"
      shift || true

      SELECTION=$(wl-paste -p 2>/dev/null || echo "")
      CLIP=$(wl-paste 2>/dev/null || echo "")

      notify() {
        if command -v notify-send >/dev/null 2>&1; then
          notify-send -a "SOLEM AI" -t 10000 "$1" "$2"
        fi
        echo "── $1 ──"
        echo "$2"
      }

      case "$ACTION" in

        # ── Traduci selezione IT→EN o auto ────────────────────────────
        translate|t)
          if [ -z "$SELECTION" ] && [ -z "$CLIP" ]; then
            notify "Translate" "Nessuna selezione o clipboard"
            exit 1
          fi
          TEXT="''${SELECTION:-$CLIP}"
          OUT=$(solem-api translate "$TEXT" auto it 2>/dev/null)
          [ -z "$OUT" ] && OUT="(traduzione fallita — controlla rete)"
          notify "Traduzione" "$OUT"
          echo "$OUT" | wl-copy 2>/dev/null || true
          ;;

        # ── Meteo (chiede città se non fornita) ───────────────────────
        weather|m|meteo)
          CITY="''${1:-$SELECTION}"
          [ -z "$CITY" ] && CITY="Rome"
          OUT=$(solem-api weather "$CITY" 2>/dev/null | jq -r '"Temp: " + (.temperature_2m | tostring) + "°C, vento: " + (.wind_speed_10m | tostring) + " km/h"' 2>/dev/null)
          [ -z "$OUT" ] && OUT="(meteo fallito)"
          notify "Meteo $CITY" "$OUT"
          ;;

        # ── Wiki sulla selezione ──────────────────────────────────────
        wiki|w)
          Q="''${SELECTION:-$CLIP}"
          if [ -z "$Q" ]; then
            notify "Wiki" "Seleziona una parola/frase"
            exit 1
          fi
          OUT=$(solem-api wiki "$Q" it 2>/dev/null | jq -r '.extract // "Non trovato"' 2>/dev/null | head -c 500)
          notify "Wiki: $Q" "$OUT"
          ;;

        # ── Dizionario ────────────────────────────────────────────────
        dict|d)
          WORD="''${SELECTION:-$CLIP}"
          if [ -z "$WORD" ]; then
            notify "Dict" "Seleziona una parola"
            exit 1
          fi
          OUT=$(solem-api dict "$WORD" en 2>/dev/null | jq -r '.def // "Non trovato"' 2>/dev/null | head -c 300)
          notify "Definizione: $WORD" "$OUT"
          ;;

        # ── Currency EUR/USD live ─────────────────────────────────────
        currency|r)
          OUT=$(solem-api currency EUR USD 1 2>/dev/null | jq -r '"1 EUR = " + (.rate | tostring) + " USD (" + .date + ")"' 2>/dev/null)
          notify "EUR/USD" "$OUT"
          ;;

        # ── GAVIO query con contesto clipboard ────────────────────────
        gavio|g)
          Q="''${SELECTION:-$CLIP}"
          if [ -z "$Q" ]; then
            notify "GAVIO" "Seleziona testo o copia in clipboard"
            exit 1
          fi
          GAVIO_URL="''${GAVIO_API_URL:-http://127.0.0.1:8000}"
          RESPONSE=$(curl -s -m 5 -X POST "$GAVIO_URL/v2/agent/query" \
            -H "Content-Type: application/json" \
            -d "$(jq -n --arg q 'spiega:' --arg c "$Q" '{query:$q, context:$c}')" 2>/dev/null)
          OUT=$(echo "$RESPONSE" | jq -r '.response // .answer // "GAVIO offline"' 2>/dev/null)
          notify "GAVIO" "$OUT"
          echo "$OUT" | wl-copy 2>/dev/null || true
          ;;

        # ── HELP ─────────────────────────────────────────────────────
        help|--help|-h|*)
          cat <<'HELP'
solem-ai-shortcut — AI quick actions su selezione/clipboard

  t/translate    traduci selezione → italiano
  m/weather      meteo (default Roma o selezione come città)
  w/wiki         Wikipedia sulla selezione
  d/dict         definizione dizionario (en)
  r/currency     1 EUR in USD live
  g/gavio        query GAVIO con selezione come contesto

Suggerito uso con bind Hyprland:
  bind = SUPER, T, exec, solem-ai-shortcut translate
  bind = SUPER, M, exec, solem-ai-shortcut weather
  bind = SUPER, W, exec, solem-ai-shortcut wiki
  bind = SUPER, D, exec, solem-ai-shortcut dict
  bind = SUPER, R, exec, solem-ai-shortcut currency
  bind = SUPER, G, exec, solem-ai-shortcut gavio

Output mostrato come notifica desktop + copiato in clipboard.
HELP
          ;;
      esac
    '';
  };

  hyprBinds = pkgs.writeText "solem-ai-shortcuts.conf" ''
    # ── SOLEM AI shortcuts ──────────────────────────────────────────
    bind = SUPER, T, exec, solem-ai-shortcut translate
    bind = SUPER, M, exec, solem-ai-shortcut weather
    bind = SUPER, W, exec, solem-ai-shortcut wiki
    bind = SUPER, D, exec, solem-ai-shortcut dict
    bind = SUPER, R, exec, solem-ai-shortcut currency
    bind = SUPER, G, exec, solem-ai-shortcut gavio
  '';
in {
  options.solem.aiShortcuts = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa `solem-ai-shortcut` + bind Hyprland AI quick actions";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ shortcutCli ];
    environment.etc."xdg/solem/hypr-ai-shortcuts.conf".source = hyprBinds;
  };
}
