{ config, pkgs, lib, ... }:

# SOLEM STREAMING FIX — abilita Widevine L3 nei browser per Netflix/Disney+/Prime.
#
# Single responsibility: SOLO configurare browser FOSS con supporto Widevine
# L3 (720p su Netflix/Disney+). Per L1 (4K) serve hardware/Windows.
#
# Browser FOSS supportati:
# - Firefox (built-in widevine via about:addons)
# - LibreWolf (richiede manualmente CDM)
# - Chromium (built-in via flag --proprietary-codecs --enable-widevine)
# - Brave (built-in)
#
# Widevine CDM è binary non-FOSS distribuito da Google. SOLEM lo offre come
# opt-in esplicito dell'utente.

let
  cfg = config.solem.streamingFix;
in {
  options.solem.streamingFix = {
    enable = lib.mkEnableOption "Widevine L3 per streaming Netflix/Disney+/Prime (720p)";

    browsers = lib.mkOption {
      type = lib.types.listOf (lib.types.enum [ "firefox" "chromium" "brave" "vivaldi" ]);
      default = [ "firefox" "chromium" ];
      description = "Browser con Widevine abilitato";
    };
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.config.allowUnfree = true;       # richiesto per Widevine CDM

    environment.systemPackages = with pkgs; lib.flatten [
      (lib.optionals (lib.elem "firefox" cfg.browsers) [ firefox ])
      (lib.optionals (lib.elem "chromium" cfg.browsers) [
        (chromium.override {
          enableWideVine = true;
        })
      ])
      (lib.optionals (lib.elem "brave" cfg.browsers) [ brave ])
      (lib.optionals (lib.elem "vivaldi" cfg.browsers) [ vivaldi vivaldi-ffmpeg-codecs ])
    ];

    # Hint per l'utente
    environment.etc."solem/streaming.md".text = ''
      # SOLEM Streaming Fix

      Browser configurati con Widevine L3 (720p):
      ${lib.concatStringsSep ", " cfg.browsers}

      ## Limiti

      - **Netflix**: max 720p (HDR/4K richiede Widevine L1, vendor-only Windows/Mac)
      - **Disney+**: max 720p
      - **Prime Video**: max 720p (HD su browser)
      - **YouTube Premium**: 1080p+ OK (non usa Widevine)
      - **Spotify Web Player**: OK
      - **Twitch**: OK

      ## Test che funziona

      Apri https://bitmovin.com/demos/drm e prova un MPEG-DASH protected.
    '';
  };
}
