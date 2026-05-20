{ config, pkgs, lib, ... }:

# SOLEM BROWSER HARDENED — Firefox + LibreWolf + arkenfox user.js.
#
# Single responsibility: SOLO installazione browser + override prefs
# (telemetria off, fingerprinting protection, anti-tracking strict).
#
# Browser FOSS:
#   - LibreWolf  → fork hardened di Firefox (FOSS, no telemetry)
#   - Firefox    → con arkenfox user.js applicato
#   - Brave      → opzionale (ha tracker BAT)
#
# Costo 0 €. Niente Google Chrome di default (closed source).

let
  cfg = config.solem.browserHardened;

  # Arkenfox-inspired prefs (sottoinsieme critical)
  arkenfoxUserJs = pkgs.writeText "user.js" ''
    // SOLEM hardened defaults (arkenfox subset)

    // Disable telemetry
    user_pref("toolkit.telemetry.enabled", false);
    user_pref("toolkit.telemetry.unified", false);
    user_pref("toolkit.telemetry.archive.enabled", false);
    user_pref("datareporting.healthreport.uploadEnabled", false);
    user_pref("datareporting.policy.dataSubmissionEnabled", false);
    user_pref("app.shield.optoutstudies.enabled", false);
    user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);

    // Disable Pocket + Sponsored
    user_pref("extensions.pocket.enabled", false);
    user_pref("browser.newtabpage.activity-stream.showSponsored", false);
    user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);

    // Resist fingerprinting
    user_pref("privacy.resistFingerprinting", true);
    user_pref("privacy.donottrackheader.enabled", true);
    user_pref("privacy.firstparty.isolate", true);

    // Disable WebRTC IP leak
    user_pref("media.peerconnection.enabled", false);
    user_pref("media.peerconnection.ice.default_address_only", true);

    // HTTPS-only mode
    user_pref("dom.security.https_only_mode", true);
    user_pref("dom.security.https_only_mode_ever_enabled", true);

    // Disable predictive prefetch
    user_pref("network.prefetch-next", false);
    user_pref("network.dns.disablePrefetch", true);
    user_pref("network.predictor.enabled", false);

    // Disable search suggestions sent in real-time
    user_pref("browser.urlbar.suggest.searches", false);
    user_pref("browser.search.suggest.enabled", false);

    // Cookies: third-party block strict
    user_pref("network.cookie.cookieBehavior", 5);  // TCP isolation
    user_pref("browser.contentblocking.category", "strict");

    // Disable WebGL (anti-fingerprint)
    user_pref("webgl.disabled", true);

    // Clear on close (configurable)
    user_pref("privacy.sanitize.sanitizeOnShutdown", true);
    user_pref("privacy.clearOnShutdown.cache", true);
    user_pref("privacy.clearOnShutdown.cookies", false);  // tieni session
    user_pref("privacy.clearOnShutdown.history", false);
    user_pref("privacy.clearOnShutdown.offlineApps", true);

    // Geolocation
    user_pref("geo.enabled", false);

    // Captive portal off (privacy)
    user_pref("network.captive-portal-service.enabled", false);
  '';
in {
  options.solem.browserHardened = {
    enable = lib.mkEnableOption "Browser hardened (LibreWolf + Firefox arkenfox)";

    installLibreWolf = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    installFirefox = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs;
      (lib.optional cfg.installLibreWolf librewolf)
      ++ (lib.optional cfg.installFirefox firefox);

    # Firefox policies enterprise (forza preferenze hardened)
    programs.firefox = lib.mkIf cfg.installFirefox {
      enable = true;
      policies = {
        DisableTelemetry = true;
        DisableFirefoxStudies = true;
        DisablePocket = true;
        DisableFormHistory = true;
        EnableTrackingProtection = {
          Value = true;
          Locked = true;
          Cryptomining = true;
          Fingerprinting = true;
        };
        DontCheckDefaultBrowser = true;
        OfferToSaveLogins = false;
        SearchSuggestEnabled = false;
        FirefoxHome = {
          Pocket = false;
          SponsoredPocket = false;
          SponsoredTopSites = false;
        };
      };
    };

    # User.js arkenfox-style applicato a tutti i profili Firefox
    environment.etc."firefox/policies/policies.json".text = builtins.toJSON {
      policies = {
        DisableTelemetry = true;
        Preferences = {
          "privacy.resistFingerprinting" = { Value = true; Status = "locked"; };
          "dom.security.https_only_mode"  = { Value = true; Status = "locked"; };
        };
      };
    };

    environment.etc."solem/firefox-hardened-user.js".source = arkenfoxUserJs;
  };
}
