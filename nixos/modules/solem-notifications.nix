{ config, pkgs, lib, ... }:

# SOLEM NOTIFICATIONS — daemon notifiche desktop (mako per Wayland).
#
# Single responsibility: SOLO daemon notifiche D-Bus + comando di test.
# Niente regole content-filter (è in business logic AI).
#
# Mako: navy palette per coerenza branding. 100% FOSS, 0 €.

let
  cfg = config.solem.notifications;

  makoConfig = pkgs.writeText "mako.config" ''
    font=Cormorant Garamond 12
    background-color=#0a1628ee
    text-color=#e8eaed
    border-color=#c9a961
    border-size=2
    border-radius=8
    default-timeout=6000
    max-visible=5
    anchor=top-right
    margin=12

    [urgency=low]
    border-color=#5a6a7a
    default-timeout=4000

    [urgency=high]
    border-color=#d97757
    default-timeout=0
    background-color=#3a1612ee
  '';
in {
  options.solem.notifications = {
    enable = lib.mkEnableOption "Notifiche desktop (mako)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      mako
      libnotify   # notify-send CLI
    ];

    # Mako config system-wide; ogni utente può override in ~/.config/mako/
    environment.etc."xdg/mako/config".source = makoConfig;
  };
}
