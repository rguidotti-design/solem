{ config, pkgs, lib, ... }:

let
  cfg = config.solem.desktop;
in {
  # ──────────────────────────────────────────────────────────────────────
  # SOLEM DESKTOP — ambiente grafico Wayland (opt-in)
  # ──────────────────────────────────────────────────────────────────────
  # Filosofia: SOLEM resta primariamente "AI-conversation as shell".
  # Desktop GUI è un'OPZIONE per chi vuole un ambiente grafico tradizionale.
  #
  # Stack scelto (leggero, AI-native friendly):
  #   - Hyprland (compositor Wayland tiling, configurabile in 1 file)
  #   - greetd + tuigreet (display manager terminale stilizzato)
  #   - Pipewire (audio moderno, default NixOS)
  #   - Firefox + Alacritty + Files (essenziali)
  #   - Bluetooth + Network applet
  #
  # Default DISABILITATO in VM Step 0 (4GB RAM in VM TCG = pesante).
  # Attivare con: solem.desktop.enable = true; in configuration.nix.

  options.solem.desktop = {
    enable = lib.mkEnableOption "Ambiente grafico Wayland (Hyprland)";

    autoLogin = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Se true, usa greetd con auto-login utente gavio e auto-launch Hyprland.
        Se false (default), Hyprland è installato ma si avvia a mano da console.
      '';
    };

    kiosk = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Modalità kiosk: dopo Hyprland, lancia Firefox fullscreen sulla dashboard
        SOLEM (http://localhost:8001). L'utente vede direttamente "l'OS visibile"
        senza dover aprire applicazioni manualmente.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs; [
        firefox          # browser
        alacritty        # terminale GPU-accelerato
        gnome-text-editor
        nautilus         # file manager
        pavucontrol      # mixer audio
      ];
      description = "Pacchetti desktop aggiunti se solem.desktop attivo.";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── Hyprland compositor ─────────────────────────────────────────
    programs.hyprland = {
      enable = true;
      xwayland.enable = true;  # compatibilità app X11 legacy
    };

    # ── Kiosk mode: cage (compositor minimal) + Firefox fullscreen ──
    # cage è 1/10 di Hyprland, software-renderable via WLR_RENDERER=pixman.
    # Funziona in QEMU TCG senza accelerazione GPU.
    #
    # Flow: greetd auto-launch → cage → firefox --kiosk http://localhost:8001
    services.greetd = lib.mkIf cfg.autoLogin {
      enable = true;
      settings.default_session =
        if cfg.kiosk then {
          # KIOSK: auto-launch cage + firefox a fullscreen su dashboard
          command = "${pkgs.cage}/bin/cage -d -- ${pkgs.firefox}/bin/firefox --kiosk http://localhost:8001";
          user = "gavio";
        } else {
          # NON-KIOSK: tuigreet → l'utente sceglie sessione
          command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --cmd Hyprland";
          user = "greeter";
        };
    };

    # Environment per software rendering wlroots (no GPU richiesta in TCG)
    environment.sessionVariables = lib.mkIf cfg.kiosk {
      WLR_RENDERER = "pixman";              # software rendering, no GL
      WLR_NO_HARDWARE_CURSORS = "1";        # mouse cursor via software
      MOZ_ENABLE_WAYLAND = "1";             # Firefox Wayland-native
      LIBGL_ALWAYS_SOFTWARE = "1";          # software OpenGL fallback
    };

    # cage è aggiunto ai systemPackages nella dichiarazione principale sotto.
    # Config Hyprland kiosk rimosso da qui (non era nemmeno usato perché ora
    # usiamo cage). Se in futuro serve Hyprland kiosk, ridichiarare con
    # `environment.etc = lib.mkIf cfg.kiosk { ... }`.

    # ── Audio: Pipewire (replacement moderno di PulseAudio) ────────
    hardware.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };

    # ── Bluetooth ───────────────────────────────────────────────────
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
    services.blueman.enable = true;

    # ── Stampa (opzionale, CUPS) ────────────────────────────────────
    services.printing.enable = true;

    # ── XDG portals (per app GTK/Qt su Wayland) ─────────────────────
    xdg.portal = {
      enable = true;
      extraPortals = with pkgs; [ xdg-desktop-portal-hyprland xdg-desktop-portal-gtk ];
    };

    # ── Font di sistema (per UI non-pixel-ugly) ─────────────────────
    fonts = {
      packages = with pkgs; [
        inter
        jetbrains-mono
        noto-fonts
        noto-fonts-emoji
        noto-fonts-cjk-sans
        liberation_ttf
      ];
      fontconfig = {
        defaultFonts = {
          sansSerif = [ "Inter" ];
          monospace = [ "JetBrains Mono" ];
          serif = [ "Liberation Serif" ];
        };
      };
    };

    # ── Pacchetti utente desktop (unica dichiarazione) ──────────────
    environment.systemPackages = cfg.extraPackages ++ (with pkgs; [
      # Hyprland ecosystem
      waybar wofi mako
      grim slurp wl-clipboard cliphist
      swaybg          # wallpaper backend
      brightnessctl   # luminosità schermo
      librsvg         # rsvg-convert per SVG→PNG runtime
      cage            # compositor kiosk minimal (TCG-friendly via WLR_RENDERER=pixman)
    ]);

    # ── Asset desktop SOLEM branded (palette navy + logo) ──────────
    # Montati in /etc/xdg/solem/ e referenziati dai config Hyprland/Waybar.
    environment.etc = {
      "xdg/solem/wallpaper.svg".source = ../desktop-assets/wallpaper.svg;
      "xdg/solem/hyprland.conf".source = ../desktop-assets/hyprland.conf;
      "xdg/solem/waybar.css".source    = ../desktop-assets/waybar.css;
      "xdg/solem/waybar.jsonc".source  = ../desktop-assets/waybar.jsonc;
    };

    # Wallpaper PNG generato da SVG (per swaybg che richiede raster).
    system.activationScripts.solem-wallpaper = ''
      if [ ! -f /etc/xdg/solem/wallpaper.png ]; then
        ${pkgs.librsvg}/bin/rsvg-convert -w 1920 -h 1080 \
          /etc/xdg/solem/wallpaper.svg \
          -o /etc/xdg/solem/wallpaper.png 2>/dev/null || true
      fi
    '';
  };
}
