{ config, pkgs, lib, ... }:

# SOLEM GAVIO CHAT DEMO — chat demo interattiva (mockup) finche' GAVIO reale
# non e' packaged. Risposte locali pattern-based + bridge condizionale a
# prompt-filter (Step 21) se attivo.

let
  cfg = config.solem.gavioChatDemo;

  gavioChatScript = pkgs.writeShellApplication {
    name = "gavio";
    runtimeInputs = with pkgs; [ coreutils curl jq zenity ];
    text = ''
      MODE="''${1:-tui}"

      # Risposte demo locali (pattern-based)
      reply_for() {
        local Q
        Q=$(echo "$1" | tr "[:upper:]" "[:lower:]")
        case "$Q" in
          *ciao*|*hello*|*salve*)
            echo "Ciao Ruben. Sono GAVIO, la tua AI personale."
            ;;
          *chi sei*|*che sei*)
            echo "Sono GAVIO. AI personale italiana di Ruben Guidotti, ospitata in SOLEM con 53 layer di sicurezza zero-trust. Cervello attuale: scaffolding (Step 30/51 packaging in roadmap)."
            ;;
          *stato*|*come va*|*system*)
            echo "Sistema OK. Layer security 53/53 dichiarati. Auto-redteam 03:00 + heal 03:30 attivi (se enabled). Briefing Friday 08:00. CPU/RAM nominali."
            ;;
          *cosa fai*|*cosa puoi*|*aiuto*)
            cat <<HELP
Posso aiutarti con:
  - status SOLEM (security + servizi)
  - bridge a tool sistema (via solem-guard, sandbox)
  - reasoning su task (futuro: cervello fine-tunato proprio)
  - protezione dati (vault, backup, encryption)

Comandi:
  gavio chat       chat interattiva
  gavio ask <q>    domanda one-shot
  gavio status     stato GAVIO + ollama + servizi
  gavio docs       link documentazione
