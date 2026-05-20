{ config, pkgs, lib, ... }:

# SOLEM PHOTO+MUSIC — server multimedia self-host (Immich + Navidrome).
#
# Single responsibility: SOLO orchestrare server multimedia. Niente client
# (Immich ha mobile FOSS; Navidrome usa Subsonic clients standard).
#
# Vantaggi vs iCloud Photo / Spotify Premium:
#   - 100% locale, niente upload cloud
#   - FOSS, costo 0 € (vs Spotify 11€/mese, iCloud 1€/mese)
#   - AI tagging foto offline (Immich Machine Learning)
#
# Storage: l'utente fornisce path su disco/NAS.

let
  cfg = config.solem.photoMusic;
in {
  options.solem.photoMusic = {
    immich = {
      enable = lib.mkEnableOption "Immich (Google Photos FOSS alternative)";
      port = lib.mkOption { type = lib.types.port; default = 2283; };
      uploadDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/immich/upload";
      };
      libraryDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/immich/library";
      };
    };

    navidrome = {
      enable = lib.mkEnableOption "Navidrome (Spotify FOSS alternative, Subsonic API)";
      port = lib.mkOption { type = lib.types.port; default = 4533; };
      musicFolder = lib.mkOption {
        type = lib.types.path;
        default = "/home/gavio/Music";
      };
    };

    jellyfin = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Jellyfin (Netflix FOSS alternative per film/serie locali)";
    };
  };

  config = lib.mkMerge [
    # Immich
    (lib.mkIf cfg.immich.enable {
      services.immich = {
        enable = true;
        port = cfg.immich.port;
        host = "127.0.0.1";
        mediaLocation = cfg.immich.libraryDir;
        machine-learning.enable = true;
      };

      systemd.tmpfiles.rules = [
        "d ${toString cfg.immich.uploadDir}  0755 immich immich - -"
        "d ${toString cfg.immich.libraryDir} 0755 immich immich - -"
      ];
    })

    # Navidrome
    (lib.mkIf cfg.navidrome.enable {
      services.navidrome = {
        enable = true;
        openFirewall = false;  # solo localhost / mesh
        settings = {
          MusicFolder = toString cfg.navidrome.musicFolder;
          Port = cfg.navidrome.port;
          Address = "127.0.0.1";
          BaseUrl = "/navidrome";
          ScanSchedule = "@every 1h";
          LogLevel = "info";
          EnableSharing = true;
        };
      };
    })

    # Jellyfin
    (lib.mkIf cfg.jellyfin {
      services.jellyfin = {
        enable = true;
        openFirewall = false;
      };
      environment.systemPackages = with pkgs; [
        jellyfin-ffmpeg
        jellyfin-web
      ];
    })
  ];
}
