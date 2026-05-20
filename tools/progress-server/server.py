"""SOLEM Progress Server — Windows-native, no WSL, no VM.

Server HTTP standalone (Python stdlib only, zero deps) che mostra lo
stato REALE del progetto SOLEM leggendo i file dal disco.

Uso:
    python tools/progress-server/server.py
    → apri browser su http://localhost:9000

Endpoint:
    GET /              dashboard HTML
    GET /api/stats     stats live JSON
    GET /api/modules   lista moduli NixOS + stato
    GET /api/layers    lista router Python backend
    GET /api/adr       lista ADR
    GET /api/docs      lista documenti
    GET /api/todo      task ancora da fare (parse questo file)
"""
from __future__ import annotations

import json
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent.parent.parent
HERE = Path(__file__).resolve().parent
PORT = 9000


def count_files(pattern: str, base: Path = ROOT) -> int:
    return len(list(base.glob(pattern)))


def list_modules() -> list[dict]:
    """Lista moduli NixOS in nixos/modules/ con info base."""
    mods_dir = ROOT / "nixos" / "modules"
    out = []
    for f in sorted(mods_dir.glob("*.nix")):
        text = f.read_text(encoding="utf-8", errors="ignore")
        # Estrai breve descrizione (prima riga commento dopo header)
        desc = ""
        for line in text.splitlines()[:30]:
            if line.strip().startswith("# ") and "─" not in line and not line.startswith("# {"):
                desc = line.strip().lstrip("# ").strip()
                if desc and len(desc) > 5:
                    break
        # Default ON/OFF
        default_on = "default = true" in text or "lib.mkOption" not in text and "mkEnableOption" not in text
        opt_in = "mkEnableOption" in text
        out.append({
            "name": f.stem,
            "size_kb": round(f.stat().st_size / 1024, 1),
            "description": desc[:120],
            "opt_in": opt_in,
            "default_on": default_on,
        })
    return out


def list_layers() -> list[dict]:
    layers_dir = ROOT / "backend" / "solem_api" / "layers"
    if not layers_dir.exists():
        return []
    out = []
    for f in sorted(layers_dir.glob("*.py")):
        if f.name == "__init__.py":
            continue
        text = f.read_text(encoding="utf-8", errors="ignore")
        # Conta endpoint via decorator
        endpoints = len(re.findall(r"@router\.(get|post|put|delete|patch)\(", text))
        # Estrai docstring iniziale
        docstring = ""
        m = re.search(r'"""(.+?)"""', text, re.DOTALL)
        if m:
            docstring = m.group(1).strip().split("\n")[0]
        out.append({
            "name": f.stem,
            "endpoints": endpoints,
            "size_kb": round(f.stat().st_size / 1024, 1),
            "description": docstring[:120],
        })
    return out


def list_adr() -> list[dict]:
    adr_dir = ROOT / "docs" / "adr"
    if not adr_dir.exists():
        return []
    out = []
    for f in sorted(adr_dir.glob("*.md")):
        text = f.read_text(encoding="utf-8", errors="ignore")
        title = ""
        for line in text.splitlines()[:10]:
            if line.startswith("# "):
                title = line.lstrip("# ").strip()
                break
        out.append({"name": f.stem, "title": title, "size_kb": round(f.stat().st_size / 1024, 1)})
    return out


def list_docs() -> list[dict]:
    out = []
    for f in sorted(ROOT.glob("*.md")):
        out.append({"name": f.name, "kb": round(f.stat().st_size / 1024, 1)})
    docs_dir = ROOT / "docs"
    if docs_dir.exists():
        for f in sorted(docs_dir.glob("*.md")):
            out.append({"name": f"docs/{f.name}", "kb": round(f.stat().st_size / 1024, 1)})
    return out


def list_tests() -> list[dict]:
    tests_dir = ROOT / "backend" / "tests"
    if not tests_dir.exists():
        return []
    out = []
    for f in sorted(tests_dir.glob("test_*.py")):
        text = f.read_text(encoding="utf-8", errors="ignore")
        test_count = len(re.findall(r"^def test_", text, re.MULTILINE))
        out.append({"name": f.stem, "tests": test_count, "size_kb": round(f.stat().st_size / 1024, 1)})
    return out


def stats() -> dict:
    git_commit = "unknown"
    try:
        import subprocess
        out = subprocess.run(
            ["git", "-C", str(ROOT), "log", "-1", "--pretty=%H"],
            capture_output=True, text=True, timeout=2,
        )
        if out.returncode == 0:
            git_commit = out.stdout.strip()[:7]
    except Exception:
        pass

    mods = list_modules()
    layers = list_layers()
    tests = list_tests()
    adr = list_adr()
    docs = list_docs()

    return {
        "project": "SOLEM",
        "version": "0.1.0-step0",
        "github": "rguidotti-design/solem",
        "git_commit": git_commit,
        "cost": "0 €",
        "nixos_modules": len(mods),
        "modules_default_on": sum(1 for m in mods if m["default_on"] and not m["opt_in"]),
        "modules_opt_in": sum(1 for m in mods if m["opt_in"]),
        "python_layers": len(layers),
        "total_endpoints": sum(l["endpoints"] for l in layers),
        "tests": sum(t["tests"] for t in tests),
        "test_files": len(tests),
        "adr": len(adr),
        "docs": len(docs),
        "cli_tools": 3,
        "ai_agents": 4,
    }


HTML = (HERE / "index.html").read_text(encoding="utf-8") if (HERE / "index.html").exists() else None


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/":
            self._send_html()
        elif path == "/api/stats":
            self._send_json(stats())
        elif path == "/api/modules":
            self._send_json(list_modules())
        elif path == "/api/layers":
            self._send_json(list_layers())
        elif path == "/api/adr":
            self._send_json(list_adr())
        elif path == "/api/docs":
            self._send_json(list_docs())
        elif path == "/api/tests":
            self._send_json(list_tests())
        else:
            self.send_error(404)

    def _send_html(self):
        if HTML is None:
            self.send_error(500, "index.html mancante")
            return
        body = HTML.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_json(self, data):
        body = json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        # Silenzioso (usa stderr custom se vuoi)
        sys.stderr.write(f"[progress-server] {fmt % args}\n")


if __name__ == "__main__":
    print(f"\n  SOLEM Progress Server")
    print(f"  Repo: {ROOT}")
    print(f"  Open: http://localhost:{PORT}\n")
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
