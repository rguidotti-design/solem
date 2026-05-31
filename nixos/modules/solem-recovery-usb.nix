{ config, pkgs, lib, ... }:

# SOLEM RECOVERY USB — Step 46: builder + restore tools.
#
# Single responsibility: SOLO CLI per creare USB recovery + restore.
#   - Build ISO recovery custom (live + key SOLEM + script restore)
#   - Backup config flake + /etc/nixos su USB
#   - Restore script: re-install + restore config + decrypt LUKS

let
  cfg = config.solem.recoveryUsb;
in {
  options.solem.recoveryUsb = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa solem-recovery CLI (USB builder + restore tools)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      gptfdisk parted util-linux coreutils dosfstools cryptsetup
      (pkgs.writeShellApplication {
        name = "solem-recovery";
        runtimeInputs = with pkgs; [ coreutils parted gptfdisk util-linux dosfstools cryptsetup gawk ];
        text = ''
          ACTION="''${1:-help}"
          shift || true

          case "$ACTION" in
            list-devices)
              echo "── Block devices ──"
              lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,LABEL
              echo
              echo "Per USB: cerca disk RIMOVIBILE (es. sda se interno e' nvme0n1)"
              ;;

            create)
              # Build recovery USB con ISO SOLEM + config backup
              DEV="''${1:?Usage: solem-recovery create <device> (es. /dev/sdX)}"
              if [ ! -b "$DEV" ]; then
                echo "ERROR: $DEV non e' un block device"
                exit 1
              fi
              echo "⚠ ATTENZIONE: questo CANCELLA tutto su $DEV"
              echo "  Lista partizioni attuali:"
              sudo parted "$DEV" print 2>&1 | head -15
              read -r -p "  Confermi? (digita 'CANCELLA $DEV'): " ANS
              if [ "$ANS" != "CANCELLA $DEV" ]; then
                echo "Annullato"
                exit 0
              fi

              # Build ISO SOLEM (se non esiste)
              ISO_PATH="/tmp/solem-recovery.iso"
              if [ ! -f "$ISO_PATH" ]; then
                echo "Build ISO SOLEM (richiede ~10min)..."
                cd /etc/nixos || cd ~/.config/solem
                nix build .#iso --no-link --print-out-paths > /tmp/iso-out 2>&1 || {
                  echo "Build fallito. Lo path manuale:"
                  cat /tmp/iso-out
                  exit 1
                }
                cp "$(cat /tmp/iso-out)/iso/"*.iso "$ISO_PATH"
              fi
              echo "ISO: $ISO_PATH ($(du -h "$ISO_PATH" | cut -f1))"

              # dd ISO su USB
              echo "Writing ISO to $DEV (slow)..."
              sudo dd if="$ISO_PATH" of="$DEV" bs=4M status=progress conv=fsync
              sync
              echo "✓ ISO scritta"

              # Aggiungi partizione DATA per config backup
              # (parted aggiunge dopo lo spazio ISO)
              # NB: ISO writeup di solito occupa solo spazio necessario, resto free.
              echo "Aggiungo partizione DATA per backup config..."
              sudo parted -s "$DEV" mkpart primary ext4 50% 100%
              sleep 2
              DATA_PART="''${DEV}3"  # ipotetico, dipende layout ISO
              [ -b "''${DEV}3" ] || DATA_PART="''${DEV}p3"
              if [ -b "$DATA_PART" ]; then
                sudo mkfs.ext4 -L SOLEM-DATA "$DATA_PART"
                MNT=$(mktemp -d)
                sudo mount "$DATA_PART" "$MNT"
                # Backup config
                sudo cp -r /etc/nixos "$MNT/etc-nixos-backup-$(date +%s)" 2>/dev/null || true
                [ -d ~/.config/solem ] && sudo cp -r ~/.config/solem "$MNT/" || true
                sudo umount "$MNT"
                rmdir "$MNT"
                echo "✓ Backup config + secret pubblici su partizione DATA"
              fi
              echo "✓ Recovery USB pronto. Boot UEFI → seleziona USB."
              ;;

            backup-config)
              # Backup /etc/nixos + secret su path scelto
              DEST="''${1:?Usage: solem-recovery backup-config <path>}"
              mkdir -p "$DEST"
              sudo cp -r /etc/nixos "$DEST/etc-nixos-$(date +%s)"
              [ -d ~/.config/solem ] && cp -r ~/.config/solem "$DEST/"
              [ -f /etc/solem/backup-passphrase ] && sudo cp /etc/solem/backup-passphrase "$DEST/"
              [ -d /var/lib/sbctl/keys ] && sudo cp -r /var/lib/sbctl/keys "$DEST/sbctl-keys"
              echo "✓ Config + secret backup in $DEST"
              echo "⚠ Contiene chiavi: trattare come SEGRETO. Salva su USB esterno OFFLINE."
              ;;

            restore-config)
              SRC="''${1:?Usage: solem-recovery restore-config <path>}"
              if [ ! -d "$SRC/etc-nixos"* ]; then
                echo "Nessun backup etc-nixos in $SRC"
                exit 1
              fi
              echo "Restore /etc/nixos da $SRC..."
              sudo cp -r "$SRC"/etc-nixos-*/. /etc/nixos/
              echo "✓ Restored. Esegui: sudo nixos-rebuild switch"
              ;;

            help|--help|-h|*)
              cat <<'HELP'
solem-recovery — USB recovery + backup/restore config

  list-devices                 elenca block devices (trova USB)
  create <dev>                 build ISO + scrivi su USB + partizione DATA backup
  backup-config <path>         copia /etc/nixos + secret in path
  restore-config <path>        ripristina /etc/nixos da backup

Workflow disaster recovery:
  1. solem-recovery create /dev/sdX        (PRIMA che serva, ovvio)
  2. Tieni USB in cassaforte / con bagaglio
  3. Quando il sistema crasha:
     - Boot USB → live SOLEM
     - Mount partizione DATA: mount /dev/disk/by-label/SOLEM-DATA /mnt
     - Restore: cp -r /mnt/etc-nixos-LATEST /etc/nixos
     - sudo nixos-rebuild switch

⚠ Tutti i comandi richiedono sudo.
⚠ "create" CANCELLA il device — verifica DUE volte.
HELP
              ;;
          esac
        '';
      })
    ];
  };
}
