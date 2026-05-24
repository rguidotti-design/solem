{ config, pkgs, lib, ... }:

# SOLEM DAVINCI — helper installazione DaVinci Resolve (free).
#
# DaVinci Resolve è gratis (Studio è $295 ma free version professional).
# Linux build ufficiale Blackmagic. NixOS può eseguirla via runtime
# environment + FHS.
#
# Single responsibility: SOLO CLI helper `solem-davinci` che:
#   1. Scarica DaVinci Resolve free dalla pagina ufficiale (manuale)
#   2. Estrae + crea FHS env per girare su NixOS
#   3. Helper "solem-davinci run"

let
  cfg = config.solem.davinci;

  davinciCli = pkgs.writeShellApplication {
    name = "solem-davinci";
    runtimeInputs = with pkgs; [ coreutils curl unzip ];
    text = ''
      DIR="$HOME/.local/share/davinci-resolve"
      mkdir -p "$DIR"

      ACTION="''${1:-help}"

      case "$ACTION" in

        # ── Step 1: scarica manualmente da Blackmagic ─────────────────
        download|dl)
          cat <<'INFO'
DaVinci Resolve è gratis (free version, no watermark, 4K export).

Download manuale richiesto (login Blackmagic gratuito):
  https://www.blackmagicdesign.com/products/davinciresolve

Scegli "DaVinci Resolve" (NON Studio, che è a pagamento).
Versione: 'Linux 64-bit' (file ZIP ~ 3 GB).

Una volta scaricato:
  solem-davinci install ~/Downloads/DaVinci_Resolve_*.zip
INFO
          ;;

        # ── Step 2: installa da ZIP scaricato ─────────────────────────
        install)
          ZIP="''${2:?Usage: solem-davinci install <path-to-zip>}"
          if [ ! -f "$ZIP" ]; then
            echo "File non trovato: $ZIP"
            exit 1
          fi
          echo "Estraggo $ZIP in $DIR..."
          unzip -q "$ZIP" -d "$DIR"
          INSTALLER=$(find "$DIR" -name "DaVinci_Resolve*.run" | head -1)
          if [ -z "$INSTALLER" ]; then
            echo "ERRORE: installer .run non trovato in zip"
            exit 1
          fi
          echo "Installer trovato: $INSTALLER"
          echo
          cat <<HINT
Per eseguire l'installer NixOS richiede un FHS env. Comando suggerito:

  cd $DIR
  nix-shell -p steam-run --command "steam-run $INSTALLER"

Oppure usa il flake DaVinci-on-Nix (FOSS community):
  https://github.com/jshholland/davinci-resolve-checked

Dopo install, lancia con:
  solem-davinci run
HINT
          ;;

        # ── Step 3: run via steam-run FHS ─────────────────────────────
        run)
          if command -v resolve >/dev/null 2>&1; then
            resolve "$@"
          elif [ -f /opt/resolve/bin/resolve ]; then
            nix-shell -p steam-run --command "steam-run /opt/resolve/bin/resolve"
          else
            echo "DaVinci Resolve non installato."
            echo "Installa: solem-davinci download → solem-davinci install <zip>"
          fi
          ;;

        # ── HELP ─────────────────────────────────────────────────────
        help|--help|-h|*)
          cat <<'HELP'
solem-davinci — helper DaVinci Resolve (free, FOSS-friendly install)

  1. solem-davinci download              istruzioni download Blackmagic
  2. solem-davinci install <zip>         estrai + setup FHS
  3. solem-davinci run                   lancia tramite steam-run

DaVinci Resolve free = professionale, no watermark, 4K export.
$0 € (Studio Pro a $295 OPZIONALE).

Vantaggi vs Adobe Premiere Pro:
  - Stesso target professional video editing
  - Free version pari a Premiere per editing base
  - Linux build ufficiale Blackmagic
  - Color grading best-in-class (lineage Resolve)
  - Render Vulkan (NVIDIA/AMD/Intel via Mesa)

Alt FOSS pure:
  - Kdenlive (FOSS, non-linear editor)
  - Shotcut (FOSS, cross-platform)
  - OpenShot (FOSS, semplice)
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.davinci = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa `solem-davinci` helper per DaVinci Resolve free";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ davinciCli ];
  };
}
