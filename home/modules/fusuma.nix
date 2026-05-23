{ config, lib, pkgs, ... }:

# SOLEM fusuma (touchpad gesture) user-side config.
{
  xdg.configFile."fusuma/config.yml".text = ''
    threshold:
      swipe: 0.4
      pinch: 0.2
    interval:
      swipe: 0.3
      pinch: 0.5

    swipe:
      3:
        left:   { command: 'hyprctl dispatch workspace +1' }
        right:  { command: 'hyprctl dispatch workspace -1' }
        up:     { command: 'hyprctl dispatch fullscreen' }
        down:   { command: 'hyprctl dispatch killactive' }
      4:
        left:   { command: 'hyprctl dispatch movetoworkspace +1' }
        right:  { command: 'hyprctl dispatch movetoworkspace -1' }
        up:     { command: 'anyrun' }
        down:   { command: 'hyprctl dispatch fullscreen 1' }

    pinch:
      in:     { command: 'wtype -k 0xffeb -k plus' }
      out:    { command: 'wtype -k 0xffeb -k minus' }
  '';

  # Systemd user service per autostart fusuma
  systemd.user.services.fusuma = {
    Unit = {
      Description = "SOLEM Fusuma touchpad gestures";
      PartOf = [ "graphical-session.target" ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
    Service = {
      ExecStart = "${pkgs.fusuma}/bin/fusuma -c %h/.config/fusuma/config.yml";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
}
