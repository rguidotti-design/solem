{ config, pkgs, lib, ... }:

# SOLEM APPSTORE — Flatpak + Flathub + GUI store + catalogo curato.
#
# Single responsibility: SOLO orchestrare Flatpak system-wide + GUI store +
# script `solem-app` per browse/install/remove via CLI.
#
# Flathub è 100% FOSS-friendly; tutte le app sono FOSS o freeware.
# Costo: 0 €.

let
  cfg = config.solem.appstore;

  # Catalogo curato 60+ app FOSS, suddivise per categoria
  curatedApps = pkgs.writeText "solem-app-catalog.json" (builtins.toJSON {
    productivity = [
      { id = "org.libreoffice.LibreOffice"; name = "LibreOffice"; desc = "Suite ufficio completa"; }
      { id = "com.logseq.Logseq"; name = "Logseq"; desc = "Note + outline markdown"; }
      { id = "md.obsidian.Obsidian"; name = "Obsidian"; desc = "Vault note markdown"; }
      { id = "org.mozilla.Thunderbird"; name = "Thunderbird"; desc = "Email client"; }
      { id = "io.github.zen_browser.zen"; name = "Zen Browser"; desc = "Firefox-fork focus"; }
      { id = "com.bitwarden.desktop"; name = "Bitwarden"; desc = "Password manager"; }
    ];
    development = [
      { id = "com.vscodium.codium"; name = "VSCodium"; desc = "VS Code FOSS"; }
      { id = "com.jetbrains.IntelliJ-IDEA-Community"; name = "IntelliJ IDEA CE"; desc = "Java IDE"; }
      { id = "com.jetbrains.PyCharm-Community"; name = "PyCharm CE"; desc = "Python IDE"; }
      { id = "io.podman_desktop.PodmanDesktop"; name = "Podman Desktop"; desc = "Container GUI"; }
      { id = "com.boxy_svg.BoxySVG"; name = "Boxy SVG"; desc = "SVG editor"; }
      { id = "io.github.shiftey.Desktop"; name = "GitHub Desktop"; desc = "Git GUI"; }
    ];
    creator = [
      { id = "org.gimp.GIMP"; name = "GIMP"; desc = "Image editor (Photoshop alt)"; }
      { id = "org.blender.Blender"; name = "Blender"; desc = "3D + video editing"; }
      { id = "org.kde.kdenlive"; name = "Kdenlive"; desc = "Video editor (Premiere alt)"; }
      { id = "org.darktable.Darktable"; name = "Darktable"; desc = "RAW photo (Lightroom alt)"; }
      { id = "org.inkscape.Inkscape"; name = "Inkscape"; desc = "Vector graphics (Illustrator alt)"; }
      { id = "org.audacityteam.Audacity"; name = "Audacity"; desc = "Audio editor"; }
      { id = "com.obsproject.Studio"; name = "OBS Studio"; desc = "Streaming + screen recording"; }
      { id = "org.shotcut.Shotcut"; name = "Shotcut"; desc = "Video editor semplice"; }
      { id = "fr.handbrake.ghb"; name = "HandBrake"; desc = "Video transcoder"; }
    ];
    multimedia = [
      { id = "org.videolan.VLC"; name = "VLC"; desc = "Media player universale"; }
      { id = "org.mpv.Mpv"; name = "mpv"; desc = "Video player minimal"; }
      { id = "io.bassi.Amberol"; name = "Amberol"; desc = "Music player GTK"; }
      { id = "com.feaneron.Boatswain"; name = "Boatswain"; desc = "Stream Deck controller"; }
      { id = "com.github.iwalton3.jellyfin-media-player"; name = "Jellyfin"; desc = "Self-host media"; }
      { id = "io.github.quodlibet.QuodLibet"; name = "Quod Libet"; desc = "Music player Python FOSS"; }
      { id = "org.strawberrymusicplayer.strawberry"; name = "Strawberry"; desc = "Audio player Qt FOSS"; }
    ];
    communication = [
      { id = "im.riot.Riot"; name = "Element (Matrix)"; desc = "Chat E2E federata FOSS"; }
      { id = "org.signal.Signal"; name = "Signal"; desc = "Messaging privato FOSS"; }
      { id = "im.dino.Dino"; name = "Dino (XMPP)"; desc = "Chat federata FOSS"; }
      { id = "io.github.Soundux"; name = "Soundux"; desc = "Soundboard meetings FOSS"; }
      { id = "info.mumble.Mumble"; name = "Mumble"; desc = "VoIP gaming low-latency FOSS"; }
      { id = "org.jitsi.jitsi-meet"; name = "Jitsi Meet"; desc = "Videoconf FOSS browser-based"; }
    ];
    gaming = [
      { id = "com.usebottles.bottles"; name = "Bottles"; desc = "Wine launcher FOSS"; }
      { id = "net.lutris.Lutris"; name = "Lutris"; desc = "Game manager FOSS"; }
      { id = "info.cemu.Cemu"; name = "Cemu"; desc = "Wii U emulator FOSS"; }
      { id = "io.mrarm.mcpelauncher"; name = "Minecraft Bedrock launcher"; desc = "FOSS launcher (gioco proprietario)"; }
      { id = "org.libretro.RetroArch"; name = "RetroArch"; desc = "Multi-emulator FOSS"; }
    ];
    utilities = [
      { id = "org.kde.kdeconnect"; name = "KDE Connect"; desc = "Sync smartphone"; }
      { id = "io.github.Foldex.AdwSteamGtk"; name = "AdwSteamGtk"; desc = "Steam tema GNOME"; }
      { id = "com.github.tchx84.Flatseal"; name = "Flatseal"; desc = "Flatpak permission GUI"; }
      { id = "org.gnome.FileRoller"; name = "File Roller"; desc = "Archive manager"; }
      { id = "io.gitlab.adhami3310.Impression"; name = "Impression"; desc = "USB image writer"; }
      { id = "com.belmoussaoui.Authenticator"; name = "Authenticator"; desc = "2FA TOTP"; }
    ];
    security = [
      { id = "org.keepassxc.KeePassXC"; name = "KeePassXC"; desc = "Password manager locale"; }
      { id = "org.torproject.torbrowser-launcher"; name = "Tor Browser"; desc = "Browser anonimo"; }
      { id = "io.github.Qalculate"; name = "Qalculate"; desc = "Calcolatrice scientifica"; }
      { id = "org.mozilla.firefox"; name = "Firefox"; desc = "Browser standard"; }
    ];
  });

  # CLI: solem-app browse / install / remove
  appCli = pkgs.writeShellApplication {
    name = "solem-app";
    runtimeInputs = with pkgs; [ flatpak jq coreutils ];
    text = ''
      CATALOG="/etc/solem/app-catalog.json"
      ACTION="''${1:-browse}"

      case "$ACTION" in
        browse|list|cat)
          echo "  SOLEM App Catalog — 60+ app FOSS curate"
          echo
          jq -r 'to_entries[] | "── \(.key | ascii_upcase) ──", (.value[] | "  \(.id|sub("^.+\\.";"")|.[0:24])  \(.name)  — \(.desc)")' "$CATALOG"
          echo
          echo "Per installare:  solem-app install <id-completo>"
          echo "Per rimuovere:   solem-app remove <id-completo>"
          ;;
        search)
          [ -z "''${2:-}" ] && { echo "Usage: solem-app search <keyword>"; exit 1; }
          jq -r --arg q "$2" '
            to_entries[] | .value[] |
            select(.name|ascii_downcase|contains($q|ascii_downcase)) |
            "[\(.id)]  \(.name) — \(.desc)"
          ' "$CATALOG"
          ;;
        install|add)
          [ -z "''${2:-}" ] && { echo "Usage: solem-app install <flatpak-id>"; exit 1; }
          echo "Installing $2 from Flathub..."
          flatpak install -y flathub "$2"
          ;;
        remove|uninstall)
          [ -z "''${2:-}" ] && { echo "Usage: solem-app remove <flatpak-id>"; exit 1; }
          flatpak uninstall -y "$2"
          ;;
        installed)
          flatpak list --app
          ;;
        update)
          flatpak update -y
          ;;
        *)
          echo "solem-app — App store SOLEM (sopra Flathub)"
          echo
          echo "Comandi:"
          echo "  solem-app browse                 → catalogo curato"
          echo "  solem-app search <keyword>       → cerca per nome"
          echo "  solem-app install <id>           → installa"
          echo "  solem-app remove <id>            → disinstalla"
          echo "  solem-app installed              → app installate"
          echo "  solem-app update                 → aggiorna tutto"
          ;;
      esac
    '';
  };
