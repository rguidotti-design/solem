{ config, pkgs, lib, ... }:

# SOLEM GAMING EXTRAS — Heroic + Proton-GE + Lutris catalog.
#
# Single responsibility: SOLO orchestrare launcher gaming FOSS aggiuntivi
# (complementare a solem-gaming.nix che fa Wine/Lutris/Bottles base).
# Steam resta opt-in granulare nel modulo solem-gaming.

let
  cfg = config.solem.gamingExtras;
in {
  options.solem.gamingExtras = {
    enable = lib.mkEnableOption "Launcher gaming extra FOSS (Heroic + ProtonUp + Lutris extra)";

    heroic = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Heroic Games Launcher — Epic Games + GOG + Amazon Prime Gaming (GPL-3.0)";
    };

    protonUp = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "ProtonUp-Qt — gestisce Proton-GE custom (GPL-3.0)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; lib.flatten [
      [
        # Lutris ha già il catalogo cloud-free per giochi vecchi
        # Heroic per Epic / GOG / Amazon
      ]

      (lib.optionals cfg.heroic [
        heroic
      ])

      (lib.optionals cfg.protonUp [
        protonup-qt
      ])
    ];
  };
}
