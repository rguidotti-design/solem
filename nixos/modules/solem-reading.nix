{ config, pkgs, lib, ... }:

# SOLEM READING — eBook + night light + reading mode.
#
# Single responsibility: SOLO tool lettura: Calibre/Foliate + gammastep
# night blue filter + reader mode.

let
  cfg = config.solem.reading;
in {
  options.solem.reading = {
    enable = lib.mkEnableOption "Reading tools (Calibre + Foliate + gammastep night light)";

    nightLight = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Gammastep blue light filter (alternative Redshift Wayland-native)";
    };

    nightLightLocation = lib.mkOption {
      type = lib.types.str;
      default = "41.9:12.5";   # Roma
      description = "Latitudine:longitudine (per calcolo tramonto/alba)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      calibre              # libreria + reader + converter
      foliate              # reader GTK4 moderno
      koreader             # se hai un Kobo / Kindle, anche desktop
      sigil-nx             # editor EPUB
    ] ++ lib.optional cfg.nightLight gammastep;

    # Gammastep user service
    systemd.user.services.gammastep = lib.mkIf cfg.nightLight {
      description = "SOLEM — night blue light filter";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.gammastep}/bin/gammastep -l ${cfg.nightLightLocation} -t 6500:3500";
        Restart = "on-failure";
      };
    };
  };
}
