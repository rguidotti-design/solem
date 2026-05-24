{ config, pkgs, lib, ... }:

# SOLEM PHOTOS MEMORIES — face clustering + auto-tag con digiKam (FOSS).
#
# Single responsibility: SOLO installare digiKam (FOSS KDE, GPL) che ha
# native face recognition + auto-tag + geotag + albums automatici per
# data/luogo. Alternativa FOSS a Apple Photos / Google Photos memories.
#
# digiKam usa OpenCV per face detection (offline, no cloud).

let
  cfg = config.solem.photosMemories;

  photosCli = pkgs.writeShellApplication {
    name = "solem-photos";
    runtimeInputs = with pkgs; [ coreutils digikam exiftool ];
    text = ''
      ACTION="''${1:-help}"
      shift || true

      LIB="''${PHOTOS_LIB:-$HOME/Pictures}"

      case "$ACTION" in
        open)
          digikam &
          ;;

        scan)
          # digiKam CLI tools per scan e indicizzazione
          echo "Scansione $LIB..."
          digikamtags -f -r "$LIB" 2>/dev/null || \
          echo "Per scan automatico, apri digiKam GUI → Tools → Maintenance → Scan for face detection"
          ;;

        stats)
          # Stats su album foto
          COUNT=$(find "$LIB" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.heic" \) 2>/dev/null | wc -l)
          SIZE=$(du -sh "$LIB" 2>/dev/null | awk '{print $1}')
          echo "── Foto in $LIB ──"
          echo "  Numero:     $COUNT"
          echo "  Spazio:     $SIZE"
          ;;

        organize)
          # Organizza foto per anno/mese basato su EXIF
          echo "Organizza foto da $LIB per anno-mese (EXIF DateTimeOriginal)..."
          find "$LIB" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) | while read -r img; do
            DATE=$(exiftool -DateTimeOriginal -s -s -s "$img" 2>/dev/null | head -1)
            if [ -n "$DATE" ]; then
              YYYY=$(echo "$DATE" | cut -c1-4)
              MM=$(echo "$DATE" | cut -c6-7)
              DEST="$LIB/Organized/$YYYY-$MM"
              mkdir -p "$DEST"
              mv -n "$img" "$DEST/" 2>/dev/null && echo "→ $YYYY-$MM/$(basename "$img")"
            fi
          done
          ;;

        memories)
          # Memorie: foto di N anni fa stesso mese
          YEARS_AGO="''${1:-1}"
          YYYY=$(date -d "$YEARS_AGO years ago" +%Y 2>/dev/null || date -v-"$YEARS_AGO"y +%Y)
          MM=$(date +%m)
          DIR="$LIB/Organized/$YYYY-$MM"
          if [ -d "$DIR" ]; then
            echo "── Memorie $YEARS_AGO anno/i fa ($YYYY-$MM) ──"
            ls "$DIR" | head -20
            echo
            echo "Apri album: thunar/nautilus '$DIR'"
          else
            echo "Nessuna foto per $YYYY-$MM (organize prima)"
          fi
          ;;

        help|--help|-h|*)
          cat <<'HELP'
solem-photos — gestione foto con face recognition FOSS

  open               apre digiKam GUI (face recognition + tag)
  scan               scan libreria + face detection
  stats              numero foto + spazio
  organize           sposta foto per anno-mese (EXIF)
  memories <years>   foto di N anni fa stesso mese

PHOTOS_LIB env = $HOME/Pictures default.

digiKam (FOSS GPL-3.0):
  - Face recognition offline (OpenCV)
  - Auto-tag geolocation (EXIF GPS)
  - Album cronologici automatici
  - Riconoscimento volti (tu lo etichetti una volta, lui propaga)
  - Niente cloud, tutto locale

Alternative FOSS:
  - Immich (self-host server + iOS/Android app, ML auto-tag)
  - Photoview (Go server semplice)

Tutto FOSS. 0 €.
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.photosMemories = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Installa digiKam + `solem-photos` CLI (FOSS, face recognition)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      photosCli
      digikam
      exiftool
    ];
  };
}
