{ config, pkgs, lib, ... }:

# SOLEM WELCOME WIZARD — Step 39: first-user experience post-install.
#
# Single responsibility: SOLO un wizard interattivo che si avvia al PRIMO
# login dopo install. Guida l'utente attraverso setup essenziali:
#   - Cambio password (se default "gavio")
#   - Backup passphrase generation
#   - SSH key import
#   - Vault init
#   - Canary enrollment
#   - Choose: enable WireGuard mesh / Tor onion / Web dashboard
#
# Friday-like: "buongiorno, sono SOLEM. Iniziamo configurando le tue
# difese — ci vogliono 5 minuti."
#
# Tutto FOSS (bash + dialog/whiptail/gum).

let
  cfg = config.solem.welcomeWizard;
in {
  options.solem.welcomeWizard = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Wizard interattivo al primo login post-install.";
    };

    markerFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/solem/welcome-completed";
      description = "Marker file: wizard mostrato una volta. Rimuovere per re-show.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d /var/lib/solem 0750 root root - -"
    ];

    environment.systemPackages = [
      pkgs.gum  # CLI UI moderna stilizzata
      (pkgs.writeShellApplication {
        name = "solem-welcome";
        runtimeInputs = with pkgs; [ coreutils gum systemd openssh ];
        text = ''
          MARKER="${cfg.markerFile}"
          FORCE="''${1:-}"

          if [ -f "$MARKER" ] && [ "$FORCE" != "--force" ]; then
            gum style --foreground 212 "Welcome wizard gia' completato."
            echo "Per re-eseguire: solem-welcome --force"
            exit 0
          fi

          clear
          gum style \
            --border double --margin "1 2" --padding "1 4" \
            --border-foreground 220 --foreground 220 \
            "SOLEM — AI-native OS" \
            "" \
            "Buongiorno. Sono il tuo nuovo sistema." \
            "Imposto le difese: 5 minuti, 6 passi."

          echo ""
          gum confirm "Iniziamo?" || { echo "Cancellato"; exit 0; }

          # ─── 1. CAMBIO PASSWORD ─────────────────────────────────
          echo ""
          gum style --foreground 220 --bold "[1/6] Cambio password utente"
          gum style --foreground 245 "Default install: utente=gavio, pass=gavio. CAMBIA SUBITO."
          if gum confirm "Cambia password ora?"; then
            passwd
          else
            gum style --foreground 196 "⚠ password default = LASCIATA. Cambia SUBITO con: passwd"
          fi

          # ─── 2. SSH KEY ──────────────────────────────────────────
          echo ""
          gum style --foreground 220 --bold "[2/6] SSH key per accesso remoto"
          if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
            if gum confirm "Genera SSH keypair ed25519?"; then
              ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N ""
              gum style --foreground 82 "✓ SSH key generata. Pubblica:"
              cat "$HOME/.ssh/id_ed25519.pub"
              gum style --foreground 245 "Copia su altri server con: ssh-copy-id user@host"
            fi
          else
            gum style --foreground 82 "✓ SSH key gia' presente"
          fi

          # ─── 3. VAULT INIT ───────────────────────────────────────
          echo ""
          gum style --foreground 220 --bold "[3/6] Secret vault (age encrypted)"
          if command -v solem-vault >/dev/null; then
            if [ ! -f "$HOME/.local/share/solem/vault-master.key" ]; then
              if gum confirm "Inizializza vault locale per gestire secret?"; then
                solem-vault init
              fi
            else
              gum style --foreground 82 "✓ vault gia' inizializzato"
            fi
          else
            gum style --foreground 245 "(solem.vault modulo non abilitato — skip)"
          fi

          # ─── 4. BACKUP PASSPHRASE ────────────────────────────────
          echo ""
          gum style --foreground 220 --bold "[4/6] Backup passphrase critiche"
          gum style --foreground 245 "Salva su USB esterno OFFLINE (non lasciare sul sistema!)"

          BACKUP_DIR="/media/usb-backup"
          if [ -d "$BACKUP_DIR" ]; then
            if gum confirm "Copia secret in $BACKUP_DIR?"; then
              [ -f /etc/solem/backup-passphrase ] && sudo cp /etc/solem/backup-passphrase "$BACKUP_DIR/" || true
              [ -d "$HOME/.local/share/solem" ] && cp -r "$HOME/.local/share/solem" "$BACKUP_DIR/solem-vault-keys" || true
              gum style --foreground 82 "✓ Backup completato. Rimuovi USB ORA."
            fi
          else
            gum style --foreground 245 "(no $BACKUP_DIR mounted — backup manuale richiesto)"
            echo "  Files critici da copiare manualmente:"
            echo "    /etc/solem/backup-passphrase  (se solem-backup-encrypted abilitato)"
            echo "    ~/.local/share/solem/vault-master.key  (se solem-vault abilitato)"
            echo "    /var/lib/sbctl/keys/  (se Secure Boot Step 32)"
          fi

          # ─── 5. CANARY ───────────────────────────────────────────
          echo ""
          gum style --foreground 220 --bold "[5/6] Canary honey tokens"
          if command -v solem-canary >/dev/null; then
            CANARY_DIR="/etc/solem/canary"
            if [ -d "$CANARY_DIR" ]; then
              COUNT=$(ls "$CANARY_DIR" 2>/dev/null | wc -l)
              gum style --foreground 82 "✓ $COUNT canary file attivi in $CANARY_DIR"
              gum style --foreground 245 "Trigger automatico kill switch su read."
            else
              gum style --foreground 245 "(modulo solem.canary disabilitato — abilita in flake per protezione)"
            fi
          fi

          # ─── 6. SCEGLI FEATURE ───────────────────────────────────
          echo ""
          gum style --foreground 220 --bold "[6/6] Feature opzionali da abilitare"
          gum style --foreground 245 "Seleziona cosa abilitare (richiede edit flake + nixos-rebuild):"

          CHOICES=$(gum choose --no-limit \
            "WireGuard mesh (remote access cifrato)" \
            "Tor onion service (anonymous access)" \
            "Web dashboard (Friday HUD browser)" \
            "Self-redteam + heal (auto-attack notturno)" \
            "Suricata IDS (network intrusion detection)" \
            "Auto-update CVE patch" \
            "Backup automatico borg+age" \
            "FIDO2 hardware MFA" \
            "Calamares installer (gia' attivo se ISO)" \
            "Nessuna — config gia' a posto")

          if echo "$CHOICES" | grep -q "WireGuard"; then
            echo "  solem.wireguardMesh.enable = true; → poi nixos-rebuild switch"
          fi
          if echo "$CHOICES" | grep -q "Tor"; then
            echo "  solem.torOnion.enable = true;"
          fi
          if echo "$CHOICES" | grep -q "Web dashboard"; then
            echo "  solem.webDashboard.enable = true;  # http://127.0.0.1:8088"
          fi
          if echo "$CHOICES" | grep -q "redteam"; then
            echo "  solem.selfRedteam.enable = true;"
            echo "  solem.selfHeal.enable = true;"
          fi
          if echo "$CHOICES" | grep -q "Suricata"; then
            echo "  solem.suricataIds.enable = true;"
          fi
          if echo "$CHOICES" | grep -q "Auto-update"; then
            echo "  solem.autoUpdate.enable = true;"
          fi
          if echo "$CHOICES" | grep -q "Backup"; then
            echo "  solem.backupEncrypted.enable = true;"
          fi
          if echo "$CHOICES" | grep -q "FIDO2"; then
            echo "  solem.fido2Mfa.enable = true;"
          fi

          # ─── FINE ────────────────────────────────────────────────
          echo ""
          gum style --border rounded --margin "1 0" --padding "1 2" \
            --border-foreground 220 --foreground 245 \
            "Setup base completato." \
            "" \
            "Prossimi step:" \
            "  solem-demo                  # demo 10 capability" \
            "  solem status                # dashboard" \
            "  solem help                  # tutti i comandi" \
            "  http://127.0.0.1:8088       # web HUD (se abilitato)"

          sudo mkdir -p /var/lib/solem
          sudo touch "$MARKER"
          sudo chmod 644 "$MARKER"
          echo ""
          gum style --foreground 82 "✓ Marker scritto in $MARKER (wizard non re-show)"
        '';
      })
    ];

    # Autostart su login (XDG desktop autostart per Hyprland/GNOME/KDE)
    environment.etc."xdg/autostart/solem-welcome.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=SOLEM Welcome
      Comment=Wizard configurazione iniziale SOLEM
      Exec=alacritty -e solem-welcome
      Icon=preferences-system
      Terminal=true
      X-GNOME-Autostart-enabled=true
    '';

    # Su tty (no desktop): mostra hint in motd
    users.motd = lib.mkAfter ''

      ╔═════════════════════════════════════════════════════════╗
      ║  Primo accesso a SOLEM?                                 ║
      ║  Esegui:  solem-welcome                                 ║
      ║  Per saltare: touch /var/lib/solem/welcome-completed    ║
      ╚═════════════════════════════════════════════════════════╝
    '';

    environment.etc."solem/welcome-wizard.md".text = ''
      # SOLEM Welcome Wizard (Step 39)

      Wizard interattivo al primo login post-install. Guida 6 step:
      1. Cambio password (default install = "gavio")
      2. SSH keypair ed25519 generation
      3. Vault init (solem-vault)
      4. Backup passphrase su USB esterno
      5. Canary status check
      6. Scelta feature opzionali da abilitare

      Mostrato UNA volta. Marker: /var/lib/solem/welcome-completed.
      Re-show: solem-welcome --force.

      ## Autostart
      Su sessione grafica (Hyprland/GNOME): autostart desktop file launch
      Alacritty con solem-welcome.

      Su tty (no desktop): motd mostra hint al login.

      ## CLI UI
      Usa `gum` (Charm, MIT): UI moderna stilizzata navy/gold (Cormorant Mono).
    '';
  };
}
