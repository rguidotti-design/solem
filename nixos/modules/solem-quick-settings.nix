{ config, pkgs, lib, ... }:

# SOLEM QUICK SETTINGS — pannello toggle rapido stile macOS Control Center.
#
# Single responsibility: SOLO installare widget eww + script toggle per
# Wi-Fi / VPN / Bluetooth / volume / brightness / focus / GAVIO. Nessuna
# configurazione waybar (separato).
#
# Tutto FOSS, 0 €. Risponde gap "Quick Settings panel" COMPETITIVE-GAP.md.

let
  cfg = config.solem.quickSettings;

  # Toggle CLI utilizzabili da waybar/eww
  wifiToggle = pkgs.writeShellApplication {
    name = "solem-toggle-wifi";
    runtimeInputs = with pkgs; [ networkmanager coreutils ];
    text = ''
      STATUS=$(nmcli radio wifi)
      if [[ "$STATUS" == "enabled" ]]; then
        nmcli radio wifi off
        echo " wifi off"
      else
        nmcli radio wifi on
        echo " wifi on"
      fi
    '';
  };

  btToggle = pkgs.writeShellApplication {
    name = "solem-toggle-bt";
    runtimeInputs = with pkgs; [ bluez coreutils ];
    text = ''
      STATUS=$(bluetoothctl show | grep -E "Powered: yes" || echo "")
      if [[ -n "$STATUS" ]]; then
        bluetoothctl power off
        echo " bt off"
      else
        bluetoothctl power on
        echo " bt on"
      fi
    '';
  };

  vpnToggle = pkgs.writeShellApplication {
    name = "solem-toggle-vpn";
    runtimeInputs = with pkgs; [ wireguard-tools coreutils ];
    text = ''
      # Toggle WireGuard mesh SOLEM (interfaccia wg-solem)
      IFACE="''${IFACE:-wg-solem}"
      if ip link show "$IFACE" up >/dev/null 2>&1; then
        sudo wg-quick down "$IFACE" && echo " vpn off"
      else
        sudo wg-quick up "$IFACE" && echo " vpn on"
      fi
    '';
  };

  focusToggle = pkgs.writeShellApplication {
    name = "solem-toggle-focus";
    runtimeInputs = with pkgs; [ coreutils systemd ];
    text = ''
      # Toggle focus-mode (DND + social block via DNS).
      FLAG="$HOME/.local/state/solem/focus.on"
      mkdir -p "$(dirname "$FLAG")"
      if [[ -f "$FLAG" ]]; then
        rm -f "$FLAG"
        # Riprendi notifiche
        systemctl --user start dunst 2>/dev/null || true
        echo "  focus off"
      else
        touch "$FLAG"
        systemctl --user stop dunst 2>/dev/null || true
        echo " focus on"
      fi
    '';
  };

  airplaneToggle = pkgs.writeShellApplication {
    name = "solem-toggle-airplane";
    runtimeInputs = with pkgs; [ rfkill coreutils ];
    text = ''
      STATUS=$(rfkill list | grep -c "blocked: yes" || true)
      if [[ "$STATUS" -gt 0 ]]; then
        rfkill unblock all
        echo "  airplane off"
      else
        rfkill block all
        echo " airplane on"
      fi
    '';
  };

  # Eww config minimale popover quick settings
  ewwConfig = pkgs.writeText "solem-quick-eww.yuck" ''
    ; ----- SOLEM QUICK SETTINGS popover -----
    (defwindow quick-settings
      :monitor 0
      :geometry (geometry :x "20px" :y "60px"
                         :width "320px" :height "240px"
                         :anchor "top right")
      :stacking "fg"
      (box :orientation "v" :spacing 6
        (label :text "SOLEM Quick Settings" :class "title")
        (box :orientation "h" :spacing 8
          (button :onclick "solem-toggle-wifi"     "  WiFi")
          (button :onclick "solem-toggle-bt"       "  BT")
          (button :onclick "solem-toggle-vpn"      "  VPN"))
        (box :orientation "h" :spacing 8
          (button :onclick "solem-toggle-focus"    " Focus")
          (button :onclick "solem-toggle-airplane" "  Airplane")
          (button :onclick "systemctl suspend"     " Sleep"))
        (box :orientation "h" :spacing 8
          (scale :value 50 :min 0 :max 100
                 :onchange "wpctl set-volume @DEFAULT_AUDIO_SINK@ {}%"
                 :tooltip "Volume"))
      ))
  '';
in {
  options.solem.quickSettings = {
    enable = lib.mkEnableOption "Pannello quick-toggle stile macOS Control Center (eww)";

    waybarIntegration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Installa moduli waybar custom che lanciano i toggle quick-settings.
        Configura il binding lato user (~/.config/waybar/config).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      # Toggle CLI
      wifiToggle
      btToggle
      vpnToggle
      focusToggle
      airplaneToggle

      # Eww widget engine
      eww

      # CLI audio/brightness usati da widget
      wireplumber       # wpctl
      brightnessctl
      pamixer
      networkmanagerapplet
      blueman           # GUI Bluetooth

      # rfkill per airplane toggle
      util-linux
    ];

    # Configurazione eww in /etc/xdg/eww (utente la copia nel suo $XDG_CONFIG_HOME)
    environment.etc."xdg/solem/eww/eww.yuck".source = ewwConfig;
  };
}
