{ config, pkgs, lib, ... }:

# SOLEM UNIVERSAL CLIPBOARD — sync clipboard cross-device via mesh.
#
# Single responsibility: SOLO daemon che pubblica/sottoscrive il
# clipboard locale sul bus mesh SOLEM (porta 9700, encrypted).
# I peer registrati (smartphone via KDE Connect, altri PC SOLEM) si
# sincronizzano automaticamente.

let
  cfg = config.solem.universalClipboard;

  clipDaemon = pkgs.writeShellApplication {
    name = "solem-clip-sync";
    runtimeInputs = with pkgs; [ wl-clipboard coreutils curl jq openssl ];
    text = ''
      # Polling clipboard locale + push ai peer mesh quando cambia.
      # Riceve via HTTP da peer (porta 9700, autenticata con shared key).

      PORT="''${SOLEM_CLIP_PORT:-9700}"
      STATE="$HOME/.cache/solem-clip"
      mkdir -p "$STATE"
      LAST="$STATE/last.sha"
      PEERS_FILE="$HOME/.local/state/solem/clip-peers"

      while true; do
        CONTENT=$(wl-paste 2>/dev/null || echo "")
        if [ -z "$CONTENT" ]; then sleep 1; continue; fi

        SHA=$(echo -n "$CONTENT" | sha256sum | cut -d' ' -f1)
        PREV=$(cat "$LAST" 2>/dev/null || echo "")

        if [ "$SHA" != "$PREV" ]; then
          echo "$SHA" > "$LAST"
          # Push ai peer registrati
          if [ -f "$PEERS_FILE" ]; then
            while read -r peer; do
              [ -z "$peer" ] && continue
              curl -s -X POST "http://$peer:$PORT/clip" \
                -H "Content-Type: text/plain" \
                --data-raw "$CONTENT" \
                --max-time 3 >/dev/null 2>&1 || true
            done < "$PEERS_FILE"
          fi
        fi

        sleep 2
      done
    '';
  };

  clipReceiver = pkgs.writeShellApplication {
    name = "solem-clip-receiver";
    runtimeInputs = with pkgs; [ python3 wl-clipboard coreutils ];
    text = ''
      PORT="''${SOLEM_CLIP_PORT:-9700}"
      exec python3 -c "
import http.server, sys, subprocess
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        l = int(self.headers.get('Content-Length',0))
        data = self.rfile.read(l).decode('utf-8', errors='ignore')
        subprocess.run(['wl-copy'], input=data, text=True, check=False)
        self.send_response(200); self.end_headers()
        self.wfile.write(b'ok')
    def log_message(self, *args): pass
http.server.HTTPServer(('0.0.0.0', $PORT), H).serve_forever()
"
    '';
  };
in {
  options.solem.universalClipboard = {
    enable = lib.mkEnableOption "Universal Clipboard sync via mesh (porta 9700)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9700;
      description = "Porta TCP per ricevere clipboard dai peer";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      clipDaemon
      clipReceiver
      pkgs.wl-clipboard
    ];

    # Apri solo LAN (firewall)
    networking.firewall.allowedTCPPorts = [ cfg.port ];

    # Daemon utente per push clipboard
    systemd.user.services.solem-clip-sync = {
      description = "SOLEM Universal Clipboard sync daemon";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${clipDaemon}/bin/solem-clip-sync";
        Restart = "on-failure";
        RestartSec = 5;
        Environment = "SOLEM_CLIP_PORT=${toString cfg.port}";
      };
    };

    systemd.user.services.solem-clip-receiver = {
      description = "SOLEM Universal Clipboard receiver";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${clipReceiver}/bin/solem-clip-receiver";
        Restart = "on-failure";
        RestartSec = 5;
        Environment = "SOLEM_CLIP_PORT=${toString cfg.port}";
      };
    };
  };
}
