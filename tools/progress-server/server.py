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


def recent_commits(n: int = 15) -> list[dict]:
    """Ultimi N commit con subject + file changed."""
    import subprocess
    try:
        out = subprocess.run(
            ["git", "-C", str(ROOT), "log", f"-{n}", "--pretty=%h|%cr|%s"],
            capture_output=True, text=True, timeout=3,
        )
        if out.returncode != 0:
            return []
    except Exception:
        return []
    commits = []
    for line in out.stdout.strip().splitlines():
        parts = line.split("|", 2)
        if len(parts) == 3:
            commits.append({"sha": parts[0], "when": parts[1], "subject": parts[2]})
    return commits


def recent_files(n: int = 30) -> list[dict]:
    """File modificati più recenti — scansione mirata directory rilevanti."""
    SCAN_DIRS = [
        ROOT / "backend" / "solem_api" / "layers",
        ROOT / "backend" / "solem_api" / "middleware",
        ROOT / "nixos" / "modules",
        ROOT / "scripts",
        ROOT / "docs",
        ROOT / "tools" / "progress-server",
    ]
    files: list[tuple[float, Path]] = []
    for d in SCAN_DIRS:
        if not d.exists():
            continue
        for p in d.rglob("*"):
            try:
                if not p.is_file():
                    continue
            except OSError:
                continue
            if "__pycache__" in p.parts:
                continue
            try:
                mtime = p.stat().st_mtime
            except OSError:
                continue
            files.append((mtime, p))
    # Top-level files repo (CLAUDE.md, README, *.nix root, flake.nix)
    # NB: salta symlink Nix "result" che genera WinError 1920 su Windows
    for p in ROOT.glob("*"):
        try:
            if p.is_file():
                files.append((p.stat().st_mtime, p))
        except OSError:
            continue

    files.sort(reverse=True)
    import datetime
    out = []
    for mtime, p in files[:n]:
        try:
            rel = p.relative_to(ROOT).as_posix()
        except ValueError:
            continue
        when = datetime.datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M:%S")
        out.append({
            "path": rel,
            "mtime": when,
            "size_kb": round(p.stat().st_size / 1024, 1),
        })
    return out


def activity() -> dict:
    return {
        "commits": recent_commits(15),
        "files": recent_files(30),
        "github_url": "https://github.com/rguidotti-design/solem",
        "github_commits_url": "https://github.com/rguidotti-design/solem/commits/main",
    }


def build_status() -> dict:
    """Stato build artifacts: ISO presente? SD-image? (robusto su Windows: il symlink WSL può non risolvere)."""
    iso_files = []
    sd_files = []
    has_iso = False
    has_sd = False

    try:
        iso_path = ROOT / "result" / "iso"
        if iso_path.exists():
            for f in iso_path.glob("*.iso"):
                try:
                    iso_files.append({
                        "name": f.name,
                        "size_gb": round(f.stat().st_size / (1024**3), 2),
                    })
                    has_iso = True
                except OSError:
                    continue
    except OSError:
        pass

    try:
        sd_path = ROOT / "result" / "sd-image"
        if sd_path.exists():
            for f in sd_path.glob("*.img"):
                try:
                    sd_files.append({
                        "name": f.name,
                        "size_gb": round(f.stat().st_size / (1024**3), 2),
                    })
                    has_sd = True
                except OSError:
                    continue
    except OSError:
        pass

    return {
        "iso_built": has_iso,
        "iso_files": iso_files,
        "sd_image_built": has_sd,
        "sd_image_files": sd_files,
        "build_status_doc": "docs/BUILD-STATUS.md",
        "build_commands": {
            "iso": "nix build .#iso",
            "vm": "nix run .#vm",
            "raspberry": "nix build .#raspberry",
            "jetson": "nix build .#jetson",
        },
        "note": (
            "Su Windows host il symlink WSL 'result/' può non risolvere. "
            "Per verifica diretta: `wsl ls -lh /mnt/c/Users/guido/Desktop/solem/result/iso/`"
        ),
    }


HTML = (HERE / "index.html").read_text(encoding="utf-8") if (HERE / "index.html").exists() else None
PREVIEW_HTML = (HERE / "preview.html").read_text(encoding="utf-8") if (HERE / "preview.html").exists() else None
OVERLAY_HTML = (HERE / "overlay.html").read_text(encoding="utf-8") if (HERE / "overlay.html").exists() else None
MOBILE_HTML = (HERE / "mobile.html").read_text(encoding="utf-8") if (HERE / "mobile.html").exists() else None
GLASS_HTML = (HERE / "glass.html").read_text(encoding="utf-8") if (HERE / "glass.html").exists() else None
TOUR_HTML = (HERE / "tour.html").read_text(encoding="utf-8") if (HERE / "tour.html").exists() else None
MANIFEST = (HERE / "manifest.webmanifest").read_text(encoding="utf-8") if (HERE / "manifest.webmanifest").exists() else None
ICON192 = (HERE / "icon-192.svg").read_text(encoding="utf-8") if (HERE / "icon-192.svg").exists() else None
ICON512 = (HERE / "icon-512.svg").read_text(encoding="utf-8") if (HERE / "icon-512.svg").exists() else None


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/":
            self._send_html()
        elif path == "/preview":
            self._send_preview()
        elif path == "/overlay":
            self._send_overlay()
        elif path == "/mobile":
            self._send_static(MOBILE_HTML, "text/html; charset=utf-8")
        elif path == "/glass":
            self._send_static(GLASS_HTML, "text/html; charset=utf-8")
        elif path == "/tour":
            self._send_static(TOUR_HTML, "text/html; charset=utf-8")
        elif path == "/manifest.webmanifest":
            self._send_static(MANIFEST, "application/manifest+json")
        elif path == "/icon-192.svg":
            self._send_static(ICON192, "image/svg+xml")
        elif path == "/icon-512.svg":
            self._send_static(ICON512, "image/svg+xml")
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
        elif path == "/api/activity":
            self._send_json(activity())
        elif path == "/api/build-status":
            self._send_json(build_status())
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

    def _send_preview(self):
        if PREVIEW_HTML is None:
            self.send_error(500, "preview.html mancante")
            return
        body = PREVIEW_HTML.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_overlay(self):
        if OVERLAY_HTML is None:
            self.send_error(500, "overlay.html mancante")
            return
        body = OVERLAY_HTML.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_static(self, content, content_type):
        if content is None:
            self.send_error(404, "asset mancante")
            return
        body = content.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "public, max-age=300")
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
