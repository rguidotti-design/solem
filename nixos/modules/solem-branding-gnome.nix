{ config, pkgs, lib, ... }:

# SOLEM BRANDING GNOME — wallpaper navy/gold + theme dark + dconf settings.
# Per VM demo: applica branding navy SOLEM al GNOME default.

let
  cfg = config.solem.brandingGnome;

  # Wallpaper navy gradient generato runtime con ImageMagick
  solemWallpaper = pkgs.runCommand "solem-wallpaper-navy" {
    nativeBuildInputs = [ pkgs.imagemagick ];
  } ''
    mkdir -p $out
    # Gradient radiale navy → gold center
    magick -size 1920x1080 \
      gradient:'#0B1426'-'#1A2540' \
      -gravity center \
      -fill '#D4A24A' -stroke '#D4A24A' -strokewidth 0 \
      -font Helvetica -pointsize 240 \
      -annotate +0-80 'SOLEM' \
      -fill '#888888' -stroke none \
      -pointsize 28 \
      -annotate +0+100 'AI-native OS' \
      $out/wallpaper.png
  '';
in {
  options.solem.brandingGnome = {
    enable = lib.mkEnableOption "Apply SOLEM navy/gold branding to GNOME desktop";
  };

  config = lib.mkIf cfg.enable {
    # Wallpaper + dconf default
    environment.systemPackages = with pkgs; [
      dconf
      gnome-tweaks
    ];

    # Setting GNOME defaults via dconf-update
    environment.etc."dconf/db/local.d/00-solem-branding".text = ''
      [org/gnome/desktop/background]
      picture-uri='file://${solemWallpaper}/wallpaper.png'
      picture-uri-dark='file://${solemWallpaper}/wallpaper.png'
      primary-color='#0B1426'
      secondary-color='#D4A24A'

      [org/gnome/desktop/screensaver]
      picture-uri='file://${solemWallpaper}/wallpaper.png'
      primary-color='#0B1426'

      [org/gnome/desktop/interface]
      color-scheme='prefer-dark'
      gtk-theme='Adwaita-dark'
      cursor-theme='Adwaita'
      font-name='Inter 11'
      monospace-font-name='Fira Code 10'
      enable-hot-corners=true
      clock-show-weekday=true
      clock-show-date=true

      [org/gnome/desktop/wm/preferences]
      titlebar-font='Inter Bold 11'
      button-layout='close,minimize,maximize:'

      [org/gnome/shell]
      favorite-apps=['firefox.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.Calculator.desktop', 'org.gnome.Settings.desktop']
    '';

    # Compila dconf db al boot
    environment.etc."dconf/profile/user".text = ''
      user-db:user
      system-db:local
    '';

    # Wallpaper accessibile system-wide
    environment.etc."solem/wallpaper.png".source = "${solemWallpaper}/wallpaper.png";

    systemd.services.solem-dconf-update = {
      wantedBy = [ "multi-user.target" ];
      before = [ "display-manager.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.dconf}/bin/dconf update";
      };
    };
  };
}
