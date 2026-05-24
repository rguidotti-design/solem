# SOLEM — GAVIO stub avanzato.
#
# Single responsibility: SOLO impacchettare un mini-server Python che
# emula gli endpoint REST attesi dal sistema SOLEM, finché il GAVIO
# reale (https://github.com/rguidotti-design/gavio) non viene
# pacchettizzato come derivation Nix vera.
#
# Endpoint emulati:
#   GET  /health                 → status + uptime + version
#   GET  /v2/capabilities        → lista capability disponibili
#   POST /v2/agent/query         → echo + suggerimento
#   POST /v2/wake/trigger        → conferma wake-word
#   GET  /v2/memory/stats        → 0 memory locale (stub)
#
# Tutti rispondono "I am a stub" e suggeriscono di installare GAVIO reale.
{ lib
, python312
, writeShellApplication
, writeText
}:

let
  serverScript = writeText "gavio-stub-server.py" ''
    """SOLEM GAVIO stub server — emula endpoint REST."""
    import http.server
    import json
    import os
    import socketserver
    import time

    START_TIME = time.time()
    PORT = int(os.environ.get("GAVIO_PORT", "8000"))
    HOST = os.environ.get("GAVIO_HOST", "127.0.0.1")
    VERSION = "stub-0.1.0"


    def stub_response(extra=None):
        base = {
            "status": "stub",
            "message": "GAVIO not packaged — this is a placeholder server",
            "install_hint": "git clone https://github.com/rguidotti-design/gavio",
            "version": VERSION,
        }
        if extra:
            base.update(extra)
        return base


    class GavioHandler(http.server.BaseHTTPRequestHandler):
        def _send(self, code, payload):
            body = json.dumps(payload, indent=2).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path == "/health":
                self._send(200, {
                    "status": "stub",
                    "uptime_s": round(time.time() - START_TIME, 1),
                    "version": VERSION,
                })
            elif self.path == "/v2/capabilities":
                self._send(200, stub_response({
                    "capabilities": [],
                    "real_capabilities_when_packaged": [
                        "chat", "memory", "embed", "vector_search",
                        "calendar", "tasks", "tools", "voice", "vision",
                        "federation", "cluster", "automation"
                    ],
                }))
            elif self.path == "/v2/memory/stats":
                self._send(200, stub_response({
                    "entries": 0, "vectors": 0, "size_mb": 0,
                }))
            elif self.path == "/":
                self._send(200, stub_response({
                    "endpoints": [
                        "/health", "/v2/capabilities", "/v2/memory/stats",
                        "/v2/agent/query [POST]", "/v2/wake/trigger [POST]",
                    ],
                }))
            else:
                self._send(404, {"error": "not found", "path": self.path})

        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0"))
            try:
                body = json.loads(self.rfile.read(length).decode("utf-8")) if length else {}
            except json.JSONDecodeError:
                body = {}
            if self.path == "/v2/agent/query":
                q = body.get("query", "")
                self._send(200, stub_response({
                    "query": q,
                    "response": f"(GAVIO stub) Hai chiesto: '{q}'. Quando installerai GAVIO reale, ricevero una risposta vera.",
                }))
            elif self.path == "/v2/wake/trigger":
                self._send(200, stub_response({
                    "triggered": True,
                    "source": body.get("source", "unknown"),
                }))
            else:
                self._send(404, {"error": "not found", "path": self.path})

        def log_message(self, fmt, *args):
            pass  # silent


    def main():
        with socketserver.TCPServer((HOST, PORT), GavioHandler) as srv:
            print(f"GAVIO stub in ascolto su http://{HOST}:{PORT}")
            print(f"Endpoint: /health, /v2/capabilities, /v2/agent/query, /v2/wake/trigger")
            try:
                srv.serve_forever()
            except KeyboardInterrupt:
                print("\nGAVIO stub fermato")


    if __name__ == "__main__":
        main()
  '';
in
writeShellApplication {
  name = "gavio-server";
  runtimeInputs = [ python312 ];
  text = ''
    exec ${python312}/bin/python3 ${serverScript} "$@"
  '';
}
