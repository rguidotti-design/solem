{ config, pkgs, lib, ... }:

# SOLEM MIGRATION ASSISTANT — wizard import dati da altre distro Linux.
#
# Single responsibility: SOLO installare lo script `solem-migrate` che
# legge i dati utente da Ubuntu/Fedora/Arch/Debian existing install e
# li importa in SOLEM (home dir, dotfile, app, configurazioni network).
#
# Modi:
#   - Live: hai SOLEM su USB live + disco vecchio montato → import
#   - Dual boot: bootta in SOLEM, monta partizione vecchia, import
#   - Remote: scp dei dati da PC vecchio → import
#
# NON sostituisce un install; è il "porta-i-tuoi-dati-da-Ubuntu" step.

let
  cfg = config.solem.migration;

  migrationScript = pkgs.writeShellApplication {
    name = "solem-migrate";
    runtimeInputs = with pkgs; [ rsync coreutils gawk gnused jq curl ];
    text = ''
      ACTION="''${1:-help}"

      case "$ACTION" in
        detect)
          # Rileva distro montata
          shift
          SRC="''${1:-/mnt/old}"
          if [ ! -d "$SRC" ]; then
            echo "Monta prima la partizione: mount /dev/sdX1 /mnt/old"
            exit 1
          fi
          if [ -f "$SRC/etc/os-release" ]; then
            grep -E '^(NAME|VERSION)=' "$SRC/etc/os-release"
          fi
          ;;

        home)
          # Copia /home utente dalla source
          shift
          SRC="''${1:-/mnt/old/home}"
          USER="''${2:-gavio}"
          if [ ! -d "$SRC" ]; then
            echo "Source $SRC non esiste"; exit 1
          fi
          echo "Copio $SRC → /home (può richiedere ore)..."
          rsync -aHAX --info=progress2 --exclude='.cache' --exclude='.local/share/Trash' \
                "$SRC/" "/home/"
          chown -R "$USER:users" "/home/$USER" 2>/dev/null || true
          ;;

        dotfiles)
          # Solo dotfiles essenziali
          shift
          SRC="''${1:-/mnt/old/home}"
          USER="''${2:-gavio}"
          DOTS=(.bashrc .zshrc .profile .gitconfig .vimrc .config/git .config/nvim .ssh/config)
          for d in "''${DOTS[@]}"; do
            if [ -e "$SRC/$USER/$d" ]; then
              echo "→ $d"
              ${pkgs.coreutils}/bin/cp -r "$SRC/$USER/$d" "/home/$USER/$d" 2>/dev/null || true
            fi
          done
          chown -R "$USER:users" "/home/$USER"
          echo "Dotfiles importati"
          ;;

        packages)
          # Lista pacchetti dell'install vecchio (mappabile a Flatpak/Nix)
          shift
          SRC="''${1:-/mnt/old}"
          if [ -f "$SRC/var/lib/dpkg/status" ]; then
            echo "── Pacchetti Debian/Ubuntu ──"
            ${pkgs.coreutils}/bin/grep -A 1 "^Package:" "$SRC/var/lib/dpkg/status" | \
              ${pkgs.coreutils}/bin/grep -E "^Status: install ok installed" -B 1 | \
              ${pkgs.coreutils}/bin/grep "^Package:" | awk '{print $2}' | head -100
          elif [ -d "$SRC/var/lib/rpm" ]; then
            echo "── Pacchetti Fedora/RHEL (no chroot, info parziale) ──"
            ls "$SRC/usr/bin" | head -50
          elif [ -f "$SRC/var/lib/pacman/local" ]; then
            echo "── Pacchetti Arch (no chroot) ──"
            ls "$SRC/var/lib/pacman/local/" | sed 's/-[0-9].*//' | head -50
          fi
          echo
          echo "Mappa equivalenti SOLEM: vedi docs/MIGRATION-PACKAGES.md"
          ;;

        wifi)
          # Estrai connessioni WiFi salvate (NetworkManager)
          shift
          SRC="''${1:-/mnt/old}"
          if [ -d "$SRC/etc/NetworkManager/system-connections" ]; then
            echo "Copio connessioni WiFi NetworkManager..."
            sudo cp -r "$SRC/etc/NetworkManager/system-connections/"* \
                       "/etc/NetworkManager/system-connections/" 2>/dev/null || true
            sudo chmod 600 /etc/NetworkManager/system-connections/* 2>/dev/null || true
            sudo systemctl restart NetworkManager
            echo "Riavvia NetworkManager: fatto"
          fi
          ;;

        bundle)
          # Crea bundle compresso esportabile da vecchio sistema
          shift
          DEST="''${1:-/tmp/solem-migration-bundle.tar.gz}"
          echo "Creo bundle da $HOME (può richiedere minuti)..."
          ${pkgs.gnutar}/bin/tar -czf "$DEST" \
              -C "$HOME" \
              --exclude='.cache' --exclude='.local/share/Trash' \
              .bashrc .zshrc .profile .gitconfig 2>/dev/null \
              Documents Music Pictures Videos Downloads 2>/dev/null || true
          echo "Bundle: $DEST"
          echo "Trasferisci su SOLEM con: scp $DEST gavio@solem.local:/tmp/"
          echo "Poi su SOLEM: solem-migrate restore /tmp/solem-migration-bundle.tar.gz"
          ;;

        restore)
          shift
          BUNDLE="''${1:?Usage: solem-migrate restore <path-to-bundle.tar.gz>}"
          if [ ! -f "$BUNDLE" ]; then
            echo "Bundle $BUNDLE non trovato"; exit 1
          fi
          echo "Estraggo $BUNDLE in $HOME..."
          ${pkgs.gnutar}/bin/tar -xzf "$BUNDLE" -C "$HOME"
          echo "Restore completato"
          ;;

        *)
          echo "solem-migrate — migra dati da altra distro Linux"
          echo
          echo "Sul VECCHIO sistema:"
          echo "  solem-migrate bundle [path]      crea tar.gz home"
          echo
          echo "Sul NUOVO sistema SOLEM:"
          echo "  solem-migrate detect /mnt/old    rileva distro source"
          echo "  solem-migrate home /mnt/old/home gavio   copia /home"
          echo "  solem-migrate dotfiles /mnt/old/home gavio"
          echo "  solem-migrate packages /mnt/old              lista pkg"
          echo "  solem-migrate wifi /mnt/old                  importa WiFi"
          echo "  solem-migrate restore /tmp/bundle.tar.gz"
          ;;
      esac
    '';
  };
in {
  options.solem.migration = {
    enable = lib.mkEnableOption "Migration assistant per import da Ubuntu/Fedora/Arch";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      migrationScript rsync
    ];
  };
}
