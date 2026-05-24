{ config, pkgs, lib, ... }:

# SOLEM QUICK LOOK — preview file rapido (macOS spacebar equiv).
#
# Single responsibility: SOLO CLI `solem-quicklook <file>` che:
# - Detecta MIME type
# - Apre con tool FOSS più adatto in modalità "view-only"
# - Esce con q/ESC
#
# Tool usati (tutti FOSS):
#   PDF       → zathura -e (embed mode)
#   immagine  → feh / sxiv / nsxiv
#   video     → mpv --keep-open --pause
#   audio     → mpv --no-video
#   testo     → bat / less
#   markdown  → glow
#   archivio  → unzip -l / tar tf
#   binario   → file + xxd head

let
  cfg = config.solem.quickLook;

  quickLookCli = pkgs.writeShellApplication {
    name = "solem-quicklook";
    runtimeInputs = with pkgs; [ coreutils file bat glow zathura mpv feh unzip ];
    text = ''
      FILE="''${1:?Usage: solem-quicklook <file>}"
      if [ ! -e "$FILE" ]; then
        echo "File non trovato: $FILE"
        exit 1
      fi

      MIME=$(file -b --mime-type "$FILE")
      EXT="''${FILE##*.}"
      EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')

      case "$MIME" in
        application/pdf)
          zathura "$FILE" &
          ;;
        image/*)
          feh --geometry 1280x800 --auto-zoom "$FILE" &
          ;;
        video/*)
          mpv --keep-open --pause "$FILE" &
          ;;
        audio/*)
          mpv --no-video "$FILE" &
          ;;
        text/markdown|text/x-markdown)
          glow -p "$FILE"
          ;;
        text/*|application/json|application/xml|application/x-yaml|application/javascript)
          bat --paging=always "$FILE"
          ;;
        application/zip|application/x-zip-compressed)
          unzip -l "$FILE" | less
          ;;
        application/x-tar|application/gzip|application/x-bzip2|application/x-xz)
          tar tf "$FILE" 2>/dev/null | less || tar tjf "$FILE" 2>/dev/null | less || tar tJf "$FILE" 2>/dev/null | less
          ;;
        application/x-7z-compressed)
          7z l "$FILE" | less
          ;;
        *)
          # Fallback: check ext + show metadata
          case "$EXT_LOWER" in
            md|markdown) glow -p "$FILE" ;;
            csv|tsv) column -t -s , "$FILE" 2>/dev/null | bat --paging=always || bat --paging=always "$FILE" ;;
            *)
              echo "── File info ──"
              file "$FILE"
              ls -lh "$FILE"
              echo
              echo "── Anteprima (primi 4KB hex) ──"
              head -c 4096 "$FILE" | xxd | head -50
              ;;
          esac
          ;;
      esac
    '';
  };
in {
  options.solem.quickLook = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa `solem-quicklook` preview universale file (FOSS, spacebar-like)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ quickLookCli ];

    # File manager binding (nautilus / nemo / thunar): l'utente lo associa
    # nel suo file manager preferito. Helper in /etc:
    environment.etc."xdg/solem/quicklook-binding.md".text = ''
      # SOLEM Quick Look — binding file manager

      ## Thunar (XFCE)
      Custom Actions → New:
        Name: Quick Look
        Command: solem-quicklook %f
        Keyboard shortcut: Space

      ## Nautilus
      ~/.local/share/nautilus/scripts/quicklook:
        #!/bin/sh
        solem-quicklook "$1"
      chmod +x

      ## Hyprland keybind (focus file manager + arg attivo)
      bind = , Space, exec, solem-quicklook "$(xclip -o)"
    '';
  };
}
