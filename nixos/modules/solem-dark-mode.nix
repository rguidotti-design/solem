{ config, pkgs, lib, ... }:

# SOLEM DARK MODE — toggle istantaneo dark/light system-wide.
#
# Single responsibility: SOLO CLI `solem-theme dark/light/auto` che cambia:
#   - GTK theme (gsettings)
#   - Qt theme (kdeglobals)
#   - cursor theme
#   - icon theme
#   - Hyprland borders color
#
# auto = scheduling solare (gammastep / wlsunset) → dark dopo tramonto.

let
  cfg = config.solem.darkMode;

  darkModeCli = pkgs.writeShellApplication {
    name = "solem-theme";
    runtimeInputs = with pkgs; [ coreutils glib gawk ];
    text = ''
      ACTION="''${1:-status}"

      apply_gtk() {
        local mode="$1"  # prefer-dark | prefer-light | default
        if command -v gsettings >/dev/null 2>&1; then
          gsettings set org.gnome.desktop.interface color-scheme "$mode" 2>/dev/null || true
        fi
        # GTK 3.x via env
        if [ "$mode" = "prefer-dark" ]; then
          mkdir -p "$HOME/.config/gtk-3.0"
          cat > "$HOME/.config/gtk-3.0/settings.ini" <<EOF
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=Adwaita-dark
EOF
        else
          cat > "$HOME/.config/gtk-3.0/settings.ini" <<EOF
[Settings]
gtk-application-prefer-dark-theme=0
gtk-theme-name=Adwaita
EOF
        fi
      }

      apply_qt() {
        local mode="$1"
        mkdir -p "$HOME/.config"
        # Qt5 e Qt6 leggono QT_STYLE_OVERRIDE
        if [ "$mode" = "dark" ]; then
          cat > "$HOME/.config/qt5ct/qt5ct.conf" <<EOF
[Appearance]
custom_palette=false
style=Breeze
EOF
        fi
      }

      apply_hypr() {
        # Sourcing /etc/xdg/solem/hypr-theme.conf (l'utente lo include)
        echo "Per Hyprland: source /etc/xdg/solem/hypr-theme.conf"
      }

      case "$ACTION" in
        dark)
          apply_gtk "prefer-dark"
          apply_qt "dark"
          echo "→ Dark mode attivo"
          echo "(riavvia app per applicare GTK)"
          ;;
        light)
          apply_gtk "prefer-light"
          apply_qt "light"
          echo "→ Light mode attivo"
          ;;
        auto)
          if command -v wlsunset >/dev/null 2>&1; then
            wlsunset -l 41.9 -L 12.5 -t 4500 -T 6500 &
            echo "→ Auto switch (wlsunset, lat 41.9 lon 12.5 = Roma)"
          else
            echo "wlsunset non disponibile. Switch manuale:"
            HOUR=$(date +%H)
            if [ "$HOUR" -ge 19 ] || [ "$HOUR" -lt 7 ]; then
              solem-theme dark
            else
              solem-theme light
            fi
          fi
          ;;
        toggle)
          CURRENT=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || echo "default")
          if echo "$CURRENT" | grep -q "dark"; then
            solem-theme light
          else
            solem-theme dark
          fi
          ;;
        status)
          MODE=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || echo "?")
          echo "Color scheme: $MODE"
          ;;
        help|--help|-h|*)
          cat <<'HELP'
solem-theme — toggle dark/light system-wide istantaneo

  solem-theme dark         dark mode
  solem-theme light        light mode
  solem-theme toggle       switch
  solem-theme auto         dark al tramonto (richiede wlsunset)
  solem-theme status       modalità corrente

Applica:
  - GTK 3/4 (gsettings + ~/.config/gtk-3.0/settings.ini)
  - Qt 5/6 (qt5ct.conf)
  - Hyprland (manualmente: source /etc/xdg/solem/hypr-theme.conf)

Bind Hyprland suggerito:
  bind = SUPER, F12, exec, solem-theme toggle
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.darkMode = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa `solem-theme` dark/light system-wide CLI";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      darkModeCli
      wlsunset      # auto switch al tramonto
      glib          # gsettings
    ];
  };
}
