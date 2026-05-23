{ config, pkgs, lib, ... }:

# SOLEM HANDHELD — profilo handheld FOSS-first (compatibile Steam Deck hw).
#
# Single responsibility: SOLO config "gaming handheld" 100% FOSS:
#   - Gamescope session (Valve, BSD-licensed)
#   - Lutris + Bottles + RetroArch + dolphin-emu come default launcher
#   - Steam closed-source SOLO se l'utente lo abilita esplicitamente
#   - Controller mapping (xbox/playstation)
#   - Audio low-latency PipeWire FOSS
#   - 32-bit gaming libs
#
# 100% FOSS di default. Costo: 0 €.

let
  cfg = config.solem.handheld;
in {
  options.solem.handheld = {
    enable = lib.mkEnableOption "Profilo handheld gaming (FOSS-first)";

    enableSteam = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Abilita Steam (CLOSED-SOURCE proprietario Valve).
        Disabilitato di default per coerenza FOSS-only di SOLEM.
        Quando true: autostart Steam Big Picture in Gamescope session.
      '';
    };

    enableEmulators = lib.mkOption {
      type = lib.types.bool;
      default = true;        # default true per handheld (no closed-source)
      description = "Emulatori FOSS retro (RetroArch + dolphin-emu + pcsx2 + rpcs3)";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── Steam SOLO opt-in esplicito ──
    programs.steam = lib.mkIf cfg.enableSteam {
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

    # ── Gaming tools FOSS ──
    environment.systemPackages = with pkgs; [
      gamescope mangohud goverlay
      lutris bottles
      retroarch-full
    ] ++ lib.optionals cfg.enableEmulators [
      pcsx2 dolphin-emu rpcs3
    ] ++ lib.optional cfg.enableSteam protontricks;

    # ── Gamemode FOSS ──
    programs.gamemode = {
      enable = true;
      settings = {
        general = { renice = 10; };
        cpu = { park_cores = "no"; pin_cores = "yes"; };
      };
    };

    # ── Controller permissions (FOSS udev rules) ──
    services.udev.packages = with pkgs; lib.optional cfg.enableSteam steam-devices;
    hardware.steam-hardware.enable = lib.mkIf cfg.enableSteam true;

    # ── Audio low-latency (PipeWire FOSS) ──
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

    # ── Autostart Steam in Gamescope SOLO se enableSteam ──
    services.greetd = lib.mkIf cfg.enableSteam {
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

    solem.edge.deviceClass = lib.mkDefault "workstation";
    networking.hostName = lib.mkDefault "solem-handheld";
  };
}
