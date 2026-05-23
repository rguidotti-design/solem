# SOLEM — packaging GAVIO backend Python come derivation Nix.
#
# IMPORTANTE: questa è una derivation OPT-IN. Per buildarla serve il
# codice sorgente di GAVIO. La modalità default usa un placeholder che
# crea un binario "gavio-stub" che dice "GAVIO non impacchettato".
#
# Per build reale:
#   1. Clona gavio in ../gavio (sibling directory)
#   2. nix build .#gavio  (sceglie src locale)
#   3. Oppure imposta `src = builtins.fetchTarball "...";` con hash valido
#
# Single responsibility: SOLO packaging, no logic.
{ lib
, python312
, makeWrapper
, runCommand
, writeText
, writeShellScriptBin
}:

# Per la CI build di default produciamo uno "stub" che è sicuro
# (non rompe il flake) ma non fa nulla. La versione reale richiede il
# codice sorgente GAVIO disponibile localmente.
writeShellScriptBin "gavio-server" ''
  set -eu
  cat <<'BANNER'
  ┌─────────────────────────────────────────────────────────────┐
  │ GAVIO stub — server non impacchettato                       │
  │                                                             │
  │ Per usare GAVIO sul sistema SOLEM:                          │
  │  1. git clone https://github.com/rguidotti-design/gavio     │
  │  2. cd gavio && pip install -r solem_api/requirements.txt   │
  │  3. uvicorn solem_api.app:app --host 127.0.0.1 --port 8000  │
  │                                                             │
  │ Oppure modifica nix/gavio.nix con la src reale.             │
  └─────────────────────────────────────────────────────────────┘
  BANNER
  # In modalità stub, espone un health endpoint dummy se chiamato come server
  if [ "''${1:-}" = "--port" ] || [ "''${GAVIO_FORCE_STUB:-}" = "1" ]; then
    PORT="''${2:-8000}"
    echo "Avvio stub su :$PORT (risponde {\"status\":\"stub\"} su /health)"
    exec ${python312}/bin/python3 -c "
import http.server, json, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers()
            self.wfile.write(json.dumps({'status':'stub','message':'GAVIO not packaged'}).encode())
        else:
            self.send_response(404); self.end_headers()
http.server.HTTPServer(('127.0.0.1',$PORT), H).serve_forever()
"
  fi
  exit 0
''
