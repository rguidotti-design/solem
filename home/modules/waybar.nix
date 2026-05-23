{ config, lib, pkgs, ... }:

# SOLEM waybar — top bar Wayland con badge SOLEM live.
{
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    settings = [{
      layer = "top";
      position = "top";
      height = 28;
      modules-left = [ "hyprland/workspaces" "hyprland/window" ];
      modules-center = [ "clock" ];
      modules-right = [
        "pulseaudio" "network" "bluetooth" "battery" "tray" "custom/solem"
      ];

      "hyprland/workspaces" = {
        format = "{icon}";
        format-icons = {
          "1" = "I"; "2" = "II"; "3" = "III"; "4" = "IV"; "5" = "V";
        };
      };
      clock = {
        format = "{:%H:%M  %a %d %b}";
        tooltip-format = "<big>{:%Y %B}</big>\n<tt>{calendar}</tt>";
      };
      pulseaudio = { format = "{icon}  {volume}%"; format-icons = [ "" "" "" ]; };
      battery = { format = "{icon}  {capacity}%"; format-icons = [ "" "" "" "" "" ]; };
      network = { format-wifi = "  {essid}"; format-ethernet = ""; format-disconnected = "睊"; };
      bluetooth = { format = "  {status}"; format-disabled = ""; };
      "custom/solem" = {
        exec = "echo SOLEM";
        format = "{}";
        tooltip = false;
        on-click = "eww open --toggle quick-settings";
      };
    }];

    style = ''
      * { font-family: "Inter"; font-size: 12px; }
      window#waybar { background: rgba(11,20,38,0.92); color: #F5F5F5; border-bottom: 1px solid #D4A24A; }
      #workspaces button.active { background: #D4A24A; color: #0B1426; padding: 0 8px; border-radius: 4px; }
      #clock { color: #D4A24A; font-weight: bold; }
      #custom-solem { color: #D4A24A; padding: 0 10px; font-weight: bold; }
    '';
  };
}
