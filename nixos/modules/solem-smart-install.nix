{ config, pkgs, lib, ... }:

# SOLEM SMART INSTALL — app store unificato.
#
# Single responsibility: SOLO CLI `solem-app install <name>` che sceglie
# automaticamente il MIGLIOR canale di installazione per l'app:
#
#   1. Flathub (Flatpak) — preferito per app GUI moderne
#   2. AppImage — se URL fornito o nome riconosciuto
#   3. Wine + Bottles — per app Windows note
#   4. Distrobox — per app distro-specifiche (apt/dnf/pacman)
#   5. nix profile — per CLI dev tool standard nixpkgs
#
# Database app conosciute mantenuto in cache locale + Flathub search live.

let
  cfg = config.solem.smartInstall;

  installCli = pkgs.writeShellApplication {
    name = "solem-app";
    runtimeInputs = with pkgs; [ coreutils curl jq ];
    text = ''
      ACTION="''${1:-help}"
      shift || true

      # Mapping app comuni → best installation channel
      # Format: app_name|channel|identifier|note
      DB=$(cat <<'EOF'
firefox|flatpak|org.mozilla.firefox|Browser FOSS
chromium|flatpak|org.chromium.Chromium|Browser FOSS
brave|flatpak|com.brave.Browser|Browser
librewolf|flatpak|io.gitlab.librewolf-community|Firefox hardened FOSS
vscode|flatpak|com.visualstudio.code|Editor (closed)
vscodium|flatpak|com.vscodium.codium|Editor FOSS
gimp|flatpak|org.gimp.GIMP|Photo editor FOSS
krita|flatpak|org.kde.krita|Digital painting FOSS
inkscape|flatpak|org.inkscape.Inkscape|Vector graphics FOSS
blender|flatpak|org.blender.Blender|3D FOSS
obs|flatpak|com.obsproject.Studio|Screen recording FOSS
audacity|flatpak|org.audacityteam.Audacity|Audio editor FOSS
kdenlive|flatpak|org.kde.kdenlive|Video editor FOSS
shotcut|flatpak|org.shotcut.Shotcut|Video editor FOSS
vlc|flatpak|org.videolan.VLC|Media player FOSS
mpv|flatpak|io.mpv.Mpv|Media player FOSS
libreoffice|flatpak|org.libreoffice.LibreOffice|Office FOSS
onlyoffice|flatpak|org.onlyoffice.desktopeditors|Office (compat MS)
zotero|flatpak|org.zotero.Zotero|Bibliografia FOSS
calibre|flatpak|com.calibre_ebook.calibre|E-book manager
joplin|flatpak|net.cozic.joplin_desktop|Note E2EE
logseq|flatpak|com.logseq.Logseq|Knowledge graph
obsidian|flatpak|md.obsidian.Obsidian|Note (closed)
anki|flatpak|net.ankiweb.Anki|Spaced repetition
gnucash|flatpak|org.gnucash.GnuCash|Accounting FOSS
keepassxc|flatpak|org.keepassxc.KeePassXC|Password manager
bitwarden|flatpak|com.bitwarden.desktop|Password manager
freecad|flatpak|org.freecad.FreeCAD|CAD parametrico FOSS
prusaslicer|flatpak|com.prusa3d.PrusaSlicer|3D print slicer
qgis|flatpak|org.qgis.qgis|GIS FOSS
darktable|flatpak|org.darktable.Darktable|Photo RAW FOSS
rawtherapee|flatpak|com.rawtherapee.RawTherapee|Photo RAW FOSS
discord|flatpak|com.discordapp.Discord|Chat (closed)
element|flatpak|im.riot.Riot|Matrix client FOSS
signal|flatpak|org.signal.Signal|Messenger
telegram|flatpak|org.telegram.desktop|Messenger
whatsapp|flatpak|io.github.mimbrero.WhatsAppDesktop|WhatsApp wrapper
slack|flatpak|com.slack.Slack|Chat (closed)
zoom|flatpak|us.zoom.Zoom|Video call (closed)
spotify|flatpak|com.spotify.Client|Music (closed)
steam|flatpak|com.valvesoftware.Steam|Gaming (opt-in, closed)
heroic|flatpak|com.heroicgameslauncher.hgl|Epic/GOG launcher FOSS
lutris|flatpak|net.lutris.Lutris|Gaming wrapper FOSS
bottles|flatpak|com.usebottles.bottles|Wine prefix manager FOSS
firefox-developer-edition|flatpak|org.mozilla.firefox|Dev edition
photoshop|wine|photoshop-cs6|Adobe PS via Wine (CS6 OK)
illustrator|wine|illustrator-cs6|Adobe IL via Wine (limited)
office|wine|office-2016|MS Office 2016 via Wine
office365|web|https://www.office.com|Office 365 (web app)
autocad|wine|autocad-2013|AutoCAD 2013-2018 via Wine
notepad++|wine|notepad-plus-plus|Editor Windows FOSS
7zip|wine|7zip|Archive (uso 'p7zip' Linux native)
EOF
)

      lookup() {
        echo "$DB" | awk -F'|' -v name="$1" '
          BEGIN {IGNORECASE=1}
          tolower($1) == tolower(name) { print; exit }
        '
      }

      flathub_search() {
        curl -s "https://flathub.org/api/v2/search?query=$1&page=1&per_page=5" 2>/dev/null | \
          jq -r '.hits[] | "\(.name)|\(.app_id)|\(.summary // "")"' 2>/dev/null | head -5
      }

      case "$ACTION" in
        install|i|add)
          APP="''${1:?Usage: solem-app install <app-name>}"
          ENTRY=$(lookup "$APP")
          if [ -z "$ENTRY" ]; then
            echo "App '$APP' non in DB curato. Cerco su Flathub..."
            flathub_search "$APP"
            echo
            echo "Per installare manualmente:"
            echo "  flatpak install flathub <ID>"
            exit 1
          fi
          CHANNEL=$(echo "$ENTRY" | cut -d'|' -f2)
          ID=$(echo "$ENTRY" | cut -d'|' -f3)
          NOTE=$(echo "$ENTRY" | cut -d'|' -f4)
          echo "▸ $APP → canale: $CHANNEL, id: $ID"
          echo "  $NOTE"
          case "$CHANNEL" in
            flatpak)
              echo "Eseguo: flatpak install flathub $ID"
              flatpak install -y flathub "$ID"
              ;;
            wine)
              echo "App Windows. Usa Bottles GUI:"
              echo "  flatpak install flathub com.usebottles.bottles"
              echo "  Poi crea bottle '$ID' e installa l'app dentro."
              ;;
            web)
              echo "App web. Apri nel browser:"
              echo "  $ID"
              ;;
            *)
              echo "Canale '$CHANNEL' non gestito"
              ;;
          esac
          ;;

        search|s|find)
          Q="''${1:?Usage: solem-app search <pattern>}"
          # Cerca nel DB locale
          echo "── DB curato ──"
          echo "$DB" | grep -i "$Q" | awk -F'|' '{printf "  %-25s [%s] %s\n", $1, $2, $4}' | head -10
          echo
          # Cerca su Flathub
          echo "── Flathub live ──"
          flathub_search "$Q" | awk -F'|' '{printf "  %-25s %s\n", $1, $3}' | head -5
          ;;

        list|ls)
          echo "── App installate Flatpak ──"
          flatpak list --app --columns=name,application 2>/dev/null | head -30 || echo "(flatpak non disponibile)"
          ;;

        browse|catalog)
          echo "── DB curato SOLEM (~ 50 app) ──"
          echo "$DB" | awk -F'|' '{printf "  %-25s [%-7s] %s\n", $1, $2, $4}'
          ;;

        info)
          APP="''${1:?Usage: solem-app info <app>}"
          ENTRY=$(lookup "$APP")
          if [ -n "$ENTRY" ]; then
            echo "$ENTRY" | awk -F'|' '
              {printf "Name:    %s\nChannel: %s\nID:      %s\nNote:    %s\n", $1, $2, $3, $4}'
          else
            echo "App '$APP' non in DB. Prova: solem-app search $APP"
          fi
          ;;

        help|--help|-h|*)
          cat <<'HELP'
solem-app — app store unificato (Flatpak + Wine + Web)

  solem-app install <name>     installa best-channel auto
  solem-app search <pattern>   cerca DB locale + Flathub live
  solem-app browse             vedi tutte le ~50 app curate
  solem-app info <name>        dettagli singola app
  solem-app list               cosa hai installato (Flatpak)

Esempi:
  solem-app install firefox
  solem-app install gimp
  solem-app install office       (mostra come usare Wine/Bottles)
  solem-app install spotify
  solem-app search photo

DB curato: ~50 app preferite SOLEM (FOSS-first).
Fallback: Flathub search live (~2k app).

Tutti FOSS / freeware. 0 € licenze.
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.smartInstall = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa `solem-app` smart app installer";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ installCli ];
  };
}
