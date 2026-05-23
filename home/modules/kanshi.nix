{ config, lib, pkgs, ... }:

# SOLEM kanshi (multi-monitor auto-profile) user-side.
{
  services.kanshi = {
    enable = true;
    systemdTarget = "graphical-session.target";
    settings = [
      {
        profile = {
          name = "docked";
          outputs = [
            { criteria = "eDP-1"; status = "enable"; scale = 1.0; }
            { criteria = "*"; status = "enable"; position = "1920,0"; }
          ];
        };
      }
      {
        profile = {
          name = "undocked";
          outputs = [
            { criteria = "eDP-1"; status = "enable"; scale = 1.0; position = "0,0"; }
          ];
        };
      }
      {
        profile = {
          name = "laptop-closed";
          outputs = [
            { criteria = "eDP-1"; status = "disable"; }
            { criteria = "*"; status = "enable"; position = "0,0"; }
          ];
        };
      }
    ];
  };
}
