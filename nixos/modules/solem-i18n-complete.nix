{ config, pkgs, lib, ... }:

# SOLEM I18N COMPLETE — Step 49: localization completa italiano-first.

let
  cfg = config.solem.i18nComplete;
in {
  options.solem.i18nComplete = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Localization italiano-first + supporto multilingue";
    };

    primaryLanguage = lib.mkOption {
      type = lib.types.str;
      default = "it_IT.UTF-8";
      description = "Locale primaria (it_IT, en_US, fr_FR, de_DE, ...)";
    };

    keymap = lib.mkOption {
      type = lib.types.str;
      default = "it";
      description = "Console keymap (it, us, de, fr, ...)";
    };

    timeZone = lib.mkOption {
      type = lib.types.str;
      default = "Europe/Rome";
      description = "Timezone (Europe/Rome, America/New_York, ...)";
    };
  };

  config = lib.mkIf cfg.enable {
    i18n.defaultLocale = cfg.primaryLanguage;
    i18n.supportedLocales = [
      "it_IT.UTF-8/UTF-8"
      "en_US.UTF-8/UTF-8"
      "fr_FR.UTF-8/UTF-8"
      "de_DE.UTF-8/UTF-8"
      "es_ES.UTF-8/UTF-8"
      "C.UTF-8/UTF-8"
    ];
    i18n.extraLocaleSettings = {
      LC_TIME = cfg.primaryLanguage;
      LC_MONETARY = cfg.primaryLanguage;
      LC_PAPER = cfg.primaryLanguage;
      LC_MEASUREMENT = cfg.primaryLanguage;
      LC_NUMERIC = cfg.primaryLanguage;
    };

    console.keyMap = cfg.keymap;
    services.xserver.xkb.layout = cfg.keymap;

    time.timeZone = cfg.timeZone;

    # Fonts con copertura multilingue ampia
    fonts.packages = with pkgs; [
      noto-fonts noto-fonts-cjk-sans noto-fonts-emoji
      liberation_ttf dejavu_fonts
      fira-code fira-code-symbols
      inter cormorant-garamond
    ];

    # Spell checker dictionaries
    environment.systemPackages = with pkgs; [
      hunspell hunspellDicts.it_IT hunspellDicts.en_US hunspellDicts.fr-any hunspellDicts.de_DE
    ];

    environment.etc."solem/i18n.md".text = ''
      # SOLEM I18N (Step 49)

      Localization completa default italiano.

      ## Locale supportate
      it_IT (default), en_US, fr_FR, de_DE, es_ES, C.UTF-8

      ## Keymap: ${cfg.keymap}
      ## Timezone: ${cfg.timeZone}

      ## Fonts
      Noto (CJK + emoji), Liberation, DejaVu, Fira Code, Cormorant Garamond
      → copertura completa Unicode + branding.

      ## Spell checker
      hunspell con dizionari it/en/fr/de.

      ## CLI SOLEM
      Messaggi system-wide: italiano-first.
      Help text: italiano + occasionali fallback inglese (technical terms).

      ## Cambiare lingua
      ```nix
      solem.i18nComplete = {
        primaryLanguage = "en_US.UTF-8";
        keymap = "us";
        timeZone = "America/New_York";
      };
      ```
      Poi: nixos-rebuild switch → reboot.

      ## Limiti onesti
      - Traduzioni CLI SOLEM: mix italiano (gestione utente) + inglese
        (technical/error msg). Full traduzione = future PR.
      - App esterne (Firefox, LibreOffice): rispettano locale via env.
      - Hyprland config: in inglese (config-as-code, no traduzione).
    '';
  };
}
