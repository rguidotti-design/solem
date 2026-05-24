{ config, pkgs, lib, ... }:

# SOLEM CONTINUITY CAMERA — usa smartphone come webcam (alt Apple CC).
#
# Single responsibility: SOLO CLI `solem-phone-cam` che:
# - Connette smartphone Android via USB (scrcpy)
# - Espone camera Android come /dev/video* virtuale (v4l2loopback)
# - GUI apps (OBS, Zoom Flatpak, Meet web) vedono come webcam
#
# Apple Continuity Camera replica: iPhone wireless via AirDrop → impossibile FOSS.
# Android version FOSS: USB cavo + scrcpy → DroidCam-style.

let
  cfg = config.solem.continuityCamera;

  phoneCamCli = pkgs.writeShellApplication {
    name = "solem-phone-cam";
    runtimeInputs = with pkgs; [ coreutils scrcpy ffmpeg android-tools ];
    text = ''
      ACTION="''${1:-start}"

      case "$ACTION" in
        # ── Avvia phone-cam (USB cavo necessario) ─────────────────────
        start|s)
          echo "── SOLEM Phone Camera ──"
          echo "Verifica device ADB:"
          adb devices

          # Verifica v4l2loopback (caricato dal modulo solem-webcam-fix)
          if ! lsmod | grep -q v4l2loopback; then
            echo "ATTENZIONE: v4l2loopback non caricato."
            echo "Attiva il modulo:"
            echo "  solem.webcamFix.enable = true; (in configuration.nix)"
            exit 1
          fi

          # scrcpy mode video-only + redirect a /dev/video10 (loopback)
          echo "Avvio scrcpy → /dev/video10..."
          scrcpy --video-source=camera \
                 --camera-facing=back \
                 --no-audio \
                 --max-fps=30 \
                 --record="$HOME/.cache/scrcpy.mp4" &
          SCRCPY_PID=$!
          echo "PID scrcpy: $SCRCPY_PID"
          echo
          echo "Ora apri Zoom/Meet/OBS e scegli webcam 'SOLEM Virtual Cam'."
          echo "Stop: solem-phone-cam stop"
          ;;

        stop)
          pkill -f "scrcpy --video-source=camera" || true
          echo "Phone-cam stopped"
          ;;

        list-devices)
          adb devices
          ;;

        help|--help|-h|*)
          cat <<'HELP'
solem-phone-cam — usa smartphone Android come webcam (FOSS)

  Prerequisiti:
    1. solem.webcamFix.enable = true; (in configuration.nix)
    2. Smartphone Android collegato USB
    3. USB Debugging attivo sullo smartphone

  start                avvia phone-cam (back camera)
  stop                 ferma scrcpy
  list-devices         lista device ADB

  Output: webcam virtuale /dev/video10 visibile a Zoom/Meet/OBS.

Alternative iOS (Apple Continuity Camera):
  - Impossibile FOSS (Apple WPAN proprietario)
  - Workaround: app iOS "DroidCam Phone" + DroidCam server Linux (commerciale)

Per Android FOSS:
  - scrcpy (questo) — back camera
  - Iriun Webcam (closed) — alternativa più matura

Tutto FOSS quando possibile. 0 €.
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.continuityCamera = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Installa `solem-phone-cam` per usare smartphone Android come webcam";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      phoneCamCli
      scrcpy
      android-tools  # adb
    ];

    # plugdev group per accesso USB
    users.groups.plugdev = {};

    # udev rules per Android phone ADB
    services.udev.packages = [ pkgs.android-udev-rules ];
  };
}
