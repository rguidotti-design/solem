{ config, pkgs, lib, ... }:

# SOLEM TOUCHPAD PRO — multi-touch gesture livello macOS (X11 + Wayland).
#
# Single responsibility: SOLO orchestrare libinput + fusuma + wluma + tuning:
# - libinput tap-to-click, natural scroll, palm detection
# - fusuma (Ruby) per gesture custom 3/4-finger
# - touchegg (X11 only, opt-in)
# - hyprland gestures native (3-finger swipe = workspace, 4-finger = overview)
#
# Tutto FOSS, 0 €. Risponde gap "Touchpad gesture macOS" COMPETITIVE-GAP.md.

let
  cfg = config.solem.touchpadPro;

  fusumaConfig = pkgs.writeText "solem-fusuma.yml" ''
    # SOLEM TOUCHPAD GESTURES (fusuma)
    # 3-finger swipe = cambia workspace Hyprland
    # 4-finger swipe = overview
    # pinch = zoom (browser/file manager)

    threshold:
      swipe: 0.4
      pinch: 0.2

    interval:
      swipe: 0.3
      pinch: 0.5

    swipe:
      3:
        left:
          command: 'hyprctl dispatch workspace +1'
        right:
          command: 'hyprctl dispatch workspace -1'
        up:
          command: 'hyprctl dispatch fullscreen'
        down:
          command: 'hyprctl dispatch killactive'
      4:
        left:
          command: 'hyprctl dispatch movetoworkspace +1'
        right:
          command: 'hyprctl dispatch movetoworkspace -1'
        up:
          command: 'rofi -show drun'
        down:
          command: 'hyprctl dispatch fullscreen 1'

    pinch:
      in:
        command: 'wtype -k 0xffeb -k plus'    # Super + plus
      out:
        command: 'wtype -k 0xffeb -k minus'   # Super + minus
  '';
in {
  options.solem.touchpadPro = {
    enable = lib.mkEnableOption "Touchpad multi-touch gesture (libinput + fusuma + tuning)";

    naturalScroll = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Natural scroll (macOS-style, contenuto segue il dito)";
    };

    tapToClick = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Tap-to-click (tocco breve = click)";
    };

    accelProfile = lib.mkOption {
      type = lib.types.enum [ "adaptive" "flat" ];
      default = "adaptive";
      description = "Profilo accelerazione: adaptive (macOS-like) o flat (1:1)";
    };
  };

  config = lib.mkIf cfg.enable {
    # libinput tuning Wayland
    services.libinput = {
      enable = true;
      touchpad = {
        tapping = cfg.tapToClick;
        naturalScrolling = cfg.naturalScroll;
        accelProfile = cfg.accelProfile;
        clickMethod = "clickfinger";       # macOS-like: 2-finger = right-click
        disableWhileTyping = true;
        middleEmulation = false;
      };
    };

    environment.systemPackages = with pkgs; [
      libinput
      libinput-gestures   # X11 / fallback
      fusuma              # Wayland (Ruby)
      wtype               # simulate keystrokes (Wayland)
      ydotool             # alt simulator input
    ];

    # Config fusuma in /etc/xdg
    environment.etc."xdg/solem/fusuma/config.yml".source = fusumaConfig;

    # Gruppo "input" per usare ydotool/fusuma senza root
    users.groups.input = {};
  };
}
