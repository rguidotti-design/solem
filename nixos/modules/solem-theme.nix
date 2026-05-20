{ config, pkgs, lib, ... }:

# SOLEM THEME — branding pack navy + Cormorant Garamond.
#
# Single responsibility: SOLO assets visivi globali (font system, palette
# wallpaper, console colors). Nessuna logica desktop (è in solem-desktop).
#
# Brand: navy #0a1628, gold accent #c9a961, font serif Cormorant Garamond.
# Tagline: "AI-native OS" (NO Theory Holding nei file/UI).

let
  cfg = config.solem.theme;

  navyWallpaper = pkgs.runCommand "solem-wallpaper.png" {
    nativeBuildInputs = [ pkgs.imagemagick ];
  } ''
    magick -size 1920x1080 \
      gradient:'#0a1628'-'#1a2840' \
      -gravity center \
      -fill '#c9a961' -font ${pkgs.cormorant-garamond}/share/fonts/opentype/CormorantGaramond-Light.otf -pointsize 96 \
      -annotate +0-100 'SOLEM' \
      -fill '#7a8a9a' -font ${pkgs.cormorant-garamond}/share/fonts/opentype/CormorantGaramond-Light.otf -pointsize 32 \
      -annotate +0+20 'AI-native OS' \
      $out
  '';
in {
  options.solem.theme = {
    enable = lib.mkEnableOption "Brand pack SOLEM (navy + Cormorant + wallpaper)";

    wallpaper = lib.mkOption {
      type = lib.types.path;
      default = navyWallpaper;
      description = "Wallpaper di default (PNG)";
    };

    fontName = lib.mkOption {
      type = lib.types.str;
      default = "Cormorant Garamond";
      description = "Serif font system";
    };
  };

  config = lib.mkIf cfg.enable {
    fonts.packages = with pkgs; [
      cormorant-garamond
      ibm-plex             # sans companion
      jetbrains-mono       # mono per console
      noto-fonts
      noto-fonts-emoji
    ];

    fonts.fontconfig = {
      defaultFonts = {
        serif      = [ cfg.fontName "Noto Serif" ];
        sansSerif  = [ "IBM Plex Sans" "Noto Sans" ];
        monospace  = [ "JetBrains Mono" "Noto Sans Mono" ];
        emoji      = [ "Noto Color Emoji" ];
      };
    };

    # Wallpaper system-wide
    environment.etc."solem/wallpaper.png".source = cfg.wallpaper;

    # Console colors navy
    console = {
      colors = [
        "0a1628"  # background (navy)
        "d97757"  # red
        "8aa67b"  # green
        "c9a961"  # yellow (gold)
        "6b8aa3"  # blue
        "9a7a8a"  # magenta
        "7a9a96"  # cyan
        "d4d4d8"  # white
        "1a2840"  # bright black
        "e09975"  # bright red
        "a8bf97"  # bright green
        "dcc481"  # bright yellow
        "85a8c0"  # bright blue
        "b89bab"  # bright magenta
        "9bbab5"  # bright cyan
        "f0f0f3"  # bright white
      ];
    };

    # GTK theme default
    environment.sessionVariables = {
      GTK_THEME = "Adwaita-dark";
      QT_STYLE_OVERRIDE = "adwaita-dark";
    };
  };
}
