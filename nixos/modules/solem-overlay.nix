{ config, pkgs, lib, ... }:

# SOLEM OVERLAY — finestra GAVIO "always-on-top" raggiungibile con Super+Space.
#
# Single responsibility: SOLO installare lo script + dichiarare le keybind
# per Hyprland. La finestra è un GTK4 webview minimale che apre
# http://127.0.0.1:9000/preview-overlay (servito da progress-server) →
# campo input + invio diretto a GAVIO via /solem/ai/route.
#
# Mimica Cmd+Space su macOS / WIN su Windows: ovunque tu sia, premi
# Super+Space e parli con GAVIO.

let
  cfg = config.solem.overlay;

  overlayScript = pkgs.writeShellApplication {
    name = "solem-overlay";
    runtimeInputs = with pkgs; [ webkitgtk_6_0 gtk4 ];
    text = ''
      # Singleton: se già aperta, focus o chiudi
      PIDFILE=/tmp/solem-overlay.pid
      if [ -f "$PIDFILE" ]; then
        PID=$(cat "$PIDFILE")
        if kill -0 "$PID" 2>/dev/null; then
          # Toggle: chiudi
          kill "$PID" 2>/dev/null || true
          rm -f "$PIDFILE"
          exit 0
        fi
      fi

      # Lancia webview minimale (fallback: chromium kiosk)
      if command -v chromium >/dev/null 2>&1; then
        chromium --app=http://127.0.0.1:9000/overlay \
          --window-size=720,520 --window-position=400,200 \
          --no-first-run --disable-translate --no-default-browser-check &
        echo $! > "$PIDFILE"
      elif command -v firefox >/dev/null 2>&1; then
        firefox --new-window http://127.0.0.1:9000/overlay &
        echo $! > "$PIDFILE"
      else
        echo "Nessun browser disponibile per overlay"
        exit 1
      fi
    '';
  };
in {
  options.solem.overlay = {
    enable = lib.mkEnableOption "Overlay GAVIO always-on-top (Super+Space)";

    hotkey = lib.mkOption {
      type = lib.types.str;
      default = "SUPER, SPACE";
      description = "Combinazione tasti Hyprland per aprire l'overlay";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ overlayScript ];

    # Hyprland bind aggiuntivo (drop-in)
    environment.etc."xdg/hypr/conf.d/solem-overlay.conf".text = ''
      # SOLEM overlay GAVIO — sempre raggiungibile
      bind = ${cfg.hotkey}, exec, solem-overlay

      # Floating + sticky + centro
      windowrule = float, ^(Chromium)$
      windowrulev2 = float, title:^(SOLEM Overlay)$
      windowrulev2 = pin, title:^(SOLEM Overlay)$
      windowrulev2 = size 720 520, title:^(SOLEM Overlay)$
      windowrulev2 = center, title:^(SOLEM Overlay)$
      windowrulev2 = noborder, title:^(SOLEM Overlay)$
    '';
  };
}
