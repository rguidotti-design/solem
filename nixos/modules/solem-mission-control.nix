{ config, pkgs, lib, ... }:

# SOLEM MISSION CONTROL — overview workspace stile macOS Mission Control.
#
# Single responsibility: SOLO CLI `solem-overview` + bind Hyprland che:
# - Mostra anteprima di tutte le finestre attive (grim screenshot)
# - Picker fzf/wofi per saltare a finestra
# - Bind Super+Tab style
#
# Tool FOSS: hyprctl + grim + slurp + jq.

let
  cfg = config.solem.missionControl;

  overviewCli = pkgs.writeShellApplication {
    name = "solem-overview";
    runtimeInputs = with pkgs; [ coreutils jq grim slurp fzf wofi ];
    text = ''
      MODE="''${1:-list}"

      case "$MODE" in
        list|l)
          # Lista finestre attive
          hyprctl clients -j 2>/dev/null | \
            jq -r '.[] | "\(.workspace.id) | \(.class) | \(.title)"' | sort -u
          ;;

        switch|s)
          # Picker wofi per cambio finestra
          PICK=$(hyprctl clients -j 2>/dev/null | \
            jq -r '.[] | "\(.address) \(.workspace.id) \(.class) — \(.title)"' | \
            wofi --dmenu --prompt "Switch to:")
          if [ -n "$PICK" ]; then
            ADDR=$(echo "$PICK" | awk '{print $1}')
            hyprctl dispatch focuswindow "address:$ADDR"
          fi
          ;;

        switch-fzf|f)
          # Picker fzf in terminale
          PICK=$(hyprctl clients -j 2>/dev/null | \
            jq -r '.[] | "\(.address) \(.workspace.id) \(.class) — \(.title)"' | \
            fzf --prompt "Switch> ")
          if [ -n "$PICK" ]; then
            ADDR=$(echo "$PICK" | awk '{print $1}')
            hyprctl dispatch focuswindow "address:$ADDR"
          fi
          ;;

        workspace|w)
          # Lista workspace + finestre per ognuno
          hyprctl workspaces -j 2>/dev/null | jq -r '.[] | "Workspace \(.id): \(.windows) finestre"'
          ;;

        screenshot|ss)
          # Screenshot di tutti monitor
          OUT="$HOME/Pictures/solem-overview-$(date +%Y%m%d-%H%M%S).png"
          mkdir -p "$(dirname "$OUT")"
          grim "$OUT"
          echo "Screenshot: $OUT"
          ;;

        help|--help|-h|*)
          cat <<'HELP'
solem-overview — Mission Control workspace + finestre

  list / l           lista finestre attive (workspace|class|title)
  switch / s         picker wofi (GUI) per saltare a finestra
  switch-fzf / f     picker fzf (terminale)
  workspace / w      lista workspace + count finestre
  screenshot / ss    grab tutti monitor in ~/Pictures/

Bind Hyprland suggerito:
  bind = SUPER, Tab, exec, solem-overview switch
  bind = SUPER, grave, exec, solem-overview switch
  bind = SUPER ALT, Tab, exec, solem-overview workspace
HELP
          ;;
      esac
    '';
  };

  hyprBinds = pkgs.writeText "solem-mission-control.conf" ''
    # ── SOLEM Mission Control bind Hyprland ────────────────────────
    bind = SUPER, Tab,       exec, solem-overview switch
    bind = SUPER, grave,     exec, solem-overview switch
    bind = SUPER ALT, Tab,   exec, solem-overview workspace
    bind = SUPER ALT, S,     exec, solem-overview screenshot
  '';
in {
  options.solem.missionControl = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa `solem-overview` + bind Hyprland Mission Control-like";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ overviewCli ];
    environment.etc."xdg/solem/hypr-mission-control.conf".source = hyprBinds;
  };
}
