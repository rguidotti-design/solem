{ config, pkgs, lib, ... }:

# SOLEM FINGERPRINT — login biometrico FOSS (fprintd + PAM).
#
# Single responsibility: SOLO orchestrare fprintd + PAM integration per:
# - login (greetd / gdm / sddm)
# - sudo
# - swaylock / hyprlock screen unlock
# - polkit auth
#
# Compatibile con la maggioranza di lettori USB/embedded (Synaptics,
# Validity, Goodix supportati dal driver libfprint FOSS).
#
# 0 €. Risponde gap "Hardware OOTB → fingerprint" COMPETITIVE-GAP.md.

let
  cfg = config.solem.fingerprint;
in {
  options.solem.fingerprint = {
    enable = lib.mkEnableOption "Login biometrico fingerprint (fprintd + PAM)";

    pamServices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "login" "sudo" "polkit-1" "swaylock" "hyprlock" "greetd" ];
      description = "Servizi PAM dove abilitare auth fingerprint";
    };
  };

  config = lib.mkIf cfg.enable {
    # Servizio fprintd + driver libfprint FOSS
    services.fprintd = {
      enable = true;
      # Tod driver disabilitato di default — alcuni chip Goodix (00xx) richiedono
      # firmware proprietario non redistribuibile. L'utente può abilitarli
      # esplicitamente se accetta licenza vendor:
      #   services.fprintd.tod.enable = true;
      #   services.fprintd.tod.driver = pkgs.libfprint-2-tod1-goodix;
    };

    # Configurazione PAM granulare
    security.pam.services = lib.genAttrs cfg.pamServices (name: {
      fprintAuth = true;
    });

    environment.systemPackages = with pkgs; [
      fprintd
      libfprint
    ];

    # CLI helper "solem-fp enroll/list/clear"
    environment.etc."solem/fingerprint.hint".text = ''
      # SOLEM FINGERPRINT
      # Enroll dito (richiede tocco multiplo):
      #   fprintd-enroll
      # Lista impronte salvate:
      #   fprintd-list "$USER"
      # Cancella impronte:
      #   fprintd-delete "$USER"
      #
      # Servizi PAM abilitati: ${lib.concatStringsSep ", " cfg.pamServices}
    '';
  };
}
