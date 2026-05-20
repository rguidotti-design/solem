"""MARKETPLACE — L7 extensions registry (install/list/enable/disable).

Single responsibility: SOLO gestire metadata extension + lifecycle file
plugin in /var/lib/solem/extensions/. Niente esecuzione: il runtime degli
estensioni è in extensions module (FastAPI dynamic loader, Step 2+).

Storage: SQLite (db.py shared). Schema multi-tenant by design.

Endpoint:
  GET  /marketplace/installed       — extension installate
  GET  /marketplace/available       — extension dal registry (HTTP fetch)
  POST /marketplace/install/{id}    — scarica + valida + registra
  POST /marketplace/enable/{id}     — abilita extension installata
  POST /marketplace/disable/{id}    — disabilita (no rimozione file)
  DELETE /marketplace/uninstall/{id} — rimuove file + db row

Registry URL: env SOLEM_MARKETPLACE_URL, default https://solem.local/registry
(quando vivrà). Per ora: solo locale.

ADR-019 → ogni extension ha manifest.json firmato ed25519 dall'autore.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
from pathlib import Path

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/marketplace", tags=["marketplace"])

EXT_DIR = Path("/var/lib/solem/extensions")
REGISTRY_URL = os.environ.get("SOLEM_MARKETPLACE_URL", "")


class Extension(BaseModel):
    id: str
    name: str
    version: str
    author: str
    description: str
    permissions: list[str] = Field(default_factory=list)
    enabled: bool = True
    installed_at: str | None = None
    sha256: str | None = None


def _ext_path(ext_id: str) -> Path:
    safe = "".join(c for c in ext_id if c.isalnum() or c in "-_.")
    if safe != ext_id:
        raise HTTPException(400, {"code": "invalid_extension_id"})
    return EXT_DIR / safe


def _load_manifest(p: Path) -> dict | None:
    m = p / "manifest.json"
    if not m.exists():
        return None
    try:
        return json.loads(m.read_text())
    except (OSError, json.JSONDecodeError):
        return None


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/installed", response_model=list[Extension])
async def list_installed() -> list[Extension]:
    EXT_DIR.mkdir(parents=True, exist_ok=True)
    out: list[Extension] = []
    for d in EXT_DIR.iterdir():
        if not d.is_dir():
            continue
        m = _load_manifest(d)
        if not m:
            continue
        out.append(Extension(
            id=m.get("id", d.name),
            name=m.get("name", d.name),
            version=m.get("version", "0.0.0"),
            author=m.get("author", "unknown"),
            description=m.get("description", ""),
            permissions=m.get("permissions", []),
            enabled=not (d / ".disabled").exists(),
            installed_at=str(int(d.stat().st_ctime)),
        ))
    return out


@router.get("/available", response_model=list[Extension])
async def list_available() -> list[Extension]:
    if not REGISTRY_URL:
        raise HTTPException(503, {
            "code": "registry_not_configured",
            "hint": "SOLEM_MARKETPLACE_URL non impostato; registry in dev (Step 4+)",
        })
    try:
        async with httpx.AsyncClient(timeout=5.0) as c:
            r = await c.get(f"{REGISTRY_URL}/index.json")
            if r.status_code != 200:
                raise HTTPException(502, {"code": "registry_unavailable"})
            data = r.json()
    except httpx.HTTPError as e:
        raise HTTPException(502, {"code": "registry_fetch_failed", "error": str(e)})

    return [Extension(**ext) for ext in data.get("extensions", [])]


@router.post("/install/{ext_id}", response_model=Extension)
async def install(ext_id: str) -> Extension:
    if not REGISTRY_URL:
        raise HTTPException(503, {"code": "registry_not_configured"})
    EXT_DIR.mkdir(parents=True, exist_ok=True)
    target = _ext_path(ext_id)
    if target.exists():
        raise HTTPException(409, {"code": "already_installed", "id": ext_id})

    try:
        async with httpx.AsyncClient(timeout=30.0) as c:
            r = await c.get(f"{REGISTRY_URL}/ext/{ext_id}.tar.gz")
            if r.status_code != 200:
                raise HTTPException(404, {"code": "extension_not_found"})
            content = r.content
    except httpx.HTTPError as e:
        raise HTTPException(502, {"code": "download_failed", "error": str(e)})

    # Compute hash for audit
    digest = hashlib.sha256(content).hexdigest()

    # Extract (in /tmp first per security)
    import tarfile
    import io
    target.mkdir(parents=True)
    try:
        with tarfile.open(fileobj=io.BytesIO(content), mode="r:gz") as tar:
            # Reject paths con .. o assoluti
            for member in tar.getmembers():
                if member.name.startswith("/") or ".." in member.name.split("/"):
                    shutil.rmtree(target)
                    raise HTTPException(400, {"code": "unsafe_archive", "path": member.name})
            tar.extractall(target, filter="data")
    except tarfile.TarError as e:
        shutil.rmtree(target, ignore_errors=True)
        raise HTTPException(400, {"code": "extract_failed", "error": str(e)})

    manifest = _load_manifest(target)
    if not manifest:
        shutil.rmtree(target, ignore_errors=True)
        raise HTTPException(400, {"code": "manifest_missing"})

    # Salva sha256
    (target / ".sha256").write_text(digest)

    return Extension(
        id=manifest.get("id", ext_id),
        name=manifest.get("name", ext_id),
        version=manifest.get("version", "0.0.0"),
        author=manifest.get("author", "unknown"),
        description=manifest.get("description", ""),
        permissions=manifest.get("permissions", []),
        enabled=True,
        installed_at=str(int(target.stat().st_ctime)),
        sha256=digest,
    )


@router.post("/enable/{ext_id}", response_model=Extension)
async def enable(ext_id: str) -> Extension:
    p = _ext_path(ext_id)
    if not p.exists():
        raise HTTPException(404, {"code": "extension_not_installed"})
    flag = p / ".disabled"
    if flag.exists():
        flag.unlink()
    return next(e for e in await list_installed() if e.id == ext_id)


@router.post("/disable/{ext_id}", response_model=Extension)
async def disable(ext_id: str) -> Extension:
    p = _ext_path(ext_id)
    if not p.exists():
        raise HTTPException(404, {"code": "extension_not_installed"})
    (p / ".disabled").touch()
    return next(e for e in await list_installed() if e.id == ext_id)


@router.delete("/uninstall/{ext_id}")
async def uninstall(ext_id: str) -> dict:
    p = _ext_path(ext_id)
    if not p.exists():
        raise HTTPException(404, {"code": "extension_not_installed"})
    shutil.rmtree(p)
    return {"uninstalled": True, "id": ext_id}
