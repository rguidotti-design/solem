{ config, pkgs, lib, ... }:

# SOLEM HANDHELD — profilo Steam Deck / Steam-Deck-like handheld.
#
# Single responsibility: SOLO config "gaming handheld":
#   - Gamescope session (compositor minimal per giochi fullscreen)
#   - Steam embedded autostart
#   - Controller mapping (xbox/playstation)
#   - On-screen keyboard touch-friendly (squeekboard)
#   - Bluetooth + audio low-latency
#   - 32-bit gaming libs

let
  cfg = config.solem.handheld;
in {
  options.solem.handheld = {
    enable = lib.mkEnableOption "Profilo handheld gaming (Steam Deck-like)";

    autostartSteam = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Avvia Steam Big Picture al boot (Gamescope session)";
    };

    enableEmulators = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Emulatori retro (RetroArch + cores comuni)";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── Steam + Gamescope ──
    programs.steam = {
      enable = true;
      gamescopeSession.enable = true;
      remotePlay.openFirewall = false;
      dedicatedServer.openFirewall = false;
      extraCompatPackages = with pkgs; [ proton-ge-bin ];
    };

    # 32-bit support
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    # ── Gaming tools ──
    environment.systemPackages = with pkgs; [
      gamescope mangohud goverlay protontricks
      lutris bottles heroic
    ] ++ lib.optionals cfg.enableEmulators [
      retroarch-full pcsx2 dolphin-emu rpcs3
    ];

    # ── Gamemode (CPU/GPU boost on demand) ──
    programs.gamemode = {
      enable = true;
      settings = {
        general = { renice = 10; };
        cpu = { park_cores = "no"; pin_cores = "yes"; };
      };
    };

    # ── Controller permissions ──
    services.udev.packages = with pkgs; [ steam-devices ];
    hardware.steam-hardware.enable = true;

    # ── Touch keyboard + accessibility ──
    services.xserver.desktopManager.gnome.extraGSettingsOverrides = ''
      [org.gnome.desktop.a11y.applications]
      screen-keyboard-enabled=true
    '';

    # ── Audio low-latency (PipeWire) ──
    services.pipewire = {
      enable = true;
      audio.enable = true;
      alsa.enable = true;
      pulse.enable = true;
      jack.enable = false;
      extraConfig.pipewire."92-low-latency" = {
        "context.properties" = {
          "default.clock.rate" = 48000;
          "default.clock.quantum" = 256;
          "default.clock.min-quantum" = 256;
          "default.clock.max-quantum" = 256;
        };
      };
    };

    # ── Autostart Steam in Gamescope (kiosk-style) ──
    services.greetd = lib.mkIf cfg.autostartSteam {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd 'steam-gamescope'";
          user = "greeter";
        };
        initial_session = {
          command = "${pkgs.bash}/bin/bash -c 'gamescope-session -- steam -gamepadui'";
          user = "gavio";
        };
      };
    };

    # ── Edge profile ──
    solem.edge.deviceClass = lib.mkDefault "workstation";  # handheld ha potenza desktop

    networking.hostName = lib.mkDefault "solem-handheld";
  };
}
