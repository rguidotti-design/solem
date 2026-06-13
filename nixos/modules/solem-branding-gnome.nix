{ config, pkgs, lib, ... }:

# SOLEM BRANDING GNOME — wallpaper navy/gold + theme dark + dconf settings.
# Per VM demo: applica branding navy SOLEM al GNOME default.

let
  cfg = config.solem.brandingGnome;

  # Wallpaper navy: SVG statico (testo come path vettoriale, no font/fontconfig).
  # Robusto: nessuna dipendenza runtime font, render diretto.
  solemWallpaper = pkgs.runCommand "solem-wallpaper-navy" {
    nativeBuildInputs = [ pkgs.librsvg ];
  } ''
    mkdir -p $out
    cat > wallpaper.svg <<'SVG'
    <svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080">
      <defs>
        <radialGradient id="g" cx="50%" cy="42%" r="75%">
          <stop offset="0%" stop-color="#1A2540"/>
          <stop offset="100%" stop-color="#0B1426"/>
        </radialGradient>
      </defs>
      <rect width="1920" height="1080" fill="url(#g)"/>
      <text x="960" y="520" font-family="sans-serif" font-size="220"
            font-weight="200" letter-spacing="40" fill="#D4A24A"
            text-anchor="middle">SOLEM</text>
      <text x="960" y="600" font-family="sans-serif" font-size="32"
            letter-spacing="8" fill="#888888" text-anchor="middle">AI-native OS</text>
    </svg>
SVG
    rsvg-convert -w 1920 -h 1080 wallpaper.svg -o $out/wallpaper.png
  '';
in {
  options.solem.brandingGnome = {
    enable = lib.mkEnableOption "Apply SOLEM navy/gold branding to GNOME desktop";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      dconf
      gnome-tweaks
    ];

    # Wallpaper accessibile system-wide
    environment.etc."solem/wallpaper.png".source = "${solemWallpaper}/wallpaper.png";

    # dconf defaults via programs.dconf (modo NixOS-native, no conflict /etc).
    programs.dconf = {
      enable = true;
      profiles.user.databases = [{
        settings = {
          "org/gnome/desktop/background" = {
            picture-uri = "file://${solemWallpaper}/wallpaper.png";
            picture-uri-dark = "file://${solemWallpaper}/wallpaper.png";
            primary-color = "#0B1426";
            secondary-color = "#D4A24A";
          };
          "org/gnome/desktop/screensaver" = {
            picture-uri = "file://${solemWallpaper}/wallpaper.png";
            primary-color = "#0B1426";
          };
          "org/gnome/desktop/interface" = {
            color-scheme = "prefer-dark";
            gtk-theme = "Adwaita-dark";
            cursor-theme = "Adwaita";
            enable-hot-corners = true;
            clock-show-weekday = true;
            clock-show-date = true;
          };
          "org/gnome/desktop/wm/preferences" = {
            button-layout = "close,minimize,maximize:";
          };
          "org/gnome/shell" = {
            favorite-apps = [
              "firefox.desktop"
              "org.gnome.Nautilus.desktop"
              "org.gnome.Terminal.desktop"
              "org.gnome.Calculator.desktop"
              "org.gnome.Settings.desktop"
            ];
          };
        };
      }];
    };
  };
}
