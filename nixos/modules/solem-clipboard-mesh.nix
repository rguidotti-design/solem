{ config, pkgs, lib, ... }:

# SOLEM CLIPBOARD MESH — universal clipboard auto-push (alt Apple Continuity).
#
# Single responsibility: SOLO daemon background che monitora il clipboard
# locale e push automatico ai peer SOLEM nella stessa LAN via Avahi mDNS
# discovery + HTTP simple.
#
# Equivale a Apple Universal Clipboard (Mac↔iPhone) o Microsoft Cloud
# Clipboard (Windows accounts). Versione FOSS, P2P LAN.

let
  cfg = config.solem.clipboardMesh;

  meshDaemon = pkgs.writers.writePython3 "solem-clip-mesh-daemon" {
    flakeIgnore = [ "E501" "W291" "W293" "E402" ];
  } ''
    """SOLEM clipboard mesh daemon.

    Monitora clipboard locale (via wl-paste --watch).
    Su change: push HTTP a tutti i peer Avahi-discovered solem-clip-mesh.
    """
    import hashlib
    import http.server
    import os
    import socket
    import subprocess
    import threading
    import time
    import urllib.request
    import urllib.error

    PORT = int(os.environ.get("SOLEM_CLIP_MESH_PORT", "9991"))
    PEER_FILE = os.path.expanduser("~/.local/state/solem/clip-mesh-peers")
    LAST_HASH = None
    LAST_TEXT = ""


    def get_peers():
        if not os.path.exists(PEER_FILE):
            return []
        with open(PEER_FILE) as f:
            return [l.strip() for l in f if l.strip() and not l.startswith("#")]


    def push_to_peers(text: str):
        for peer in get_peers():
            try:
                req = urllib.request.Request(
                    f"http://{peer}:{PORT}/clip",
                    data=text.encode("utf-8"),
                    method="POST",
                    headers={"Content-Type": "text/plain"},
                )
                urllib.request.urlopen(req, timeout=2)
            except (urllib.error.URLError, OSError):
                pass


    class ReceiverHandler(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            global LAST_HASH, LAST_TEXT
            if self.path == "/clip":
                length = int(self.headers.get("Content-Length", "0"))
                text = self.rfile.read(length).decode("utf-8", errors="ignore")
                # Set locale clipboard
                try:
                    subprocess.run(["wl-copy"], input=text, text=True, check=False, timeout=2)
                except (subprocess.SubprocessError, FileNotFoundError):
                    pass
                LAST_TEXT = text
                LAST_HASH = hashlib.sha256(text.encode()).hexdigest()
                self.send_response(200); self.end_headers(); self.wfile.write(b"ok")
            else:
                self.send_response(404); self.end_headers()

        def log_message(self, *args): pass


    def receiver_thread():
        http.server.HTTPServer(("0.0.0.0", PORT), ReceiverHandler).serve_forever()


    def watch_clipboard():
        global LAST_HASH
        while True:
            try:
                p = subprocess.run(["wl-paste"], capture_output=True, text=True, timeout=2)
                text = p.stdout if p.returncode == 0 else ""
            except (subprocess.SubprocessError, FileNotFoundError):
                text = ""
            if text and len(text) < 100000:  # max 100 KB
                h = hashlib.sha256(text.encode()).hexdigest()
                if h != LAST_HASH:
                    LAST_HASH = h
                    print(f"[clip-mesh] Push {len(text)} bytes to peers")
                    push_to_peers(text)
            time.sleep(2)


    if __name__ == "__main__":
        os.makedirs(os.path.dirname(PEER_FILE), exist_ok=True)
        threading.Thread(target=receiver_thread, daemon=True).start()
        watch_clipboard()
  '';

  meshCli = pkgs.writeShellApplication {
    name = "solem-clip-mesh";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      ACTION="''${1:-status}"
      PEER_FILE="$HOME/.local/state/solem/clip-mesh-peers"
      mkdir -p "$(dirname "$PEER_FILE")"

      case "$ACTION" in
        add)
          PEER="''${1:?Usage: solem-clip-mesh add <hostname-or-ip>}"
          echo "$PEER" >> "$PEER_FILE"
          echo "Aggiunto peer: $PEER"
          sort -u -o "$PEER_FILE" "$PEER_FILE"
          ;;
        list|ls)
          if [ -f "$PEER_FILE" ]; then
            echo "── Peer SOLEM clip-mesh ──"
            cat "$PEER_FILE"
          else
            echo "(nessun peer)"
          fi
          ;;
        rm)
          PEER="''${1:?Usage: solem-clip-mesh rm <peer>}"
          sed -i "/^$PEER$/d" "$PEER_FILE"
          echo "Rimosso: $PEER"
          ;;
        start)
          echo "Avvio daemon (Ctrl+C per fermare)..."
          ${meshDaemon}
          ;;
        status)
          echo "Peer file: $PEER_FILE"
          [ -f "$PEER_FILE" ] && echo "Peer: $(wc -l < "$PEER_FILE")" || echo "Peer: 0"
          PID=$(pgrep -f solem-clip-mesh-daemon || true)
          [ -n "$PID" ] && echo "Daemon attivo (PID $PID)" || echo "Daemon non attivo"
          ;;
        *)
          cat <<'HELP'
solem-clip-mesh — universal clipboard P2P LAN

  add <peer>     aggiungi peer hostname/IP
  list           vedi peer
  rm <peer>      rimuovi peer
  start          avvia daemon (push auto + receive)
  status         daemon attivo? quanti peer?

Daemon attivato come user service systemd:
  solem.clipboardMesh.enable = true; (in configuration.nix)

Equivale a Apple Universal Clipboard (Mac↔iPhone) — versione FOSS LAN.
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.clipboardMesh = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Daemon clipboard mesh auto-push P2P LAN (Apple Universal Clipboard alt)";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9991;
      description = "Porta TCP daemon clipboard mesh";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      meshCli
      pkgs.wl-clipboard
    ];

    # User service systemd
    systemd.user.services.solem-clip-mesh = {
      description = "SOLEM Clipboard Mesh daemon";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${meshDaemon}";
        Restart = "on-failure";
        RestartSec = 5;
        Environment = "SOLEM_CLIP_MESH_PORT=${toString cfg.port}";
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
