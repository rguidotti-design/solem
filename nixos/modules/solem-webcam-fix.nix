{ config, pkgs, lib, ... }:

# SOLEM WEBCAM FIX — virtual cam + GUI scelta webcam.
#
# Single responsibility: SOLO orchestrare:
# - v4l2loopback (virtual webcam Linux)
# - guvcview (GUI controllo webcam)
# - cheese (test rapido webcam)
# - OBS plugin per virtual cam (richiede obs-studio)

let
  cfg = config.solem.webcamFix;
in {
  options.solem.webcamFix = {
    enable = lib.mkEnableOption "Webcam virtuali + GUI selezione + test (v4l2loopback)";

    loopbackDevices = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = "Numero device virtuali da creare (per OBS Virtual Cam, scrcpy, etc.)";
    };
  };

  config = lib.mkIf cfg.enable {
    # v4l2loopback per virtual webcam
    boot.extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback ];
    boot.kernelModules = [ "v4l2loopback" ];
    boot.extraModprobeConfig = ''
      options v4l2loopback devices=${toString cfg.loopbackDevices} \
              card_label="SOLEM Virtual Cam" exclusive_caps=1
    '';

    environment.systemPackages = with pkgs; [
      guvcview         # GTK GUI controllo webcam
      cheese           # test rapido (GNOME)
      v4l-utils        # v4l2-ctl CLI
      ffmpeg-full      # registrazione + filtri
      gphoto2          # DSLR come webcam
    ];

    # Permessi video group
    users.groups.video = {};
  };
}
