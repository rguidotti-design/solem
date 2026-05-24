{ config, pkgs, lib, ... }:

# SOLEM MULTIMEDIA TOOLS — toolkit foto/video/audio 100% FOSS.
#
# Single responsibility: SOLO tool media FOSS (download, batch image,
# screen-record GIF, audio editing, video editing). Niente codec
# proprietari non-redistribuibili di default.
#
# CLI helper `solem-media` per operazioni rapide. Costo: 0 €.

let
  mediaCli = pkgs.writeShellApplication {
    name = "solem-media";
    runtimeInputs = with pkgs; [ yt-dlp ffmpeg imagemagick coreutils ];
    text = ''
      ACTION="''${1:-help}"
      case "$ACTION" in
        download|dl)
          URL="''${2:?Usage: solem-media download <url>}"
          yt-dlp -o "%(title)s.%(ext)s" "$URL"
          ;;
        download-audio|dla|mp3)
          URL="''${2:?Usage: solem-media mp3 <url>}"
          yt-dlp -x --audio-format mp3 -o "%(title)s.%(ext)s" "$URL"
          ;;
        convert)
          SRC="''${2:?Usage: solem-media convert <input> <output>}"
          DST="''${3:?Usage: solem-media convert <input> <output>}"
          ffmpeg -i "$SRC" "$DST"
          ;;
        gif)
          # Estrai GIF da video (es. clip 5s)
          SRC="''${2:?Usage: solem-media gif <input.mp4> [start] [duration]}"
          START="''${3:-0}"
          DUR="''${4:-5}"
          ffmpeg -ss "$START" -t "$DUR" -i "$SRC" -vf "fps=15,scale=640:-1:flags=lanczos" -loop 0 "''${SRC%.*}.gif"
          ;;
        compress-video)
          SRC="''${2:?Usage: solem-media compress-video <input>}"
          ffmpeg -i "$SRC" -vcodec libx264 -crf 28 -preset slow "''${SRC%.*}-compressed.mp4"
          ;;
        resize)
          # Resize batch immagini (preserva ratio)
          DIR="''${2:?Usage: solem-media resize <dir> [width]}"
          W="''${3:-1920}"
          for img in "$DIR"/*.{jpg,jpeg,png,JPG,JPEG,PNG}; do
            [[ -f "$img" ]] || continue
            convert "$img" -resize "''${W}x>" "''${img%.*}-resized.''${img##*.}"
          done
          ;;
        webp)
          # JPG/PNG → WebP (perdita qualità minima, peso -70%)
          SRC="''${2:?Usage: solem-media webp <input>}"
          ffmpeg -i "$SRC" -quality 85 "''${SRC%.*}.webp"
          ;;
        strip-metadata)
          SRC="''${2:?Usage: solem-media strip-metadata <input>}"
          exiftool -all= "$SRC" 2>/dev/null || ffmpeg -i "$SRC" -map_metadata -1 -c copy "''${SRC%.*}-clean.''${SRC##*.}"
          ;;
        *)
          echo "solem-media — toolkit media FOSS"
          echo
          echo "  Download:"
          echo "    solem-media download <url>            video/audio (FOSS yt-dlp)"
          echo "    solem-media mp3 <url>                 solo audio MP3"
          echo
          echo "  Convert / Transform:"
          echo "    solem-media convert <in> <out>        formato libero (ffmpeg)"
          echo "    solem-media compress-video <in>       H.264 CRF 28 (peso -60%)"
          echo "    solem-media webp <in>                 → WebP (-70% peso)"
          echo "    solem-media resize <dir> [width]      batch resize"
          echo
          echo "  Estrai:"
          echo "    solem-media gif <in> [start] [dur]    clip → GIF"
          echo
          echo "  Privacy:"
          echo "    solem-media strip-metadata <in>       rimuove EXIF/metadata"
          ;;
      esac
    '';
  };

  cfg = config.solem.multimediaTools;
in {
  options.solem.multimediaTools = {
    enable = lib.mkEnableOption "Tool multimedia FOSS (yt-dlp, ffmpeg, GIMP, Audacity, Kdenlive, OBS)";

    pro = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Suite "pro" FOSS: DaVinci-Resolve-alternative (Kdenlive + LosslessCut),
        Audio multitrack (Ardour), DAW (LMMS), Inkscape, Scribus, Krita advanced.
      '';
    };

    streaming = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Live streaming FOSS (OBS Studio + Owncast self-host)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; lib.flatten [
      [
        mediaCli

        # CLI core
        yt-dlp
        ffmpeg-full
        imagemagick
        exiftool

        # GUI media base
        vlc
        mpv
        celluloid     # GTK GUI mpv
        gimp          # foto editor (Photoshop-alt)
        krita         # disegno digitale
        darktable     # photo workflow (Lightroom-alt)
        rawtherapee   # RAW dev alternativo
        digikam       # gestione foto

        # Audio FOSS
        audacity      # audio editor classico
        # tenacity rimosso (fork instabile, può non essere in 24.11)

        # Video FOSS
        kdenlive      # video editor non-lineare
        shotcut       # video editor cross-platform
        # losslesscut-bin rimosso (nome variabile in 24.11)

        # Screen-record / GIF
        # peek rimosso (deprecato, può non essere in 24.11)
        # kooha rimosso (nome variabile)
        flameshot     # screenshot annotato

        # Conversion / metadata
        handbrake     # video transcoder GUI
        mkvtoolnix    # MKV editor
      ]

      (lib.optionals cfg.pro [
        ardour        # multi-track DAW
        lmms          # DAW music production
        inkscape      # vector (Illustrator-alt)
        scribus       # DTP (InDesign-alt)
        blender       # 3D + video editing
        natron        # compositing (After Effects-alt)
        olive-editor  # video editor moderno
      ])

      (lib.optionals cfg.streaming [
        obs-studio
        obs-studio-plugins.obs-vkcapture
        obs-studio-plugins.wlrobs
      ])
    ];
  };
}
