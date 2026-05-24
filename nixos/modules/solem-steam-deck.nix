{ config, pkgs, lib, ... }:

# SOLEM STEAM DECK — preset gaming pronto in 3 click.
#
# Single responsibility: SOLO orchestrare:
# - Steam (closed-source, opt-in esplicito)
# - Proton-GE custom (FOSS fork con fixes per giochi extra)
# - GameMode (FOSS, Feral Interactive, CPU/GPU/IO tuning automatico)
# - MangoHud (FOSS, FPS overlay)
# - gamescope (FOSS, Valve, Wayland compositor per giochi)
# - Lutris (FOSS, launcher universale)
# - Heroic (FOSS, Epic/GOG/Amazon)
#
# Cosa NON include (per principio FOSS-only di default):
# - Anti-cheat kernel (Easy Anti-Cheat, BattlEye sono closed)
#   Funzionano automaticamente via Proton se il gioco li supporta.

let
  cfg = config.solem.steamDeck;
in {
  options.solem.steamDeck = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Abilita gaming stack 'Steam Deck like'.
        Include Steam (closed-source) + tools FOSS.
        OPT-IN: l'utente accetta esplicitamente Steam closed.
      '';
    };

    gameMode = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Feral GameMode (FOSS, CPU/IO/GPU tuning automatico)";
    };

    mangohud = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "MangoHud FPS overlay (FOSS)";
    };

    gamescope = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Gamescope (FOSS, Valve, micro-compositor per giochi)";
    };
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.config.allowUnfree = true;

    programs.steam = {
      enable = true;
      remotePlay.openFirewall = false;
      dedicatedServer.openFirewall = false;
      gamescopeSession.enable = cfg.gamescope;
    };

    # 32-bit graphics support (richiesto da quasi tutti i giochi)
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    # GameMode tuning
    programs.gamemode = lib.mkIf cfg.gameMode {
      enable = true;
      settings = {
        general.renice = 10;
        cpu.park_cores = "no";
        cpu.pin_cores = "yes";
        gpu.apply_gpu_optimisations = "accept-responsibility";
        gpu.gpu_device = 0;
        gpu.amd_performance_level = "high";
      };
    };

    environment.systemPackages = with pkgs; lib.flatten [
      [
        # FOSS gaming tools
        lutris            # launcher universale
        heroic            # Epic/GOG/Amazon
        bottles           # Wine prefix GUI
        protonup-qt       # Proton-GE custom manager

        # Wine for non-Steam games
        wineWowPackages.stable
        winetricks

        # Performance
        dxvk              # DirectX 11 → Vulkan
        vkbasalt          # FOSS post-processing

        # Emulazione console retro
        retroarch
      ]

      (lib.optionals cfg.mangohud [
        mangohud
        goverlay          # GUI per MangoHud
      ])

      (lib.optionals cfg.gamescope [
        gamescope
      ])
    ];

    # sysctl per gaming (vm.max_map_count alto per Star Citizen/etc)
    boot.kernel.sysctl = {
      "vm.max_map_count" = 2147483642;
    };

    # User in gamemode group
    users.groups.gamemode = {};
  };
}
