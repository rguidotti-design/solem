{ config, pkgs, lib, ... }:

# SOLEM CLOUD SYNC — sync Google Drive / OneDrive / Dropbox / S3 via rclone.
#
# Single responsibility: SOLO CLI `solem-cloud-sync` wrapper rclone (FOSS,
# MIT) per 70+ cloud provider. Pattern: pull/push, no daemon.

let
  cfg = config.solem.cloudSync;

  syncCli = pkgs.writeShellApplication {
    name = "solem-cloud-sync";
    runtimeInputs = with pkgs; [ coreutils rclone ];
    text = ''
      ACTION="''${1:-help}"
      shift || true

      case "$ACTION" in
        config|setup)
          rclone config
          ;;

        list|ls)
          rclone listremotes
          ;;

        # Pull cloud → locale
        pull)
          REMOTE="''${1:?Usage: solem-cloud-sync pull <remote>: <local-dir>}"
          DEST="''${2:?Usage: solem-cloud-sync pull <remote>: <local-dir>}"
          rclone copy --progress "$REMOTE" "$DEST"
          ;;

        # Push locale → cloud
        push)
          SRC="''${1:?Usage: solem-cloud-sync push <local-dir> <remote>:}"
          REMOTE="''${2:?Usage: solem-cloud-sync push <local-dir> <remote>:}"
          rclone copy --progress "$SRC" "$REMOTE"
          ;;

        # Sync bidirezionale (cautela)
        sync)
          SRC="''${1:?}"
          DEST="''${2:?}"
          rclone bisync --progress "$SRC" "$DEST"
          ;;

        # Mount cloud come filesystem
        mount)
          REMOTE="''${1:?Usage: solem-cloud-sync mount <remote>: <mountpoint>}"
          MOUNT="''${2:?}"
          mkdir -p "$MOUNT"
          rclone mount "$REMOTE" "$MOUNT" --daemon --vfs-cache-mode writes
          echo "Cloud montato in $MOUNT (in background)"
          ;;

        # Unmount
        umount|unmount)
          MOUNT="''${1:?}"
          fusermount -u "$MOUNT"
          ;;

        # Listing veloce
        tree)
          REMOTE="''${1:?Usage: solem-cloud-sync tree <remote>:}"
          rclone tree "$REMOTE" | head -50
          ;;

        # Spazio usato
        du)
          REMOTE="''${1:?Usage: solem-cloud-sync du <remote>:}"
          rclone size "$REMOTE"
          ;;

        # HELP
        help|--help|-h|*)
          cat <<'HELP'
solem-cloud-sync — rclone wrapper (70+ cloud provider)

  Setup (una tantum per ogni provider):
    solem-cloud-sync config           wizard interattivo rclone

  Provider gratuiti popolari:
    Google Drive (15 GB free)
    OneDrive (5 GB free)
    Dropbox (2 GB free)
    pCloud (10 GB free)
    Mega.io (20 GB free)
    Storj (25 GB free, FOSS)
    Backblaze B2 (10 GB free)
    AWS S3 (5 GB free 12 mesi)
    Yandex Disk (5 GB free)

  Comandi:
    solem-cloud-sync list                       lista remotes configurati
    solem-cloud-sync pull gdrive: ~/Downloads   download tutto
    solem-cloud-sync push ~/Documents gdrive:   upload tutto
    solem-cloud-sync sync local gdrive:         bidirezionale
    solem-cloud-sync mount gdrive: ~/gdrive     mount FUSE
    solem-cloud-sync tree gdrive:               vedi struttura
    solem-cloud-sync du gdrive:                 spazio usato

Tutto FOSS (rclone MIT). 0 €.
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.cloudSync = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa `solem-cloud-sync` rclone wrapper (70+ provider)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      syncCli
      rclone
    ];
  };
}
