{ config, pkgs, lib, ... }:

# SOLEM PRINT/SCAN — CUPS + SANE opt-in.
#
# Single responsibility: SOLO abilitare stampa/scansione system-wide.
# Driver vendor: HP, Brother, Canon. Tutti FOSS, costo 0 €.

let
  cfg = config.solem.printScan;
in {
  options.solem.printScan = {
    enable = lib.mkEnableOption "Stampa (CUPS) + scansione (SANE)";

    enableHP = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Driver HP (hplip)";
    };

    enableBrother = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Driver Brother";
    };

    enableNetworkDiscovery = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Avahi mDNS per scoprire stampanti su LAN";
    };
  };

  config = lib.mkIf cfg.enable {
    # CUPS
    services.printing = {
      enable = true;
      drivers = with pkgs; lib.mkMerge [
        (lib.mkIf cfg.enableHP [ hplip ])
        (lib.mkIf cfg.enableBrother [ brlaser brgenml1lpr brgenml1cupswrapper ])
        [ gutenprint gutenprintBin ]
      ];
    };

    # mDNS discovery
    services.avahi = lib.mkIf cfg.enableNetworkDiscovery {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
      publish = {
        enable = true;
        addresses = true;
        userServices = true;
      };
    };

    # SANE (scanner)
    hardware.sane = {
      enable = true;
      extraBackends = with pkgs; lib.optional cfg.enableHP hplipWithPlugin;
    };

    environment.systemPackages = with pkgs; [
      simple-scan
      cups-pdf-to-pdf
    ];

    # gavio user nel gruppo scanner
    users.users.gavio.extraGroups = [ "scanner" "lp" ];
  };
}
