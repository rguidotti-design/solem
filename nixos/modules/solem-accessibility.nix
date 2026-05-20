{ config, pkgs, lib, ... }:

# SOLEM ACCESSIBILITY — modulo accessibilità (WCAG AAA goal).
#
# Single responsibility: SOLO installare tool a11y e configurare AT-SPI
# bus. Niente politica UI (è in solem-desktop.nix).
#
# Strumenti FOSS:
#   - Orca           → screen reader (GNOME a11y)
#   - speech-dispatcher → TTS backend per Orca
#   - espeak-ng      → voci offline (IT incluso)
#   - dasher         → input testuale predittivo per disabilità motorie
#   - onboard        → tastiera on-screen
#   - magnifier      → ingrandimento schermo
#
# AT-SPI esposto come bus D-Bus per assistive tech.

let
  cfg = config.solem.accessibility;
in {
  options.solem.accessibility = {
    enable = lib.mkEnableOption "Stack accessibilità completo (screen reader + magnifier + on-screen kbd)";

    highContrast = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Tema alto contrasto navy/giallo (default off per estetica branding navy)";
    };

    voiceItalian = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Carica voci italiane per espeak/speech-dispatcher";
    };
  };

  config = lib.mkIf cfg.enable {
    # AT-SPI bus (assistive tech base)
    services.gnome.at-spi2-core.enable = true;

    # Pacchetti a11y
    environment.systemPackages = with pkgs; [
      orca                  # screen reader
      speechd               # speech-dispatcher
      espeak-ng             # TTS offline
      dasher                # input predittivo
      onboard               # on-screen keyboard
    ];

    # GTK/Qt accessibility
    environment.variables = {
      GTK_MODULES = "gail:atk-bridge";
      QT_ACCESSIBILITY = "1";
      ACCESSIBILITY_ENABLED = "1";
    };

    # Speech-dispatcher config
    environment.etc."speech-dispatcher/speechd.conf".text = ''
      LogLevel 2
      DefaultModule espeak-ng
      DefaultVoiceType FEMALE1
      DefaultLanguage ${if cfg.voiceItalian then "it" else "en"}
      AudioOutputMethod pulse
    '';

    # Override font scaling default per leggibilità
    fonts.fontconfig = {
      enable = true;
      antialias = true;
      hinting.enable = true;
      hinting.style = "slight";
    };
  };
}
