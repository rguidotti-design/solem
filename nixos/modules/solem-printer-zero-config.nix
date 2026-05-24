{ config, pkgs, lib, ... }:

# SOLEM PRINTER ZERO-CONFIG — auto-discovery stampanti/scanner di rete.
#
# Single responsibility: SOLO configurare CUPS + Avahi + driverless IPP +
# sane-airscan per discovery automatica plug-and-play (AirPrint-like).

let
  cfg = config.solem.printerZeroConfig;
in {
  options.solem.printerZeroConfig = {
    enable = lib.mkEnableOption "Stampa/scan auto-discovery di rete (CUPS + Avahi + IPP)";

    drivers = lib.mkOption {
      type = lib.types.listOf (lib.types.enum [
        "hp" "epson" "canon" "brother" "samsung" "gutenprint"
      ]);
      default = [ "gutenprint" "hp" "epson" ];
      description = "Driver vendor da includere (gutenprint copre ~80% modelli)";
    };
  };

  config = lib.mkIf cfg.enable {
    services.printing = {
      enable = true;
      drivers = with pkgs; lib.flatten [
        (lib.optionals (lib.elem "gutenprint" cfg.drivers) [ gutenprint gutenprintBin ])
        (lib.optionals (lib.elem "hp" cfg.drivers) [ hplip hplipWithPlugin ])
        (lib.optionals (lib.elem "epson" cfg.drivers) [ epson-escpr epson-escpr2 ])
        (lib.optionals (lib.elem "canon" cfg.drivers) [ cnijfilter2 ])
        (lib.optionals (lib.elem "brother" cfg.drivers) [ brlaser brgenml1lpr ])
        (lib.optionals (lib.elem "samsung" cfg.drivers) [ splix ])
      ];
      browsing = true;
      browsedConf = ''
        BrowseDNSSDSubTypes _cups,_print
        BrowseLocalProtocols all
        BrowseRemoteProtocols all
        CreateIPPPrinterQueues All
        BrowseProtocols all
      '';
    };

    # Avahi essenziale per discovery mDNS (AirPrint-compatibile)
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        userServices = true;
        addresses = true;
      };
    };

    # SANE scanner USB + AirScan wireless
    hardware.sane = {
      enable = true;
      extraBackends = with pkgs; [ sane-airscan epkowa ];
      disabledDefaultBackends = [];
    };
    services.udev.packages = with pkgs; [ sane-airscan ];

    # GUI tools
    environment.systemPackages = with pkgs; [
      system-config-printer        # GTK GUI gestione stampanti
      simple-scan                  # GTK GUI scanner facile
      skanlite                     # Qt GUI scanner (alt)
    ];

    # Apri porte LAN per IPP (sicuro: solo LAN)
    networking.firewall.allowedTCPPorts = [ 631 ];     # IPP
    networking.firewall.allowedUDPPorts = [ 631 5353 ]; # IPP + mDNS
  };
}
