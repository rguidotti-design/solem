{ config, pkgs, lib, ... }:

# SOLEM CLIPBOARD SHARE — copy/paste cross-device via HTTP (LAN).
#
# Single responsibility: SOLO CLI `solem-clip` per share rapido contenuto
# clipboard via HTTP plain (porta locale, solo LAN).
#
# Niente daemon, niente sync background. Pull/push esplicito on-demand.

let
  cfg = config.solem.clipboardShare;

  clipCli = pkgs.writeShellApplication {
    name = "solem-clip";
    runtimeInputs = with pkgs; [ coreutils curl python3 ];
    text = ''
      ACTION="''${1:-help}"
      shift || true

      STATE="$HOME/.cache/solem-clip"
      mkdir -p "$STATE"
      LAST_FILE="$STATE/last.txt"
      PORT="''${SOLEM_CLIP_PORT:-9990}"

      case "$ACTION" in

        # ── Salva contenuto in clipboard share ────────────────────────
        push|set)
          if [ $# -gt 0 ]; then
            echo "$*" > "$LAST_FILE"
          else
            # Da stdin
            cat > "$LAST_FILE"
          fi
          BYTES=$(stat -c %s "$LAST_FILE" 2>/dev/null || wc -c < "$LAST_FILE")
          echo "Salvati $BYTES bytes in clipboard share"
          ;;

        # ── Leggi contenuto ──────────────────────────────────────────
        pull|get|cat)
          if [ -f "$LAST_FILE" ]; then
            cat "$LAST_FILE"
          else
            echo "(clipboard share vuota)" >&2
          fi
          ;;

        # ── Avvia mini-server HTTP per ricevere da peer ──────────────
        serve)
          echo "Server HTTP clipboard share su :$PORT"
          echo "Push da peer: curl -X POST http://$HOSTNAME:$PORT/ --data 'testo'"
          echo "Pull da peer: curl http://$HOSTNAME:$PORT/"
          exec python3 -c "
import http.server, os
LAST = '$LAST_FILE'
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            with open(LAST) as f:
                data = f.read()
            self.send_response(200); self.send_header('Content-Type','text/plain; charset=utf-8'); self.end_headers()
            self.wfile.write(data.encode('utf-8'))
        except FileNotFoundError:
            self.send_response(404); self.end_headers()
    def do_POST(self):
        length = int(self.headers.get('Content-Length',0))
        data = self.rfile.read(length).decode('utf-8', errors='ignore')
        with open(LAST, 'w') as f:
            f.write(data)
        self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers()
        self.wfile.write(b'{\"ok\":true}')
    def log_message(self, *args): pass
http.server.HTTPServer(('0.0.0.0', $PORT), H).serve_forever()
"
          ;;

        # ── Push a un peer HTTP ───────────────────────────────────────
        send)
          PEER="''${1:?Usage: solem-clip send <peer-host> [text]}"
          shift || true
          if [ $# -gt 0 ]; then
            DATA="$*"
          else
            DATA=$(cat)
          fi
          curl -sS -X POST "http://$PEER:$PORT/" --data-raw "$DATA" --max-time 5
          echo
          ;;

        # ── Pull da un peer HTTP ──────────────────────────────────────
        fetch)
          PEER="''${1:?Usage: solem-clip fetch <peer-host>}"
          curl -sS "http://$PEER:$PORT/" --max-time 5
          ;;

        # ── HELP ─────────────────────────────────────────────────────
        help|--help|-h|*)
          cat <<'HELP'
solem-clip — clipboard share LAN (HTTP semplice)

  Locale:
    solem-clip push "testo"             salva in cache
    solem-clip push < file.txt          salva da file
    solem-clip pull                     stampa contenuto

  Server (riceve da peer):
    solem-clip serve                    HTTP :9990

  Client (verso peer):
    solem-clip send peer-host "hello"   POST a peer
    solem-clip fetch peer-host          GET da peer

ENV: SOLEM_CLIP_PORT=9990
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.clipboardShare = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa `solem-clip` CLI per share clipboard via HTTP LAN";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ clipCli ];
  };
}
