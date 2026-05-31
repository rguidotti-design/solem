{ config, pkgs, lib, ... }:

# SOLEM SETTINGS GUI — Step 44: pannello settings centralizzato.
#
# Single responsibility: SOLO orchestrazione gnome-control-center
# (Settings app GNOME) come pannello unificato per Wi-Fi, display,
# audio, account, ecc. — UX tipo Win/macOS Settings.

let
  cfg = config.solem.settingsGui;
in {
  options.solem.settingsGui = {
    enable = lib.mkEnableOption "gnome-control-center come Settings GUI";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      gnome-control-center
      gnome-system-monitor
      gnome-disk-utility
      networkmanagerapplet
      pavucontrol
      blueman
      (pkgs.writeShellApplication {
        name = "solem-settings";
        runtimeInputs = with pkgs; [ coreutils ];
        text = ''
          ACTION="''${1:-open}"
          case "$ACTION" in
            open|*)  gnome-control-center & ;;
            wifi)    nm-connection-editor & ;;
            audio)   pavucontrol & ;;
            bt)      blueman-manager & ;;
            disk)    gnome-disks & ;;
            sys)     gnome-system-monitor & ;;
          esac
        '';
      })
    ];
    services.dbus.enable = true;
    services.gnome.gnome-keyring.enable = true;
    programs.dconf.enable = true;
  };
}
