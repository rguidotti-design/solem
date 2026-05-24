{ config, pkgs, lib, ... }:

# SOLEM FAMILY GUI — interfaccia grafica per family sharing.
#
# Single responsibility: SOLO CLI `solem-family-gui` wrapper grafico
# del modulo solem-family-sharing. Usa zenity/yad per GUI dialog su
# operazioni famiglia (add/remove user, parental control, ecc.).

let
  cfg = config.solem.familyGui;

  familyGuiCli = pkgs.writeShellApplication {
    name = "solem-family-gui";
    runtimeInputs = with pkgs; [ coreutils zenity ];
    text = ''
      ACTION=$(zenity --list \
        --title="SOLEM Family" \
        --column="Azione" --column="Descrizione" \
        "members" "Lista membri famiglia" \
        "add" "Aggiungi nuovo membro" \
        "remove" "Rimuovi membro" \
        "kid-mode-on" "Attiva DNS family-safe (parental control)" \
        "kid-mode-off" "Disattiva DNS family-safe" \
        "shared-folder" "Apri cartella condivisa" \
        "screen-time" "Vedi screen-time membri" \
        --height=350 --width=500)

      case "$ACTION" in
        members)
          MEMBERS=$(getent group solem-family | awk -F: '{print $4}' | tr ',' '\n')
          zenity --info --text="Membri famiglia:\n\n$MEMBERS" --title="SOLEM Family"
          ;;
        add)
          USER=$(zenity --entry --title="Aggiungi membro" --text="Username:")
          if [ -n "$USER" ]; then
            if command -v solem-family >/dev/null 2>&1; then
              pkexec solem-family add "$USER"
              zenity --info --text="Membro $USER aggiunto!"
            else
              zenity --error --text="solem-family CLI non disponibile"
            fi
          fi
          ;;
        remove)
          USER=$(zenity --entry --title="Rimuovi membro" --text="Username:")
          if [ -n "$USER" ]; then
            pkexec solem-family remove "$USER" && zenity --info --text="Rimosso $USER"
          fi
          ;;
        kid-mode-on)
          if pkexec solem-family kid-mode on; then
            zenity --info --text="DNS family-safe attivo\n(Cloudflare 1.1.1.3 / Quad9 9.9.9.11)"
          fi
          ;;
        kid-mode-off)
          if pkexec solem-family kid-mode off; then
            zenity --info --text="DNS family-safe disattivato"
          fi
          ;;
        shared-folder)
          xdg-open /srv/family/ &
          ;;
        screen-time)
          USER=$(zenity --entry --title="Screen time" --text="Username (vuoto = tu):")
          OUT=$(solem-family screen-time "''${USER:-$USER}" 2>&1)
          zenity --info --text="$OUT" --title="Screen time"
          ;;
      esac
    '';
  };
in {
  options.solem.familyGui = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Installa `solem-family-gui` GUI per family sharing (zenity dialogs)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      familyGuiCli
      zenity
    ];
  };
}
