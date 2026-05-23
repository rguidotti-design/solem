{ config, lib, pkgs, ... }:

# SOLEM eww quick-settings popover — auto in ~/.config/eww/
{
  xdg.configFile."eww/eww.yuck".text = ''
    ; SOLEM Quick Settings popover
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
        (scale :value 50 :min 0 :max 100
               :onchange "wpctl set-volume @DEFAULT_AUDIO_SINK@ {}%")))
  '';

  xdg.configFile."eww/eww.scss".text = ''
    * { all: unset; font-family: "Inter"; }
    .title { font-size: 14px; color: #D4A24A; font-weight: bold; }
    button {
      background: #0B1426;
      color: #F5F5F5;
      padding: 8px 12px;
      border-radius: 8px;
      border: 1px solid #D4A24A33;
    }
    button:hover { background: #1A2436; border-color: #D4A24A; }
  '';
}
