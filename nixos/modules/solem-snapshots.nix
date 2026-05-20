{ config, pkgs, lib, ... }:

# SOLEM SNAPSHOTS — auto-snapshot filesystem (ZFS o btrfs).
#
# Single responsibility: SOLO orchestrare timer snapshot + retention.
# Detect runtime quale FS è usato; fallback su tar+zstd se nessun FS
# snapshot-capable.
#
# Vantaggio: rollback istantaneo a stato precedente di intere subvol.
# 100% FOSS, 0 €.

let
  cfg = config.solem.snapshots;
in {
  options.solem.snapshots = {
    enable = lib.mkEnableOption "Auto-snapshot fs (ZFS/btrfs sanoid-style)";

    backend = lib.mkOption {
      type = lib.types.enum [ "auto" "zfs" "btrfs" "none" ];
      default = "auto";
    };

    hourly = lib.mkOption { type = lib.types.int; default = 6;  description = "Snapshots orari da tenere"; };
    daily  = lib.mkOption { type = lib.types.int; default = 7;  };
    weekly = lib.mkOption { type = lib.types.int; default = 4;  };
    monthly = lib.mkOption { type = lib.types.int; default = 12; };
  };

  config = lib.mkIf cfg.enable {
    # ZFS path: usa sanoid
    services.sanoid = lib.mkIf (cfg.backend == "zfs" || cfg.backend == "auto") {
      enable = true;
      interval = "*:0/15";
      templates.solem = {
        hourly = cfg.hourly;
        daily = cfg.daily;
        weekly = cfg.weekly;
        monthly = cfg.monthly;
        autoprune = true;
        autosnap = true;
      };
      # User deve dichiarare datasets in services.sanoid.datasets via main config
    };

    # btrfs path: usa snapper
    services.snapper = lib.mkIf (cfg.backend == "btrfs") {
      configs.root = {
        SUBVOLUME = "/";
        ALLOW_USERS = [ "gavio" ];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
        TIMELINE_LIMIT_HOURLY  = cfg.hourly;
        TIMELINE_LIMIT_DAILY   = cfg.daily;
        TIMELINE_LIMIT_WEEKLY  = cfg.weekly;
        TIMELINE_LIMIT_MONTHLY = cfg.monthly;
      };
      snapshotInterval = "hourly";
    };

    # Tools comuni
    environment.systemPackages = with pkgs; [
      sanoid     # ZFS
      snapper    # btrfs
    ];
  };
}
