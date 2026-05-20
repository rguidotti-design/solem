{ config, pkgs, lib, ... }:

# SOLEM WAYBAR — status bar branded navy + gold.
#
# Single responsibility: SOLO config waybar (JSON + CSS). Niente install
# (è in solem-desktop). Mostra: workspace, finestre, CPU/RAM/batteria,
# rete, audio, ora, modulo custom SOLEM AI state.

let
  cfg = config.solem.waybar;

  waybarConfig = pkgs.writeText "waybar-config" (builtins.toJSON {
    layer = "top";
    position = "top";
    height = 32;
    spacing = 6;

    modules-left = [ "hyprland/workspaces" "hyprland/window" ];
    modules-center = [ "clock" ];
    modules-right = [
      "custom/solem"
      "cpu"
      "memory"
      "temperature"
      "network"
      "pulseaudio"
      "battery"
      "tray"
    ];

    "hyprland/workspaces" = {
      format = "{icon}";
      format-icons = {
        "1" = "I"; "2" = "II"; "3" = "III"; "4" = "IV"; "5" = "V";
        "6" = "VI"; "7" = "VII"; "8" = "VIII"; "9" = "IX"; "10" = "X";
        urgent = "!";
        active = "•";
        default = "·";
      };
    };

    "hyprland/window" = {
      max-length = 50;
      separate-outputs = true;
    };

    clock = {
      format = "{:%H:%M  %a %d %b}";
      tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
    };

    "custom/solem" = {
      # Live activity: chiama /solem/live/badge → label+colore dinamici
      # (focus countdown, backup ⛁, update ↻, GPU ◢, SOLEM idle)
      exec = "curl -fsS http://127.0.0.1:8001/solem/live/badge 2>/dev/null | jq -r '.label' || echo 'SOLEM'";
      interval = 2;
      tooltip-format = "click → http://localhost:8001/";
      on-click = "xdg-open http://127.0.0.1:8001/";
      on-click-right = "xdg-open http://127.0.0.1:9000/preview";
    };

    cpu = {
      format = "CPU {usage}%";
      interval = 5;
    };

    memory = {
      format = "RAM {percentage}%";
      interval = 5;
    };

    temperature = {
      critical-threshold = 80;
      format = "{temperatureC}°";
      tooltip = false;
    };

    network = {
      format-wifi = "WiFi {essid}";
      format-ethernet = "LAN {ifname}";
      format-disconnected = "—";
      tooltip-format = "{ifname}: {ipaddr}/{cidr}";
    };

    pulseaudio = {
      format = "vol {volume}%";
      format-muted = "muted";
      format-bluetooth = "BT {volume}%";
      on-click = "pavucontrol";
    };

    battery = {
      states = { warning = 30; critical = 15; };
      format = "{capacity}%";
      tooltip-format = "{time}";
    };

    tray = {
      icon-size = 18;
      spacing = 8;
    };
  });

  waybarCss = pkgs.writeText "waybar.css" ''
    * {
      font-family: "Cormorant Garamond", "IBM Plex Sans", sans-serif;
      font-size: 13px;
      min-height: 0;
    }

    window#waybar {
      background: rgba(10, 22, 40, 0.95);
      color: #e8eaed;
      border-bottom: 2px solid #c9a961;
    }

    tooltip {
      background: rgba(10, 22, 40, 0.98);
      border: 1px solid #c9a961;
      border-radius: 6px;
    }

    #workspaces button {
      padding: 0 8px;
      color: #7a8a9a;
      background: transparent;
      border-bottom: 2px solid transparent;
      transition: all 200ms ease;
    }

    #workspaces button.active {
      color: #c9a961;
      border-bottom-color: #c9a961;
    }

    #workspaces button.urgent {
      color: #d97757;
      border-bottom-color: #d97757;
    }

    #clock, #cpu, #memory, #temperature, #network, #pulseaudio,
    #battery, #custom-solem, #window {
      padding: 0 10px;
      color: #e8eaed;
    }

    #clock {
      color: #c9a961;
      font-weight: 600;
    }

    #custom-solem {
      color: #c9a961;
      font-weight: 600;
      border-left: 2px solid #c9a961;
      border-right: 2px solid #c9a961;
      padding: 0 14px;
    }

    #battery.critical {
      color: #d97757;
    }

    #temperature.critical {
      color: #d97757;
    }
  '';
in {
  options.solem.waybar = {
    enable = lib.mkEnableOption "Waybar status bar SOLEM branded";
  };

  config = lib.mkIf cfg.enable {
    environment.etc."xdg/waybar/config".source = waybarConfig;
    environment.etc."xdg/waybar/style.css".source = waybarCss;

    environment.systemPackages = with pkgs; [
      waybar
      pavucontrol
    ];
  };
}
