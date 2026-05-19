"""L7 — EXTENSIONS MARKETPLACE (scheletro Step 0)

Plugin di terze parti che estendono SOLEM con capabilities, AI specialiste,
bridge custom. Step 0: registry + manifest schema. Step 4+: hot-load runtime,
sandboxing AppArmor, payment marketplace.

Manifest di una extension (`solem.extension.json`):

  {
    "id": "com.example.cool-extension",
    "name": "Cool Extension",
    "version": "1.0.0",
    "author": "Example Org",
    "description": "Aggiunge capability X",
    "type": "capability | agent | bridge | ui-component",
    "entry_point": "main.py",  # o package npm, ecc.
    "requires_solem": ">=0.1.0",
    "permissions": ["filesystem.read", "network.outbound"],
    "capabilities_added": [{...}],
    "agents_added": [{...}]
  }

Endpoint:
  GET    /extensions                — lista installate
  GET    /extensions/{id}           — dettaglio
  POST   /extensions/install        — installa (download + verify + sandbox)
  POST   /extensions/{id}/enable    — attiva
  POST   /extensions/{id}/disable   — disattiva
  DELETE /extensions/{id}           — uninstall
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from .db import get_conn, tx

router = APIRouter(prefix="/extensions", tags=["extensions"])

EXTENSIONS_DIR = Path("/var/lib/solem/extensions")


class ExtensionManifest(BaseModel):
    id: str = Field(..., pattern=r"^[a-z][a-z0-9.-]+$")
    name: str
    version: str
    author: str
    description: str
    type: Literal["capability", "agent", "bridge", "ui-component"]
    entry_point: str
    requires_solem: str = ">=0.1.0"
    permissions: list[str] = Field(default_factory=list)
    capabilities_added: list[dict[str, Any]] = Field(default_factory=list)
    agents_added: list[dict[str, Any]] = Field(default_factory=list)


class ExtensionStatus(BaseModel):
    manifest: ExtensionManifest
    installed_at: str
    enabled: bool
    state: Literal["installed", "running", "error", "uninstalled"]
    install_path: str


class InstallRequest(BaseModel):
    source: str = Field(..., description="URL Git/HTTP da cui scaricare, o path locale")
    verify: bool = True


def _ensure_table() -> None:
    c = get_conn()
    c.execute("""
    CREATE TABLE IF NOT EXISTS extensions (
        id           TEXT PRIMARY KEY,
        manifest     TEXT NOT NULL,
        installed_at TEXT NOT NULL DEFAULT (datetime('now')),
        enabled      INTEGER NOT NULL DEFAULT 1,
        state        TEXT NOT NULL DEFAULT 'installed',
        install_path TEXT NOT NULL
    );
    """)


@router.get("", response_model=list[ExtensionStatus])
async def list_extensions() -> list[ExtensionStatus]:
    _ensure_table()
    c = get_conn()
    rows = c.execute("SELECT * FROM extensions ORDER BY installed_at DESC").fetchall()
    return [
        ExtensionStatus(
            manifest=ExtensionManifest(**json.loads(r["manifest"])),
            installed_at=r["installed_at"],
            enabled=bool(r["enabled"]),
            state=r["state"],
            install_path=r["install_path"],
        )
        for r in rows
    ]


@router.get("/{ext_id}", response_model=ExtensionStatus)
async def get_extension(ext_id: str) -> ExtensionStatus:
    _ensure_table()
    c = get_conn()
    r = c.execute("SELECT * FROM extensions WHERE id = ?", (ext_id,)).fetchone()
    if r is None:
        raise HTTPException(404, {"code": "extension_not_found", "id": ext_id})
    return ExtensionStatus(
        manifest=ExtensionManifest(**json.loads(r["manifest"])),
        installed_at=r["installed_at"],
        enabled=bool(r["enabled"]),
        state=r["state"],
        install_path=r["install_path"],
    )


@router.post("/install", response_model=ExtensionStatus, status_code=201)
async def install_extension(req: InstallRequest) -> ExtensionStatus:
    """Step 0: stub — accetta path locale a manifest, registra in DB.
    Step 4+: download + verify firma + sandbox + AppArmor profile."""
    _ensure_table()

    manifest_path = Path(req.source) / "solem.extension.json"
    if not manifest_path.exists():
        raise HTTPException(400, {
            "code": "manifest_not_found",
            "message": f"Atteso {manifest_path}",
        })

    try:
        manifest_data = json.loads(manifest_path.read_text())
        manifest = ExtensionManifest(**manifest_data)
    except (json.JSONDecodeError, ValueError) as e:
        raise HTTPException(400, {"code": "invalid_manifest", "error": str(e)})

    install_path = EXTENSIONS_DIR / manifest.id
    install_path.mkdir(parents=True, exist_ok=True)

    with tx() as t:
        try:
            t.execute(
                """INSERT INTO extensions (id, manifest, install_path, state)
                   VALUES (?, ?, ?, 'installed')""",
                (manifest.id, json.dumps(manifest.model_dump()), str(install_path)),
            )
        except Exception as e:
            raise HTTPException(409, {"code": "already_installed", "id": manifest.id, "error": str(e)})

    return await get_extension(manifest.id)


@router.post("/{ext_id}/enable", response_model=ExtensionStatus)
async def enable_extension(ext_id: str) -> ExtensionStatus:
    _ensure_table()
    with tx() as t:
        cur = t.execute("UPDATE extensions SET enabled = 1 WHERE id = ?", (ext_id,))
        if cur.rowcount == 0:
            raise HTTPException(404, {"code": "extension_not_found"})
    return await get_extension(ext_id)


@router.post("/{ext_id}/disable", response_model=ExtensionStatus)
async def disable_extension(ext_id: str) -> ExtensionStatus:
    _ensure_table()
    with tx() as t:
        cur = t.execute("UPDATE extensions SET enabled = 0 WHERE id = ?", (ext_id,))
        if cur.rowcount == 0:
            raise HTTPException(404, {"code": "extension_not_found"})
    return await get_extension(ext_id)


@router.delete("/{ext_id}")
async def uninstall_extension(ext_id: str) -> dict:
    _ensure_table()
    with tx() as t:
        cur = t.execute("DELETE FROM extensions WHERE id = ?", (ext_id,))
        if cur.rowcount == 0:
            raise HTTPException(404, {"code": "extension_not_found"})
    return {"uninstalled": True, "id": ext_id}
