{ config, pkgs, lib, ... }:

# SOLEM KEYCHAIN — keychain SSO clone (GNOME Keyring + KWallet + pass).
#
# Single responsibility: SOLO orchestrare keystore secret-service FOSS:
# - gnome-keyring        → daemon Secret Service standard freedesktop
# - libsecret + seahorse → GUI gestione secret
# - kwallet (opt-in)     → alternativa KDE
# - pass + gopass        → password store git-friendly per power-user
# - browser integration  → unlock automatico al login (PAM)
#
# Sblocco con biometrico (se solem-fingerprint attivo) o password login.
# 0 €. Risponde gap "Keychain SSO macOS" COMPETITIVE-GAP.md.

let
  cfg = config.solem.keychain;
in {
  options.solem.keychain = {
    enable = lib.mkEnableOption "Keychain SSO FOSS (GNOME Keyring + Secret Service + pass)";

    pamUnlock = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Unlock automatico keychain al login (PAM integration)";
    };

    pass = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa anche pass + gopass (CLI git-backed password store)";
    };

    kwallet = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Aggiungi KWallet (utile se anche KDE/Plasma è installato)";
    };
  };

  config = lib.mkIf cfg.enable {
    # GNOME Keyring come Secret Service provider
    services.gnome.gnome-keyring.enable = true;

    # PAM: unlock automatico al login (greetd/gdm/sddm)
    security.pam.services = lib.mkIf cfg.pamUnlock {
      login.enableGnomeKeyring = true;
      greetd.enableGnomeKeyring = true;
      sddm.enableGnomeKeyring = true;
    };

    environment.systemPackages = with pkgs; lib.flatten [
      [
        seahorse           # GUI GNOME Keyring
        libsecret          # API secret service
        gcr                # crypto UI helper (pinentry)
        pinentry-gtk2      # prompt PIN per GPG/keyring

        # Browser integration
        libsecret          # firefox usa secret-service via gnome-keyring
      ]

      (lib.optionals cfg.pass [
        pass
        gopass
        passff-host        # firefox extension host
        pass-secret-service   # bridge pass ↔ secret service
      ])

      (lib.optionals cfg.kwallet [
        kdePackages.kwallet
        kdePackages.kwallet-pam
        kdePackages.ksshaskpass
      ])
    ];

    # Variabili ambiente per app
    environment.sessionVariables = {
      # SSH usa gnome-keyring agent
      SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/keyring/ssh";
      # GPG pinentry-gtk2 di default
      PINENTRY_USER_DATA = "USE_CURSES=0";
    };
  };
}
