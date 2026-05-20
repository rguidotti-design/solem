{ config, pkgs, lib, ... }:

# SOLEM I18N — locale + tastiera + input method.
#
# Single responsibility: SOLO config locale system-wide (LANG, LC_*, kbd).
# Default Italian, switchabile via solem.i18n.locale.
#
# 100% FOSS. IBus per input method (CJK, accented chars).

let
  cfg = config.solem.i18n;
in {
  options.solem.i18n = {
    locale = lib.mkOption {
      type = lib.types.str;
      default = "it_IT.UTF-8";
      description = "Locale principale (LANG)";
    };

    extraLocales = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "en_US.UTF-8" ];
      description = "Locale aggiuntive disponibili";
    };

    keyboardLayout = lib.mkOption {
      type = lib.types.str;
      default = "it";
      description = "Layout tastiera (xkb)";
    };

    keyboardVariant = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Variante xkb (es. nodeadkeys, mac)";
    };

    timeZone = lib.mkOption {
      type = lib.types.str;
      default = "Europe/Rome";
    };

    inputMethod = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "ibus" "fcitx5" ]);
      default = null;
      description = "Input method per CJK/accented (null = niente)";
    };
  };

  config = {
    i18n = {
      defaultLocale = cfg.locale;
      supportedLocales = map (l: "${l}/UTF-8") (lib.unique ([ cfg.locale ] ++ cfg.extraLocales));
      extraLocaleSettings = {
        LC_ADDRESS        = cfg.locale;
        LC_IDENTIFICATION = cfg.locale;
        LC_MEASUREMENT    = cfg.locale;
        LC_MONETARY       = cfg.locale;
        LC_NAME           = cfg.locale;
        LC_NUMERIC        = cfg.locale;
        LC_PAPER          = cfg.locale;
        LC_TELEPHONE      = cfg.locale;
        LC_TIME           = cfg.locale;
      };
    };

    time.timeZone = cfg.timeZone;

    # Console + X11 keyboard
    console.keyMap = cfg.keyboardLayout;

    services.xserver.xkb = {
      layout = cfg.keyboardLayout;
      variant = cfg.keyboardVariant;
    };

    # Input method (CJK ecc.)
    i18n.inputMethod = lib.mkIf (cfg.inputMethod != null) {
      enable = true;
      type = cfg.inputMethod;
    };
  };
}
