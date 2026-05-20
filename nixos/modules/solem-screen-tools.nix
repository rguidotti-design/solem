{ config, pkgs, lib, ... }:

# SOLEM SCREEN TOOLS — screenshot + screen recorder (Wayland-first).
#
# Single responsibility: SOLO installare binari + helper script. Keybind
# è gestita nel desktop module.
#
# Tools:
#   - grim       → screenshot Wayland (output PNG)
#   - slurp      → selezione regione (geometry picker)
#   - wf-recorder → screen recorder Wayland
#   - swappy     → annotation overlay
#   - satty      → screenshot annotator moderno (alternativa)
#
# Helper: solem-shot (selezione → save in ~/Pictures/solem/ + notifica).
# 100% FOSS, 0 €.

let
  cfg = config.solem.screenTools;

  solemShot = pkgs.writeShellApplication {
    name = "solem-shot";
    runtimeInputs = with pkgs; [ grim slurp wl-clipboard libnotify coreutils ];
    text = ''
      MODE="''${1:-region}"
      OUTDIR="$HOME/Pictures/solem"
      mkdir -p "$OUTDIR"
      OUTFILE="$OUTDIR/shot-$(date +%Y%m%d-%H%M%S).png"

      case "$MODE" in
        region)
          REGION=$(slurp) || exit 1
          grim -g "$REGION" "$OUTFILE"
          ;;
        full)
          grim "$OUTFILE"
          ;;
        window)
          REGION=$(slurp -d) || exit 1
          grim -g "$REGION" "$OUTFILE"
          ;;
        *)
          echo "Usage: solem-shot [region|full|window]"
          exit 1
          ;;
      esac

      wl-copy < "$OUTFILE"
      notify-send -i "$OUTFILE" "SOLEM Screenshot" "Salvato: $OUTFILE (copiato in clipboard)"
      echo "$OUTFILE"
    '';
  };

  solemRecord = pkgs.writeShellApplication {
    name = "solem-record";
    runtimeInputs = with pkgs; [ wf-recorder slurp libnotify coreutils ];
    text = ''
      OUTDIR="$HOME/Videos/solem"
      mkdir -p "$OUTDIR"
      OUTFILE="$OUTDIR/rec-$(date +%Y%m%d-%H%M%S).mp4"

      MODE="''${1:-region}"
      if [ "$MODE" = "region" ]; then
        REGION=$(slurp) || exit 1
        notify-send "SOLEM Record" "Recording avviato. Ctrl+C per fermare."
        wf-recorder -g "$REGION" -f "$OUTFILE" -c libx264 -p preset=veryfast
      else
        notify-send "SOLEM Record" "Recording full-screen. Ctrl+C per fermare."
        wf-recorder -f "$OUTFILE" -c libx264 -p preset=veryfast
      fi

      notify-send "SOLEM Record" "Salvato: $OUTFILE"
    '';
  };
in {
  options.solem.screenTools = {
    enable = lib.mkEnableOption "Screenshot + screen recorder (grim/slurp/wf-recorder)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      grim slurp wl-clipboard
      wf-recorder
      swappy
      satty
      solemShot
      solemRecord
    ];
  };
}
