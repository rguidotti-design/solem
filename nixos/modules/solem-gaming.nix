{ config, pkgs, lib, ... }:

# SOLEM GAMING — modulo gaming opt-in 100% FOSS.
#
# Single responsibility: SOLO orchestrazione gaming stack (Steam+Proton,
# Wine, Bottles, Lutris, Waydroid). Niente custom config.
#
# Tutto gratis. Steam è FOSS-friendly (client closed-source, libreria
# locale) — incluso solo se l'utente lo abilita esplicitamente.
#
# Costo licenza: 0 € (giochi che compri sono separati, ovvio).

let
  cfg = config.solem.gaming;
in {
  options.solem.gaming = {
    enable = lib.mkEnableOption "Gaming stack (Steam+Proton, Wine, Lutris, Bottles)";

    waydroid = lib.mkEnableOption "Waydroid (Android apps su Wayland)";

    gamemode = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Feral GameMode (CPU governor + nice + I/O priority)";
    };

    mangohud = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "MangoHud FPS overlay";
    };
  };

  config = lib.mkIf cfg.enable {
    # Steam + Proton
    programs.steam = {
      enable = true;
      remotePlay.openFirewall = false;  # privacy: niente remote play out-of-the-box
      dedicatedServer.openFirewall = false;
      gamescopeSession.enable = true;   # gamescope = wayland compositor per gaming
    };

    # 32-bit support (richiesto da molti giochi)
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    # Pacchetti gaming
    environment.systemPackages = with pkgs; lib.mkMerge [
      [
        wineWowPackages.stable
        winetricks
        lutris
        bottles
        protontricks
        dxvk
        vkbasalt
        mesa-demos
      ]
      (lib.mkIf cfg.mangohud [ pkgs.mangohud ])
    ];

    # GameMode (Feral)
    programs.gamemode = lib.mkIf cfg.gamemode {
      enable = true;
      settings = {
        general = { renice = 10; };
        cpu = { park_cores = "no"; pin_cores = "yes"; };
      };
    };

    # Waydroid (Android su Wayland)
    virtualisation.waydroid.enable = cfg.waydroid;

    # Limiti sysctl per gaming (vm.max_map_count per giochi DX12)
    boot.kernel.sysctl = {
      "vm.max_map_count" = 2147483642;  # Cyberpunk, Star Citizen, ecc.
    };
  };
}
