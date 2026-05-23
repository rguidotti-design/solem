{ config, pkgs, lib, ... }:

# SOLEM PDF TOOLS — merge/split/OCR/annotate per PDF.
#
# Single responsibility: SOLO installare tool PDF FOSS + CLI wrapper
# `solem-pdf` con sub-comando user-friendly.

let
  cfg = config.solem.pdfTools;

  pdfCli = pkgs.writeShellApplication {
    name = "solem-pdf";
    runtimeInputs = with pkgs; [ qpdf poppler_utils ocrmypdf imagemagick ];
    text = ''
      ACTION="''${1:-help}"
      shift || true

      case "$ACTION" in
        merge)
          OUT="merged.pdf"
          # Ultimo argomento = output se finisce in .pdf
          if [ $# -ge 2 ] && [[ "''${!#}" =~ \.pdf$ ]]; then
            OUT="''${!#}"
            set -- "''${@:1:$#-1}"
          fi
          qpdf --empty --pages "$@" -- "$OUT"
          echo "Merged → $OUT"
          ;;
        split)
          SRC="''${1:?Usage: solem-pdf split <input.pdf>}"
          OUT_DIR="''${SRC%.pdf}_pages"
          mkdir -p "$OUT_DIR"
          qpdf --split-pages=1 "$SRC" "$OUT_DIR/page-%d.pdf"
          echo "Split → $OUT_DIR/"
          ;;
        ocr)
          SRC="''${1:?Usage: solem-pdf ocr <input.pdf> [output.pdf]}"
          OUT="''${2:-''${SRC%.pdf}_ocr.pdf}"
          ocrmypdf -l ita+eng --rotate-pages --deskew "$SRC" "$OUT"
          echo "OCR → $OUT"
          ;;
        extract-text)
          SRC="''${1:?Usage: solem-pdf extract-text <input.pdf>}"
          pdftotext -layout "$SRC" -
          ;;
        extract-images)
          SRC="''${1:?Usage: solem-pdf extract-images <input.pdf>}"
          OUT_DIR="''${SRC%.pdf}_images"
          mkdir -p "$OUT_DIR"
          pdfimages -all "$SRC" "$OUT_DIR/img"
          echo "Images → $OUT_DIR/"
          ;;
        compress)
          SRC="''${1:?Usage: solem-pdf compress <input.pdf> [output.pdf]}"
          OUT="''${2:-''${SRC%.pdf}_compressed.pdf}"
          # Strategy: reduce image quality to 150dpi
          gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 \
             -dPDFSETTINGS=/ebook -dNOPAUSE -dQUIET -dBATCH \
             -sOutputFile="$OUT" "$SRC"
          echo "Compressed → $OUT ($(du -h "$OUT" | cut -f1))"
          ;;
        rotate)
          SRC="''${1:?Usage: solem-pdf rotate <input.pdf> <deg>}"
          DEG="''${2:-90}"
          OUT="''${SRC%.pdf}_rotated.pdf"
          qpdf --rotate=+"$DEG" "$SRC" "$OUT"
          echo "Rotated → $OUT"
          ;;
        encrypt)
          SRC="''${1:?Usage: solem-pdf encrypt <input.pdf> <password>}"
          PASS="''${2:?password mancante}"
          OUT="''${SRC%.pdf}_encrypted.pdf"
          qpdf --encrypt "$PASS" "$PASS" 256 -- "$SRC" "$OUT"
          echo "Encrypted → $OUT"
          ;;
        decrypt)
          SRC="''${1:?Usage: solem-pdf decrypt <input.pdf> <password>}"
          PASS="''${2:?password mancante}"
          OUT="''${SRC%.pdf}_decrypted.pdf"
          qpdf --password="$PASS" --decrypt "$SRC" "$OUT"
          echo "Decrypted → $OUT"
          ;;
        info)
          SRC="''${1:?Usage: solem-pdf info <input.pdf>}"
          pdfinfo "$SRC"
          ;;
        *)
          echo "solem-pdf — utility PDF universale (FOSS)"
          echo
          echo "  solem-pdf merge file1.pdf file2.pdf out.pdf"
          echo "  solem-pdf split input.pdf"
          echo "  solem-pdf ocr scan.pdf [out.pdf]"
          echo "  solem-pdf extract-text input.pdf"
          echo "  solem-pdf extract-images input.pdf"
          echo "  solem-pdf compress input.pdf"
          echo "  solem-pdf rotate input.pdf 90"
          echo "  solem-pdf encrypt input.pdf <password>"
          echo "  solem-pdf decrypt input.pdf <password>"
          echo "  solem-pdf info input.pdf"
          ;;
      esac
    '';
  };
in {
  options.solem.pdfTools = {
    enable = lib.mkEnableOption "PDF tools (merge/split/OCR/compress/encrypt)";

    annotator = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Xournal++ + Okular GUI per annotare/firmare";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      pdfCli
      qpdf poppler_utils ocrmypdf
      ghostscript
      tesseract     # OCR engine
      img2pdf
    ] ++ lib.optionals cfg.annotator [
      xournalpp
      okular
      masterpdfeditor4
    ];
  };
}
