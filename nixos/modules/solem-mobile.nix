{ config, pkgs, lib, ... }:

# SOLEM MOBILE — integrazione smartphone (KDE Connect + Syncthing).
#
# Single responsibility: SOLO orchestrare KDE Connect daemon + Syncthing.
# Niente UI custom: usa client ufficiali (gsconnect/valent per GNOME,
# native su KDE).
#
# Features (con KDE Connect Android/iOS):
#   - Notifiche smartphone → desktop e viceversa
#   - Clipboard sync bidirezionale
#   - File transfer P2P (no cloud)
#   - Remote input (mouse/keyboard da smartphone)
#   - SMS reply dal desktop
#   - Ring my phone
#
# 100% FOSS, costo 0 €. Zero cloud: tutto LAN o mesh WireGuard.

let
  cfg = config.solem.mobile;
in {
  options.solem.mobile = {
    enable = lib.mkEnableOption "Integrazione smartphone (KDE Connect)";

    syncthing = lib.mkEnableOption "Syncthing P2P file sync (alternativa Dropbox)";

    syncthingUser = lib.mkOption {
      type = lib.types.str;
      default = "gavio";
    };

    syncthingFolders = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Mappa nome→path delle cartelle da sync (config manuale via GUI port 8384)";
      example = { documents = "/home/gavio/Documents"; };
    };
  };

  config = lib.mkMerge [
    # KDE Connect
    (lib.mkIf cfg.enable {
      programs.kdeconnect = {
        enable = true;
        package = pkgs.gnomeExtensions.gsconnect;  # versione GNOME
      };

      # Firewall: KDE Connect usa porte 1714-1764 UDP+TCP
      networking.firewall = {
        allowedTCPPortRanges = [{ from = 1714; to = 1764; }];
        allowedUDPPortRanges = [{ from = 1714; to = 1764; }];
      };

      environment.systemPackages = with pkgs; [
        kdePackages.kdeconnect-kde  # GUI standalone (alternativa GNOME)
      ];
    })

    # Syncthing
    (lib.mkIf cfg.syncthing {
      services.syncthing = {
        enable = true;
        user = cfg.syncthingUser;
        dataDir = "/var/lib/syncthing";
        configDir = "/var/lib/syncthing/.config/syncthing";

        openDefaultPorts = true;

        settings = {
          options = {
            urAccepted = -1;       # disable usage reporting
            crashReportingEnabled = false;
            globalAnnounceEnabled = false;  # privacy: solo discovery locale + mesh
            relaysEnabled = false;           # no relay esterni
            localAnnounceEnabled = true;
            natEnabled = false;              # solo LAN/mesh
          };

          folders = lib.mapAttrs (name: path: {
            inherit path;
            id = name;
            type = "sendreceive";
          }) cfg.syncthingFolders;

          gui = {
            address = "127.0.0.1:8384";
          };
        };
      };
    })
  ];
}
