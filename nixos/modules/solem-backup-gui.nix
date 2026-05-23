{ config, pkgs, lib, ... }:

# SOLEM BACKUP GUI — interfacce grafiche per backup utente FOSS.
#
# Single responsibility: SOLO GUI per backup utente. La logica CLI è in
# [[solem-backup-restic]] e [[solem-backup]]. Qui aggiungiamo:
# - Pika Backup    → GTK4 GUI su Borg (GPL-3.0)
# - Vorta          → Qt GUI su Borg (GPL-3.0)
# - Déjà Dup       → GNOME backup GUI su Duplicity (GPL-3.0)
# - Syncthing-tray → tray icon Syncthing (LGPL-3.0)
# - Grsync         → GUI rsync (GPL-2.0)
# - Timeshift      → snapshot system-wide GUI (GPL-3.0)
# - kup-backup     → KDE Plasma backup GUI (GPL-2.0)
#
# Tutto FOSS, 0 €.

let
  cfg = config.solem.backupGui;
in {
  options.solem.backupGui = {
    enable = lib.mkEnableOption "GUI backup utente FOSS (Pika + Vorta + Déjà Dup + Grsync)";

    pika = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Pika Backup (GTK4, BorgBackup engine, raccomandato)";
    };

    vorta = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Vorta (Qt, BorgBackup engine, alternativa cross-DE)";
    };

    dejaDup = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Déjà Dup (GNOME, Duplicity engine, semplice)";
    };

    syncthingTray = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Tray icon Syncthing + GTK GUI";
    };

    timeshift = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Timeshift — snapshot system-wide (alt-Restic, per BTRFS/rsync)";
    };

    kde = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "kup-backup — backup GUI integrato KDE Plasma";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; lib.flatten [
      [
        # Engine sempre presenti (richiesto dalle GUI)
        borgbackup
        restic
        duplicity
        rsync

        # GUI rsync (sempre utile)
        grsync
      ]

      (lib.optionals cfg.pika [
        pika-backup
      ])

      (lib.optionals cfg.vorta [
        vorta
      ])

      (lib.optionals cfg.dejaDup [
        deja-dup
      ])

      (lib.optionals cfg.syncthingTray [
        syncthingtray-minimal
      ])

      (lib.optionals cfg.timeshift [
        timeshift
      ])

      (lib.optionals cfg.kde [
        kup
        bup           # backend kup
      ])
    ];
  };
}
