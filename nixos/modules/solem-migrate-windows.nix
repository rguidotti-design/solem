{ config, pkgs, lib, ... }:

# SOLEM MIGRATE WINDOWS — wizard zero-config per portare dati da PC Windows.
#
# Single responsibility: SOLO CLI `solem-migrate-windows <path>` che:
# - Monta partizione NTFS Windows (read-only per sicurezza)
# - Scopre struttura standard (Users/<name>/Documents, Pictures, Desktop, etc.)
# - Copia con rsync in $HOME mantenendo timestamp
# - Importa browser data (Firefox/Chrome bookmarks)
# - Skip cartelle di sistema (AppData/Roaming è grosso, ProgramFiles non serve)

let
  cfg = config.solem.migrateWindows;

  migrateCli = pkgs.writeShellApplication {
    name = "solem-migrate-windows";
    runtimeInputs = with pkgs; [ coreutils util-linux ntfs3g rsync ];
    text = ''
      ACTION="''${1:-help}"
      shift || true

      MOUNTPOINT="/mnt/windows-migrate"

      case "$ACTION" in

        # ── Lista partizioni NTFS disponibili ─────────────────────────
        list|ls)
          echo "Partizioni NTFS disponibili:"
          lsblk -f 2>/dev/null | grep -E "ntfs|TYPE" || echo "(no NTFS detected)"
          echo
          echo "Oppure inserisci un disco esterno NTFS USB e ripeti."
          ;;

        # ── Mount partizione Windows ──────────────────────────────────
        mount)
          DEV="''${1:?Usage: solem-migrate-windows mount /dev/sdX1}"
          sudo mkdir -p "$MOUNTPOINT"
          if mountpoint -q "$MOUNTPOINT"; then
            echo "Già montato su $MOUNTPOINT"
          else
            sudo mount -t ntfs3 -o ro "$DEV" "$MOUNTPOINT" || \
              sudo mount -t ntfs -o ro "$DEV" "$MOUNTPOINT"
            echo "Montato $DEV su $MOUNTPOINT (read-only)"
          fi
          # Lista Users
          ls -la "$MOUNTPOINT/Users" 2>/dev/null | head -10
          ;;

        # ── Scoperta utente Windows ───────────────────────────────────
        users)
          if ! mountpoint -q "$MOUNTPOINT"; then
            echo "ERRORE: monta prima con: solem-migrate-windows mount /dev/sdX1"
            exit 1
          fi
          echo "Utenti Windows trovati su $MOUNTPOINT/Users:"
          ls -1 "$MOUNTPOINT/Users" 2>/dev/null | grep -vE "^(Default|Public|All Users|Default User|desktop.ini)" || true
          ;;

        # ── Migrazione automatica ─────────────────────────────────────
        migrate|go)
          WINUSER="''${1:?Usage: solem-migrate-windows migrate <windows-username>}"
          if ! mountpoint -q "$MOUNTPOINT"; then
            echo "ERRORE: monta prima con: solem-migrate-windows mount /dev/sdX1"
            exit 1
          fi
          SRC="$MOUNTPOINT/Users/$WINUSER"
          if [ ! -d "$SRC" ]; then
            echo "ERRORE: $SRC non trovato. Lista users:"
            solem-migrate-windows users
            exit 1
          fi
          DST="$HOME/From-Windows-$(date +%Y%m%d)"
          mkdir -p "$DST"
          echo "Migrazione da: $SRC"
          echo "Destinazione:  $DST"
          echo

          # Cartelle utente standard
          for folder in Documents Desktop Downloads Pictures Videos Music Contacts Favorites; do
            if [ -d "$SRC/$folder" ]; then
              echo "→ Copio $folder..."
              rsync -ah --progress --info=progress2 \
                "$SRC/$folder/" "$DST/$folder/" 2>&1 | tail -3
            fi
          done

          # Firefox profiles (bookmarks, history)
          if [ -d "$SRC/AppData/Roaming/Mozilla/Firefox/Profiles" ]; then
            echo "→ Copio Firefox profile..."
            mkdir -p "$DST/firefox-windows"
            cp -r "$SRC/AppData/Roaming/Mozilla/Firefox/Profiles"/* "$DST/firefox-windows/" 2>/dev/null || true
            echo "  Profile Firefox in $DST/firefox-windows/"
            echo "  Per importare: copia in ~/.mozilla/firefox/"
          fi

          # Chrome bookmarks
          if [ -d "$SRC/AppData/Local/Google/Chrome/User Data/Default" ]; then
            echo "→ Copio Chrome bookmarks..."
            mkdir -p "$DST/chrome-windows"
            cp "$SRC/AppData/Local/Google/Chrome/User Data/Default/Bookmarks" "$DST/chrome-windows/" 2>/dev/null || true
          fi

          # Riepilogo
          echo
          echo "── Migrazione completata ──"
          du -sh "$DST" 2>/dev/null
          echo "Dati in: $DST"
          echo
          echo "Prossimi step:"
          echo "  - Sposta Documents/Pictures/etc da $DST a $HOME come preferisci"
          echo "  - Importa Firefox profile in ~/.mozilla/firefox/"
          echo "  - Per smontare Windows: solem-migrate-windows umount"
          ;;

        # ── Smonta ────────────────────────────────────────────────────
        umount|unmount)
          if mountpoint -q "$MOUNTPOINT"; then
            sudo umount "$MOUNTPOINT"
            echo "Smontato $MOUNTPOINT"
          else
            echo "$MOUNTPOINT non era montato"
          fi
          ;;

        # ── HELP ─────────────────────────────────────────────────────
        help|--help|-h|*)
          cat <<'HELP'
solem-migrate-windows — wizard migrazione da PC Windows

  1. Connetti il disco Windows (USB esterno o partizione interna)
  2. solem-migrate-windows list           lista partizioni NTFS disponibili
  3. solem-migrate-windows mount /dev/sdX1   monta read-only
  4. solem-migrate-windows users          vedi utenti Windows trovati
  5. solem-migrate-windows migrate ruben  copia Documents/Pictures/etc

Cartelle copiate:
  Documents, Desktop, Downloads, Pictures, Videos, Music,
  Contacts, Favorites
  + Firefox profile (bookmarks/history)
  + Chrome bookmarks

NON copiate (per sicurezza/privacy):
  AppData (cache app, no utile)
  ProgramFiles (app Windows, useless su Linux)
  System32 (system)

Destinazione: ~/From-Windows-<data>/
Read-only mount: il tuo Windows non viene modificato.

ESEMPIO:
  solem-migrate-windows mount /dev/sdb3
  solem-migrate-windows migrate ruben
  solem-migrate-windows umount
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.migrateWindows = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa `solem-migrate-windows` wizard NTFS rsync";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ migrateCli ];

    # NTFS3 kernel module (built-in 24.11, no extra pkg)
    boot.supportedFilesystems = [ "ntfs" ];
  };
}
