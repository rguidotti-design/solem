{ config, pkgs, lib, ... }:

# SOLEM ITALIAN LOCALE — locale, font, spell, formati italiani.
#
# Single responsibility: SOLO localizzazione it_IT:
# - locale it_IT.UTF-8 + keyboard layout
# - timezone Europe/Rome + formato 24h + dd/mm/yyyy
# - hunspell IT + LanguageTool offline
# - font con accenti completi (DejaVu, Liberation, Inter, Cormorant)
# - calendario festività italiane (locale + libreoffice)
# - dizionario sinonimi/contrari IT
#
# Tutto FOSS, 0 €.

let
  cfg = config.solem.italianLocale;
in {
  options.solem.italianLocale = {
    enable = lib.mkEnableOption "Localizzazione completa it_IT (locale, font, spell-check)";

    languageTool = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Abilita LanguageTool offline (Java, GPL). Grammar check + style per
        italiano, integrato in LibreOffice/browser via add-on.
      '';
    };

    extraFonts = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Font extra italiani (Inter, Cormorant Garamond, EB Garamond, JetBrains Mono)";
    };
  };

  config = lib.mkIf cfg.enable {
    # === Locale === (mkDefault per non collidere con configuration.nix)
    i18n = {
      defaultLocale = lib.mkDefault "it_IT.UTF-8";
      supportedLocales = lib.mkDefault [
        "it_IT.UTF-8/UTF-8"
        "en_US.UTF-8/UTF-8"
      ];
      extraLocaleSettings = {
        LC_TIME = lib.mkDefault "it_IT.UTF-8";
        LC_NUMERIC = lib.mkDefault "it_IT.UTF-8";
        LC_MONETARY = lib.mkDefault "it_IT.UTF-8";
        LC_MEASUREMENT = lib.mkDefault "it_IT.UTF-8";
        LC_PAPER = lib.mkDefault "it_IT.UTF-8";
      };
    };

    # Timezone
    time.timeZone = lib.mkDefault "Europe/Rome";

    # Console keyboard layout
    console.keyMap = lib.mkDefault "it";

    # X11 / Wayland keyboard layout
    services.xserver.xkb = lib.mkDefault {
      layout = "it";
      variant = "";
    };

    # === Spell-check / Grammar ===
    environment.systemPackages = with pkgs; lib.flatten [
      [
        # Hunspell dictionaries it_IT + en_US
        hunspell
        hunspellDicts.it_IT
        hunspellDicts.en_US

        # Aspell italiano (alt-lingua)
        aspell
        aspellDicts.it
        aspellDicts.en

        # Sinonimi/contrari
        mythes

        # Tool linguistici
        translate-shell    # Translate CLI multi-engine FOSS
      ]

      (lib.optionals cfg.languageTool [
        languagetool       # grammar checker offline (Java, GPL)
      ])

      (lib.optionals cfg.extraFonts [
        # Font con supporto Latin Extended (accenti italiani perfetti)
        inter
        cormorant
        eb-garamond
        crimson
        merriweather
        source-sans
        source-serif
        jetbrains-mono
        fira-code
        ibm-plex
        roboto
        liberation_ttf
        dejavu_fonts
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-emoji
      ])
    ];

    # Font configuration sistema
    fonts = lib.mkIf cfg.extraFonts {
      packages = with pkgs; [
        inter
        cormorant
        eb-garamond
        jetbrains-mono
        liberation_ttf
        dejavu_fonts
        noto-fonts
        noto-fonts-emoji
      ];
      fontconfig = {
        enable = true;
        defaultFonts = {
          serif = [ "Cormorant Garamond" "EB Garamond" "Liberation Serif" ];
          sansSerif = [ "Inter" "Liberation Sans" ];
          monospace = [ "JetBrains Mono" "DejaVu Sans Mono" ];
          emoji = [ "Noto Color Emoji" ];
        };
      };
    };

    # LanguageTool come servizio locale (porta 8010)
    services.languagetool = lib.mkIf cfg.languageTool {
      enable = true;
      port = 8010;
      allowOrigin = "*";
    };
  };
}
