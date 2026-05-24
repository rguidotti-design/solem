{ config, pkgs, lib, ... }:

# SOLEM TRIAL MODE — boot live "prova SOLEM senza installare".
#
# Single responsibility: SOLO segnalare al sistema che siamo in modalità
# trial (non install) + offrire pratici "Save state to USB" se l'utente
# vuole persistenza temporanea.

let
  cfg = config.solem.trialMode;

  trialCli = pkgs.writeShellApplication {
    name = "solem-trial";
    runtimeInputs = with pkgs; [ coreutils util-linux rsync ];
    text = ''
      ACTION="''${1:-status}"
      case "$ACTION" in
        status)
          if [ -f /etc/solem/trial-mode ]; then
            echo "Sei in TRIAL MODE — nessuna persistenza."
            echo "I cambiamenti saranno persi al riavvio."
            echo ""
            echo "Comandi:"
            echo "  solem-trial save-to-usb /dev/sdX     persiste home su USB"
            echo "  solem-trial install                  esci da trial → installer"
          else
            echo "Non in trial mode (sistema installato)."
          fi
          ;;
        install)
          if command -v solem-installer >/dev/null 2>&1; then
            exec solem-installer
          elif command -v calamares >/dev/null 2>&1; then
            exec sudo calamares
          else
            echo "Installer non disponibile in questa ISO."
          fi
          ;;
        save-to-usb)
          USB="''${2:?Usage: solem-trial save-to-usb /dev/sdX}"
          echo "ATTENZIONE: $USB sarà formattato come ext4 e popolato con la tua home."
          read -r -p "Digita YES per confermare: " ans
          [[ "$ans" == "YES" ]] || { echo "Annullato"; exit 1; }
          sudo mkfs.ext4 -L SOLEM-TRIAL "$USB"
          sudo mkdir -p /mnt/trial
          sudo mount "$USB" /mnt/trial
          rsync -avh "$HOME/" /mnt/trial/home/
          sudo umount /mnt/trial
          echo "Home salvata su $USB (label SOLEM-TRIAL)."
          echo "Al prossimo boot live, monta /dev/disk/by-label/SOLEM-TRIAL su ~/"
          ;;
        *)
          echo "solem-trial — modalità prova"
          echo "  solem-trial status         vede se sei in trial"
          echo "  solem-trial save-to-usb    persiste home su USB esterno"
          echo "  solem-trial install        esci da trial → installer"
          ;;
      esac
    '';
  };
in {
  options.solem.trialMode = {
    enable = lib.mkEnableOption "Modalità trial (boot live senza install)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ trialCli ];
    environment.etc."solem/trial-mode".text = "1\n";

    # Banner di benvenuto in modalità trial
    environment.etc."issue".text = ''
      ╔════════════════════════════════════════════════════╗
      ║          SOLEM — TRIAL MODE (live, no install)     ║
      ║                                                    ║
      ║  Nessun cambiamento è permanente.                  ║
      ║  Per installare: `solem-trial install`             ║
      ║  Per persistere su USB: `solem-trial save-to-usb`  ║
      ╚════════════════════════════════════════════════════╝
    '';
  };
}
