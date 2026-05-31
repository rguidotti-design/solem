{ config, pkgs, lib, ... }:

# SOLEM APP STORE — Step 43: GUI app store visuale (GNOME Software + Flatpak).
#
# Single responsibility: SOLO orchestrazione gnome-software (GUI app store)
# + Flatpak backend per install one-click ~3000+ app sandbox.
#
# Filosofia: per "vero OS user-facing" serve "click su icona → install".
# Nix è bellissimo ma richiede edit flake. Flatpak compensa.
#
# Stack:
#   - gnome-software: GUI app store con screenshot, ratings, search
#   - flatpak: sandbox runtime per app (Flathub.org repo gratis)
#   - flatpak-builder: per pacchettizzare custom (opt-in)
#
# Tutto FOSS (GNOME Software GPL-2.0, Flatpak LGPL-2.1).

let
  cfg = config.solem.appStore;
in {
  options.solem.appStore = {
    enable = lib.mkEnableOption "GNOME Software + Flatpak (GUI app store)";

    enableFlathub = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Aggiungi Flathub repo (~3000 app gratis sandbox)";
    };

    enableNixIntegration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        GNOME Software mostra ANCHE nix packages installabili
        (via packagekit-nix backend opzionale).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.flatpak.enable = true;

    # GNOME Software: pacchetto principale
    environment.systemPackages = with pkgs; [
      gnome-software
      flatpak
      (pkgs.writeShellApplication {
        name = "solem-app";
        runtimeInputs = with pkgs; [ coreutils flatpak gnome-software ];
        text = ''
          ACTION="''${1:-store}"
          shift || true

          case "$ACTION" in
            store|open)
              # Apre GNOME Software GUI
              gnome-software &
              echo "GNOME Software aperto. Cerca + install grafico."
              ;;

            search)
              Q="''${1:?Usage: solem-app search <query>}"
              echo "── Flatpak Flathub ──"
              flatpak search "$Q" 2>/dev/null | head -20
              ;;

            install)
              APP="''${1:?Usage: solem-app install <flatpak-id>}"
              flatpak install -y flathub "$APP"
              ;;

            list|installed)
              echo "── Flatpak installed ──"
              flatpak list 2>/dev/null
              ;;

            update)
              echo "── Update Flatpak apps ──"
              flatpak update -y
              ;;

            remove|uninstall)
              APP="''${1:?Usage: solem-app remove <app-id>}"
              flatpak uninstall -y "$APP"
              ;;

            help|--help|-h|*)
              cat <<'HELP'
solem-app — GUI app store + Flatpak CLI

  store / open         apre GNOME Software (GUI)
  search <q>           cerca su Flathub
  install <id>         installa Flatpak (es. org.signal.Signal)
  list                 elenca installed
  update               aggiorna tutte
  remove <id>          disinstalla

Flathub: ~3000 app gratuite (sandbox sicuro).
  https://flathub.org

Per pacchetti Nix system-wide: edit flake + nixos-rebuild.
Per app utente quick: usa Flatpak.
HELP
              ;;
          esac
        '';
      })
    ];

    # Flathub repo auto-add (one-time al primo flatpak run)
    systemd.services.solem-flathub-init = lib.mkIf cfg.enableFlathub {
      description = "SOLEM: aggiungi Flathub repo (one-time)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        if ! ${pkgs.flatpak}/bin/flatpak remotes 2>/dev/null | grep -q flathub; then
          ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists \
            flathub https://flathub.org/repo/flathub.flatpakrepo || true
        fi
      '';
    };

    # XDG portal per Flatpak (necessario per file picker, ecc.)
    xdg.portal = {
      enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
        xdg-desktop-portal-hyprland
      ];
    };

    environment.etc."solem/app-store.md".text = ''
      # SOLEM App Store (Step 43)

      Stack visuale per install app one-click.

      ## Componenti
      - **GNOME Software**: GUI app store (screenshot, ratings, search)
      - **Flatpak**: sandbox runtime (~3000 app gratis su Flathub)
      - **XDG Portals**: dialog file picker / camera / location

      ## Workflow utente
      ```bash
      solem-app store              # apre GUI
      # oppure cerca a CLI:
      solem-app search signal
      solem-app install org.signal.Signal
      ```

      Flathub repo auto-aggiunto al primo boot.

      ## App popolari Flathub
      - org.signal.Signal — messaging
      - im.riot.Riot — Matrix client
      - com.spotify.Client — musica
      - com.discordapp.Discord — chat gaming
      - org.libreoffice.LibreOffice — office (alt al system pkg)
      - com.obsproject.Studio — OBS streaming
      - md.obsidian.Obsidian — notes (proprietario, popolare)
      - org.gimp.GIMP — image editor
      - org.audacityteam.Audacity — audio
      - net.cozic.joplin_desktop — note (FOSS)

      ## Vantaggi Flatpak vs Nix system pkg
      - Install user-only (no rebuild)
      - Sandbox sicuro (filesystem isolato)
      - Update indipendenti
      - 3000+ app gia' pacchettizzate

      ## Svantaggi
      - Storage: ogni Flatpak include runtime (~500MB-1GB extra)
      - Performance: ~5% overhead vs nativo
      - Permission management: serve GUI (Flatseal, gia' incluso?)

      ## Limiti onesti
      - Non sostituisce Nix per server / system packages
      - User-facing app SI, daemon/service NO (usa Nix)
    '';
  };
}
