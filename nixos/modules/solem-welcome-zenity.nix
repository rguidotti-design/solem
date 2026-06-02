{ config, pkgs, lib, ... }:

# SOLEM WELCOME ZENITY — Wizard GUI primo login (zenity dialog).
# Sostituisce solem-welcome (CLI gum) con GUI desktop friendly.

let
  cfg = config.solem.welcomeZenity;

  wizardScript = pkgs.writeShellApplication {
    name = "solem-welcome-gui";
    runtimeInputs = with pkgs; [ coreutils zenity systemd openssh ];
    text = ''
      MARKER="/var/lib/solem/welcome-gui-completed"
      FORCE="''${1:-}"

      if [ -f "$MARKER" ] && [ "$FORCE" != "--force" ]; then
        exit 0
      fi

      zenity --info --width=500 --title="SOLEM Welcome" \
        --text="<b>Benvenuto in SOLEM</b>\n\nAI-native OS - zero-trust - 100% FOSS\n\nConfig iniziale: 3 min." || exit 0

      zenity --question --width=500 --title="Step 1/4: Password" \
        --text="Default install: gavio/gavio. Cambia password subito?" && {
        NEW_PASS=$(zenity --password --title="Nuova password gavio")
        if [ -n "$NEW_PASS" ]; then
          echo "gavio:$NEW_PASS" | sudo chpasswd && \
            zenity --info --text="Password cambiata." || true
        fi
      } || true

      if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
        zenity --question --width=500 --title="Step 2/4: SSH key" \
          --text="Genero chiave SSH ed25519?" && {
          ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N ""
          PUB=$(cat "$HOME/.ssh/id_ed25519.pub")
          zenity --info --width=600 --title="SSH key generata" \
            --text="<tt>$PUB</tt>" || true
        } || true
      fi

      CHOICES=$(zenity --list --checklist --width=600 --height=400 \
        --title="Step 3/4: Feature opt-in" \
        --text="Cosa abilitare?" \
        --column="" --column="Feature" --column="Cosa fa" \
        TRUE "Self red-team" "Auto-attack notturno" \
        TRUE "Self heal" "Auto-fix post redteam" \
        TRUE "Backup borg" "Backup encrypted 6h" \
        FALSE "WireGuard mesh" "Remote access VPN" \
        FALSE "Tor onion" "Anonymous .onion" \
        FALSE "Suricata IDS" "Network intrusion detection" \
        FALSE "FIDO2 MFA" "Yubikey richiesto" \
        TRUE "Auto-update CVE" "Daily auto-rebuild" \
        2>/dev/null || true)

      if [ -n "$CHOICES" ]; then
        zenity --info --width=700 --title="Selezionato" \
          --text="<b>Aggiungi a configuration.nix le opzioni corrispondenti:</b>\n\n$CHOICES\n\nPoi: <b>sudo nixos-rebuild switch</b>" || true
      fi

      zenity --warning --width=600 --title="Step 4/4: Backup CRITICO" \
        --text="<b>IMPORTANTE</b>: copia su USB ESTERNO:\n\n- /etc/solem/backup-passphrase\n- ~/.local/share/solem/vault-master.key\n- /var/lib/sbctl/keys/" || true

      sudo mkdir -p /var/lib/solem
      sudo touch "$MARKER"

      zenity --info --width=500 --title="Setup completato" \
        --text="<b>SOLEM pronto.</b>\n\nProssimi comandi:\n\n<tt>solem-demo</tt> walkthrough\n<tt>solem status</tt> dashboard\n<tt>solem help</tt> comandi" || true
    '';
  };
in {
  options.solem.welcomeZenity = {
    enable = lib.mkEnableOption "Welcome wizard GUI zenity";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ wizardScript pkgs.zenity ];

    environment.etc."xdg/autostart/solem-welcome-gui.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=SOLEM Welcome Setup
      Comment=Wizard configurazione iniziale SOLEM
      Exec=solem-welcome-gui
      Icon=preferences-system
      Terminal=false
      X-GNOME-Autostart-enabled=true
      OnlyShowIn=GNOME;
    '';
  };
}
