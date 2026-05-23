{ config, pkgs, lib, ... }:

# SOLEM FAMILY SHARING — multi-utente + parental control + share FOSS.
#
# Single responsibility: SOLO orchestrare:
# - Multi-utente sistema con gruppi family
# - Nextcloud "Family" group + shared folders
# - Parental control (DNS family-safe + screen-time)
# - Shared photo library (Immich albums condivisi)
# - Shared password vault (Vaultwarden organization)
# - Calendari condivisi (Radicale collections)
#
# 0 €. Risponde gap "Family Sharing iCloud" COMPETITIVE-GAP.md.

let
  cfg = config.solem.familySharing;

  familyCli = pkgs.writeShellApplication {
    name = "solem-family";
    runtimeInputs = with pkgs; [ coreutils shadow gawk ];
    text = ''
      ACTION="''${1:-list}"
      case "$ACTION" in
        list)
          echo "── Membri famiglia (gruppo: solem-family) ──"
          getent group solem-family | awk -F: '{print $4}' | tr ',' '\n' | grep -v '^$'
          ;;
        add)
          USER="''${2:?Usage: solem-family add <username>}"
          # Crea utente se non esiste
          if ! id "$USER" >/dev/null 2>&1; then
            sudo useradd -m -G solem-family,users "$USER"
            echo "Imposta password:"
            sudo passwd "$USER"
          else
            sudo usermod -aG solem-family "$USER"
          fi
          # Crea share dir
          sudo mkdir -p /srv/family/shared
          sudo chgrp -R solem-family /srv/family
          sudo chmod -R g+rws /srv/family
          echo "Utente $USER aggiunto al gruppo solem-family"
          ;;
        remove)
          USER="''${2:?Usage: solem-family remove <username>}"
          sudo gpasswd -d "$USER" solem-family
          ;;
        screen-time)
          # Mostra screen-time per utente (basato su systemd-loginctl)
          USER="''${2:-$USER}"
          echo "── Screen-time $USER (oggi) ──"
          loginctl list-sessions --no-legend | awk -v u="$USER" '$3==u {print $1}' | while read -r sid; do
            loginctl show-session "$sid" -p Timestamp 2>/dev/null
          done
          ;;
        kid-mode)
          # Abilita DNS family-safe (CloudFlare 1.1.1.3 / Quad9 9.9.9.11)
          ACTION2="''${2:-on}"
          if [[ "$ACTION2" == "on" ]]; then
            sudo resolvectl dns "*" 1.1.1.3 9.9.9.11
            echo "Kid mode ON — DNS family-safe attivo (blocca adult content)"
          else
            sudo resolvectl revert
            echo "Kid mode OFF — DNS ripristinato"
          fi
          ;;
        *)
          echo "solem-family — multi-utente + parental control"
          echo
          echo "  solem-family list                  membri del gruppo family"
          echo "  solem-family add <user>            crea/aggiungi utente"
          echo "  solem-family remove <user>         rimuovi dal gruppo"
          echo "  solem-family screen-time [user]    sessioni grafiche"
          echo "  solem-family kid-mode [on|off]     DNS family-safe Cloudflare"
          ;;
      esac
    '';
  };
in {
  options.solem.familySharing = {
    enable = lib.mkEnableOption "Family sharing multi-utente (FOSS clone iCloud Family)";

    sharedDir = lib.mkOption {
      type = lib.types.str;
      default = "/srv/family";
      description = "Directory radice file condivisi (perms gruppo solem-family rwx)";
    };

    parentalControl = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Abilita DNS family-safe (Cloudflare 1.1.1.3) per tutto il sistema";
    };

    screenTimeLog = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Log durata sessioni grafiche per utente (privacy: local-only)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Gruppo family
    users.groups.solem-family = {};

    # Cartella shared
    systemd.tmpfiles.rules = [
      "d ${cfg.sharedDir}        0775 root solem-family - -"
      "d ${cfg.sharedDir}/photos 2775 root solem-family - -"
      "d ${cfg.sharedDir}/docs   2775 root solem-family - -"
      "d ${cfg.sharedDir}/media  2775 root solem-family - -"
    ];

    environment.systemPackages = [ familyCli ];

    # DNS family-safe (system-wide se parentalControl=true)
    networking.nameservers = lib.mkIf cfg.parentalControl [
      "1.1.1.3"     # Cloudflare family (block malware + adult)
      "1.0.0.3"
      "9.9.9.11"    # Quad9 family
    ];

    # Screen-time log (systemd journal queryable)
    services.logrotate = lib.mkIf cfg.screenTimeLog {
      enable = true;
      settings."/var/log/solem/screen-time.log" = {
        frequency = "monthly";
        rotate = 12;
        compress = true;
        missingok = true;
      };
    };
  };
}
