{ config, pkgs, lib, ... }:

# SOLEM MIGRATION TOOL — wizard "trasferisci dati da PC vecchio".
#
# Single responsibility: SOLO orchestrare strumenti di migrazione + CLI:
# - rsync + rclone (Windows SMB / macOS AFP / Linux SSH / cloud generico)
# - smbclient per Windows shares
# - hfsprogs per leggere dischi macOS HFS+
# - apfs-fuse (FOSS, alpha) per APFS read-only
# - Python script `solem-migrate` che fa wizard step-by-step

let
  cfg = config.solem.migrationTool;

  migrateCli = pkgs.writeShellApplication {
    name = "solem-migrate";
    runtimeInputs = with pkgs; [ rsync rclone samba coreutils gum ];
    text = ''
      gum style \
        --foreground 220 --border-foreground 220 --border double \
        --align center --padding "1 2" \
        'SOLEM Migration — porta i dati dal PC vecchio'

      SOURCE=$(gum choose \
        "Windows PC (SMB/CIFS share)" \
        "Mac PC (SSH o SMB share)" \
        "Linux PC (rsync via SSH)" \
        "USB esterno (qualsiasi filesystem)" \
        "Cloud (Dropbox/GoogleDrive/OneDrive via rclone)")

      DEST="$HOME/Migrated-$(date +%Y%m%d)"
      mkdir -p "$DEST"
      gum style --bold "Destinazione: $DEST"

      case "$SOURCE" in
        Windows*)
          HOST=$(gum input --placeholder "IP/hostname Windows (es. 192.168.1.50)")
          SHARE=$(gum input --placeholder "Nome share (es. Users/Pippo)")
          USER=$(gum input --placeholder "User Windows")
          gum style "Connessione SMB a //$HOST/$SHARE..."
          mkdir -p /tmp/winmount
          mount -t cifs "//$HOST/$SHARE" /tmp/winmount -o "user=$USER" || \
            sudo mount -t cifs "//$HOST/$SHARE" /tmp/winmount -o "user=$USER"
          rsync -avh --progress /tmp/winmount/Documents/ "$DEST/Documents/"
          rsync -avh --progress /tmp/winmount/Desktop/ "$DEST/Desktop/" 2>/dev/null || true
          rsync -avh --progress /tmp/winmount/Pictures/ "$DEST/Pictures/"
          sudo umount /tmp/winmount
          ;;
        Mac*)
          HOST=$(gum input --placeholder "hostname Mac (es. ruben-mac.local)")
          USER=$(gum input --placeholder "User Mac")
          gum style "rsync via SSH dal Mac..."
          rsync -avh --progress "$USER@$HOST:~/Documents/" "$DEST/Documents/"
          rsync -avh --progress "$USER@$HOST:~/Desktop/" "$DEST/Desktop/"
          rsync -avh --progress "$USER@$HOST:~/Pictures/" "$DEST/Pictures/"
          ;;
        Linux*)
          HOST=$(gum input --placeholder "hostname Linux")
          USER=$(gum input --placeholder "User Linux")
          rsync -avh --progress "$USER@$HOST:~/" "$DEST/home-$USER/"
          ;;
        USB*)
          gum style "Inserisci USB. Cartelle disponibili:"
          ls /media /run/media /mnt 2>/dev/null || true
          USB=$(gum input --placeholder "Path USB (es. /run/media/$USER/MIODISCO)")
          rsync -avh --progress "$USB/" "$DEST/usb/"
          ;;
        Cloud*)
          gum style "Configura rclone (richiede prima 'rclone config')"
          rclone config
          REMOTE=$(gum input --placeholder "Nome remote (es. gdrive:)")
          rclone copy "$REMOTE" "$DEST/cloud/" --progress
          ;;
      esac

      gum style \
        --foreground 46 --border-foreground 46 --border rounded \
        --align center --padding "1 2" \
        "Migrazione completata!" \
        "Dati in: $DEST"
    '';
  };
in {
  options.solem.migrationTool = {
    enable = lib.mkEnableOption "Wizard migrazione dati da PC vecchio (Win/Mac/Linux/USB/cloud)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      migrateCli
      rsync
      rclone        # cloud generico (Dropbox/GoogleDrive/OneDrive/S3/Backblaze)
      samba         # smbclient + mount.cifs
      cifs-utils    # mount Windows shares
      gum           # TUI elegante
      hfsprogs      # leggere dischi macOS HFS+ (read-only)
    ];
  };
}
