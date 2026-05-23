{ config, pkgs, lib, ... }:

# SOLEM ONBOARDING WIZARD — primo-boot tour interattivo.
#
# Single responsibility: SOLO TUI wizard primo-boot per portare l'utente
# da "ho appena installato SOLEM" a "tutto funziona" in 5 step:
#   1. Locale + timezone (default it_IT)
#   2. Utente principale + password
#   3. Mesh pair (genera identità federation Ed25519)
#   4. GAVIO key (opzionale, configura backend AI)
#   5. Backup destination (locale o nodo cloud-personal)
#
# Niente cloud, niente account remoto. 0 €.
# Risponde gap "Onboarding zero-knowledge" COMPETITIVE-GAP.md.

let
  cfg = config.solem.onboarding;

  wizardScript = pkgs.writeShellApplication {
    name = "solem-welcome";
    runtimeInputs = with pkgs; [ gum coreutils openssh openssl jq ];
    text = ''
      STATE_DIR="$HOME/.local/state/solem"
      mkdir -p "$STATE_DIR"
      DONE_FLAG="$STATE_DIR/onboarding.done"

      if [[ -f "$DONE_FLAG" && "''${1:-}" != "--force" ]]; then
        echo "Onboarding già completato. Usa --force per ripeterlo."
        exit 0
      fi

      # Banner
      gum style \
        --foreground 220 --border-foreground 220 --border double \
        --align center --width 60 --margin "1 2" --padding "1 2" \
        'SOLEM Welcome Wizard' \
        '' \
        'AI-native OS — 100% FOSS — 0 €/mese'

      # Step 1 — locale
      gum style --bold "Step 1/5 — Locale"
      LOCALE=$(gum choose "it_IT.UTF-8 (Italia)" "en_US.UTF-8 (English)" "de_DE.UTF-8 (Deutsch)" "fr_FR.UTF-8 (Français)" "es_ES.UTF-8 (Español)")
      echo "→ Locale: $LOCALE"

      # Step 2 — utente
      gum style --bold "Step 2/5 — Identità utente"
      USERNAME=$(gum input --placeholder "Nome utente (es. ruben)")
      EMAIL=$(gum input --placeholder "Email (per Nextcloud/Joplin/git)")

      # Step 3 — mesh identity
      gum style --bold "Step 3/5 — Mesh federation (Ed25519)"
      if gum confirm "Genero identità federation per pairing multi-device?"; then
        KEYFILE="$STATE_DIR/mesh-identity.key"
        if [[ ! -f "$KEYFILE" ]]; then
          ssh-keygen -t ed25519 -N "" -f "$KEYFILE" -C "solem-mesh-$USERNAME" >/dev/null
        fi
        echo "→ Chiave pubblica:"
        cat "''${KEYFILE}.pub"
      fi

      # Step 4 — GAVIO key
      gum style --bold "Step 4/5 — GAVIO (AI personale)"
      gum style --foreground 244 'GAVIO funziona di default in modalità locale (Ollama).'
      gum style --foreground 244 'Vuoi configurare un backend cloud opzionale FOSS-compatibile?'
      if gum confirm "Configura backend GAVIO?"; then
        BACKEND=$(gum choose "Ollama locale (default)" "Groq cloud (free tier)" "OpenAI-compat self-host (vLLM)" "Salta")
        echo "→ Backend: $BACKEND"
        case "$BACKEND" in
          *Ollama*)   echo 'GAVIO_BACKEND="ollama"' > "$STATE_DIR/gavio.env" ;;
          *Groq*)     KEY=$(gum input --password --placeholder "GROQ_API_KEY")
                      echo 'GAVIO_BACKEND="groq"' > "$STATE_DIR/gavio.env"
                      echo "GROQ_API_KEY=$KEY" >> "$STATE_DIR/gavio.env"
                      chmod 600 "$STATE_DIR/gavio.env" ;;
          *vLLM*)     URL=$(gum input --placeholder "http://your-server:8000")
                      echo 'GAVIO_BACKEND="openai-compat"' > "$STATE_DIR/gavio.env"
                      echo "OPENAI_BASE_URL=$URL" >> "$STATE_DIR/gavio.env" ;;
        esac
      fi

      # Step 5 — backup
      gum style --bold "Step 5/5 — Backup"
      DEST=$(gum choose "Locale (/var/backup/solem)" "Nodo SOLEM cloud-personal in LAN" "USB esterno" "Salta")
      echo "→ Destinazione backup: $DEST"
      echo "BACKUP_DEST=$DEST" > "$STATE_DIR/backup.env"

      # Done
      gum style \
        --foreground 46 --border-foreground 46 --border rounded \
        --align center --width 60 --margin "1 2" --padding "1 2" \
        'Onboarding completato! 🌱' \
        '' \
        'Prossimi passi:' \
        '• Super+Space → parla con GAVIO' \
        '• `solem-app browse` → installa app FOSS' \
        '• `solem cluster` → vedi i tuoi device'

      touch "$DONE_FLAG"
      date -Iseconds > "$DONE_FLAG"
    '';
  };

  # Hook auto-launch al primo login Wayland (graphical-session)
  autostartDesktop = pkgs.writeText "solem-welcome.desktop" ''
    [Desktop Entry]
    Type=Application
    Name=SOLEM Welcome
    Exec=alacritty -e solem-welcome
    OnlyShowIn=Hyprland;sway;
    X-GNOME-Autostart-enabled=true
  '';
in {
  options.solem.onboarding = {
    enable = lib.mkEnableOption "Primo-boot wizard interattivo (solem-welcome)";

    autoLaunch = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Lancia automaticamente al primo login grafico";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      wizardScript
      gum                # TUI elegante
      alacritty          # terminale fallback per autostart
    ];

    # Auto-start solo al primo login (controllato dal flag in $HOME)
    environment.etc."xdg/autostart/solem-welcome.desktop" =
      lib.mkIf cfg.autoLaunch { source = autostartDesktop; };
  };
}
