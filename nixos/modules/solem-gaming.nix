{ config, pkgs, lib, ... }:

# SOLEM GAMING — modulo gaming 100% FOSS.
#
# Single responsibility: SOLO orchestrazione gaming stack open-source:
# Wine + Lutris + Bottles + RetroArch + Wayland gamescope. Niente Steam
# di default (proprietario; chi lo vuole lo installa via Flatpak come
# scelta esplicita, separata da SOLEM).
#
# 100% FOSS. Costo: 0 €.

let
  cfg = config.solem.gaming;
in {
  options.solem.gaming = {
    enable = lib.mkEnableOption "Gaming stack FOSS (Wine + Lutris + Bottles + RetroArch + gamescope)";

    enableSteam = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Abilita Steam (closed-source). NON incluso di default per coerenza
        FOSS-only. L'utente che lo vuole può abilitarlo esplicitamente.
      '';
    };

    waydroid = lib.mkEnableOption "Waydroid (Android apps FOSS su Wayland)";

    gamemode = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Feral GameMode FOSS (CPU governor + nice + I/O priority)";
    };

    mangohud = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "MangoHud FPS overlay FOSS";
    };
  };

  config = lib.mkIf cfg.enable {
    # Steam SOLO se l'utente lo abilita esplicitamente (closed-source)
    programs.steam = lib.mkIf cfg.enableSteam {
      enable = true;
      remotePlay.openFirewall = false;
      dedicatedServer.openFirewall = false;
      gamescopeSession.enable = true;
    };

    # 32-bit support (richiesto da molti giochi Wine)
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    # Pacchetti gaming 100% FOSS
    environment.systemPackages = with pkgs; lib.mkMerge [
      [
        wineWowPackages.stable
        winetricks
        lutris
        bottles
        dxvk
        vkbasalt
        mesa-demos
        gamescope        # Wayland compositor per giochi (Valve, FOSS)
        retroarch-full   # multi-emulator FOSS
      ]
      (lib.mkIf cfg.mangohud [ pkgs.mangohud ])
    ];

    # GameMode (Feral, FOSS)
    programs.gamemode = lib.mkIf cfg.gamemode {
      enable = true;
      settings = {
        general = { renice = 10; };
        cpu = { park_cores = "no"; pin_cores = "yes"; };
      };
    };

    # Waydroid (FOSS Android su Wayland)
    virtualisation.waydroid.enable = cfg.waydroid;

    # Limiti sysctl per gaming
    boot.kernel.sysctl = {
      "vm.max_map_count" = 2147483642;
    };
  };
}