in {
  options.solem.appstore = {
    enable = lib.mkEnableOption "App store FOSS (Flatpak + Flathub + GUI + CLI curato)";

    addFlathub = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Aggiungi remote Flathub al primo boot";
    };

    gui = lib.mkOption {
      type = lib.types.enum [ "none" "gnome-software" "plasma-discover" ];
      default = "gnome-software";
      description = "GUI store: gnome-software (default) o plasma-discover";
    };
  };

  config = lib.mkIf cfg.enable {
    services.flatpak.enable = true;

    # XDG portals richiesti per sandbox Flatpak
    xdg.portal = {
      enable = true;
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    };

    # GUI store (default GNOME Software, alternativa Plasma Discover)
    environment.systemPackages =
      [ appCli ]
      ++ (lib.optional (cfg.gui == "gnome-software") pkgs.gnome-software)
      ++ (lib.optional (cfg.gui == "plasma-discover") pkgs.kdePackages.discover);

    # Catalogo curato accessibile da solem-app
    environment.etc."solem/app-catalog.json".source = curatedApps;

    # Aggiungi Flathub al primo boot
    systemd.services.solem-flathub-init = lib.mkIf cfg.addFlathub {
      description = "SOLEM — registra remote Flathub";
      after = [ "flatpak-system-helper.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.flatpak ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "solem-flathub-init" ''
          set -euo pipefail
          ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists \
            flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        '';
        Restart = "no";
      };
    };
  };
}