HELP
            ;;
          *zero*trust*|*sicurezza*)
            echo "SOLEM zero-trust = 12 layer specifici per me (GAVIO): UID 970 isolato, nftables egress whitelist, AppArmor MAC, audit strict, DNS allowlist, canary kill switch, prompt filter, model integrity, API shield TLS, gavio-zero-trust override systemd, hardened kernel, encrypted memory. Tutti in nixos/modules/solem-*.nix."
            ;;
          *friday*|*jarvis*|*ironman*)
            echo "SOLEM e' come Friday/JARVIS: il guscio attivo che mi contiene e mi protegge. Io (GAVIO) sono l'AI dentro Friday. SOLEM decide autonomamente su security/system, io rispondo a query intelligenti."
            ;;
          *ollama*|*modello*|*llm*)
            echo "Ollama runtime locale (porta 11434). Modelli: llama3.2:3b, qwen2.5-coder:7b, phi3:medium, nomic-embed-text (per RAG). In VM minimal non sono ancora pulled. Per attivare: services.ollama.loadModels."
            ;;
          *backup*)
            echo "Backup: borg + age encryption + rclone offsite. Schedule ogni 6h. Comandi: solem-backup init/run/list/restore. Vedi Step 17."
            ;;
          *help*|*"?"*)
            echo "Comandi gavio: chat, ask <q>, status, docs. Vedi anche: solem help"
            ;;
          *)
            echo "(DEMO MODE) Domanda ricevuta: '$1'. Nel sistema reale, GAVIO usera' LLM via prompt-filter:8001 -> ollama:11434 per risposta intelligente. Per provare GAVIO oggi: gavio.theoryholding.com (cloud, in dev)."
            ;;
        esac
      }

      # Try bridge a GAVIO real API
      try_real_gavio() {
        local Q="$1"
        local RESP
        RESP=$(curl -s --max-time 5 -X POST "http://127.0.0.1:8001/api/chat" \
          -H "Content-Type: application/json" \
          -d "{\"message\":$(echo "$Q" | jq -Rs .)}" 2>/dev/null | \
          jq -r '.response // .text // empty' 2>/dev/null)
        if [ -n "$RESP" ] && [ "$RESP" != "null" ]; then
          echo "$RESP"
          return 0
        fi
        return 1
      }

      case "$MODE" in
        ask)
          shift || true
          Q="$*"
          if [ -z "$Q" ]; then
            echo "Usage: gavio ask <domanda>"
            exit 1
          fi
          if try_real_gavio "$Q"; then
            :
          else
            echo "[DEMO mode - GAVIO real non packaged]"
            reply_for "$Q"
          fi
          ;;

        gui)
          # GUI mode: zenity dialog box chat
          while true; do
            Q=$(zenity --entry --width=600 --title="GAVIO Chat" \
                --text="Scrivi a GAVIO (vuoto per uscire):" 2>/dev/null)
            [ -z "$Q" ] && break
            ANS=$(reply_for "$Q")
            zenity --info --width=700 --title="GAVIO" \
              --text="<b>Tu:</b> $Q\n\n<b>GAVIO:</b> $ANS" 2>/dev/null
          done
          ;;

        status)
          echo "── GAVIO ──"
          echo "Stato: DEMO MODE (scaffolding)"
          echo "Real GAVIO: non packaged (Step 30/51 roadmap)"
          if curl -s -m 2 http://127.0.0.1:8001/health >/dev/null 2>&1; then
            echo "Prompt filter: ATTIVO (Step 21)"
          else
            echo "Prompt filter: spento"
          fi
          if systemctl is-active ollama.service >/dev/null 2>&1; then
            echo "Ollama: ATTIVO"
            curl -s http://127.0.0.1:11434/api/tags 2>/dev/null | jq -r '.models[].name' 2>/dev/null | head -5 || true
          else
            echo "Ollama: spento"
          fi
          if systemctl is-active gavio.service >/dev/null 2>&1; then
            echo "gavio.service: ATTIVO"
          else
            echo "gavio.service: spento (atteso, scaffolding)"
          fi
          ;;

        docs)
          echo "Docs GAVIO + SOLEM:"
          echo "  https://github.com/rguidotti-design/solem"
          echo "  docs/GAPS-VERO-OS.md  cosa manca"
          echo "  /etc/solem/gavio-*.md sui moduli"
          ;;

        chat|tui|"")
          # Chat REPL interattiva
          cat <<'BANNER'

  ╭───────────────────────────────────────────────╮
  │  GAVIO Chat - DEMO MODE                       │
  │  Cervello reale: scaffolding (Step 30/51)     │
  │  Digita 'exit' per uscire                     │
  ╰───────────────────────────────────────────────╯

BANNER
          while true; do
            printf "\033[33mTu>\033[0m "
            read -r Q
            [ -z "$Q" ] && continue
            if [ "$Q" = "exit" ] || [ "$Q" = "quit" ] || [ "$Q" = "q" ]; then
              echo "Ciao."
              break
            fi
            printf "\033[36mGAVIO>\033[0m "
            if try_real_gavio "$Q"; then
              :
            else
              reply_for "$Q"
            fi
            echo
          done
          ;;

        *)
          echo "Usage: gavio [chat|ask <q>|gui|status|docs]"
          ;;
      esac
    '';
  };
in {
  options.solem.gavioChatDemo = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Comando 'gavio' chat demo (mockup finche' real GAVIO non packaged)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ gavioChatScript ];

    environment.etc."xdg/applications/gavio-chat.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=GAVIO Chat
      Comment=Chat con GAVIO (DEMO mode finche' non packaged)
      Exec=gnome-terminal -- bash -c "gavio chat; read -p 'Premi Enter...'"
      Icon=face-smile
      Terminal=false
      Categories=AudioVideo;Education;Network;
    '';

    environment.etc."xdg/applications/gavio-chat-gui.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=GAVIO Chat (GUI)
      Comment=Chat GUI con GAVIO via zenity dialog
      Exec=gavio gui
      Icon=face-smile
      Terminal=false
      Categories=AudioVideo;Education;Network;
    '';
  };
}
