{ config, pkgs, lib, ... }:

# SOLEM GREETER — schermata di login bella (regreet GTK4 Wayland).
#
# Single responsibility: SOLO config regreet via greetd (display manager
# Wayland minimal). Niente sessione (Hyprland gestito da solem-desktop).
#
# Sostituisce tty getty con grafica branded navy + Cormorant. Login
# avvia automaticamente Hyprland session SOLEM.

let
  cfg = config.solem.greeter;

  # Wallpaper di login generato da SVG navy gradient + "S" gold
  loginBg = pkgs.runCommand "solem-login-bg.png" {
    nativeBuildInputs = [ pkgs.librsvg ];
  } ''
    cat > /tmp/bg.svg <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080" viewBox="0 0 1920 1080">
  <defs>
    <radialGradient id="bg" cx="50%" cy="40%" r="80%">
      <stop offset="0%"   stop-color="#112340"/>
      <stop offset="50%"  stop-color="#0a1628"/>
      <stop offset="100%" stop-color="#050912"/>
    </radialGradient>
  </defs>
  <rect width="1920" height="1080" fill="url(#bg)"/>
  <text x="960" y="540" text-anchor="middle"
        font-family="Cormorant Garamond, Georgia, serif"
        font-size="280" font-weight="300"
        fill="#c9a961" letter-spacing="40"
        opacity="0.12">SOLEM</text>
  <text x="960" y="600" text-anchor="middle"
        font-family="Inter, sans-serif"
        font-size="16" letter-spacing="20"
        fill="#7a8a9a" opacity="0.4">AI-NATIVE OS</text>
</svg>
SVG
    rsvg-convert -w 1920 -h 1080 -o $out /tmp/bg.svg
  '';

  regreetStyle = pkgs.writeText "regreet-style.css" ''
    /* SOLEM greeter — navy + gold + Cormorant */
    window {
      background-image: url('/etc/solem/login-bg.png');
      background-size: cover;
      background-position: center;
    }
    button, entry, label, dropdown {
      font-family: 'Cormorant Garamond', Georgia, serif;
      color: #e8edf5;
    }
    .session-list, .user-list {
      background: rgba(10, 22, 40, 0.78);
      border: 1px solid #c9a961;
      border-radius: 12px;
      padding: 14px;
    }
    entry {
      background: rgba(26, 47, 84, 0.85);
      border: 2px solid #2c4a7a;
      border-radius: 8px;
      padding: 12px 16px;
      font-size: 18px;
      color: #e8edf5;
    }
    entry:focus {
      border-color: #c9a961;
      box-shadow: 0 0 18px rgba(201, 169, 97, 0.25);
    }
    button {
      background: #c9a961;
      color: #050912;
      border: 0;
      border-radius: 8px;
      padding: 12px 24px;
      font-size: 16px;
      font-weight: 500;
      letter-spacing: 0.08em;
    }
    button:hover { background: #e0c585; }
    .clock-time {
      font-size: 96px;
      font-weight: 300;
      color: #e8edf5;
      letter-spacing: 0.04em;
    }
    .clock-date {
      font-size: 14px;
      color: #7a8a9a;
      letter-spacing: 0.2em;
      text-transform: uppercase;
    }
  '';
in {
  options.solem.greeter = {
    enable = lib.mkEnableOption "Greeter login bello (regreet GTK4 navy)";

    session = lib.mkOption {
      type = lib.types.str;
      default = "Hyprland";
      description = "Comando sessione da avviare dopo login (default Hyprland)";
    };
  };

  config = lib.mkIf cfg.enable {
    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --cmd ${cfg.session}";
          user = "greeter";
        };
      };
    };

    # Wallpaper login accessibile
    environment.etc."solem/login-bg.png".source = loginBg;
    environment.etc."xdg/regreet/regreet.css".source = regreetStyle;

    # Font Cormorant disponibile al greeter
    fonts.packages = with pkgs; [ cormorant-garamond ibm-plex ];

    # No console getty visibile (Plymouth + greeter coprono tutto)
    services.getty.autologinUser = lib.mkForce null;
  };
}
