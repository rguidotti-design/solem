"""CRDT SYNC — scaffold sync multi-device via Y-CRDT.

Single responsibility: SOLO sync state via CRDT update messages.
Niente storage business, niente trasporto (delegato a mesh WireGuard).

ADR-017 → Y-CRDT (yrs Rust bindings) per testo, JSON e mappe. Conflict
resolution automatica, offline-first. Update binari piccoli (~bytes).

Endpoint:
  GET  /crdt/docs                   — lista doc sync-ate
  POST /crdt/docs/{doc_id}/init     — crea doc (vuoto)
  POST /crdt/docs/{doc_id}/update   — applica update binario
  GET  /crdt/docs/{doc_id}/state    — state vector per delta sync
  POST /crdt/docs/{doc_id}/delta    — calcola delta da state vector remoto

Step 0: scaffold. y-py deps richiede `python312Packages.y-py` in
solem-api.nix pyDeps (da aggiungere quando attivato).
"""
from __future__ import annotations

import base64
import json
import os
from pathlib import Path
from typing import Any

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/crdt", tags=["crdt"])

DOCS_DIR = Path(os.environ.get("SOLEM_CRDT_DIR", "/var/lib/solem/crdt"))


class DocInfo(BaseModel):
    doc_id: str
    created_at: str
    size_bytes: int
    last_updated_at: str | None = None


class UpdateRequest(BaseModel):
    update_b64: str = Field(..., description="Update Y-CRDT base64-encoded")


class StateVector(BaseModel):
    state_vector_b64: str


class DeltaRequest(BaseModel):
    remote_state_vector_b64: str


class DeltaResponse(BaseModel):
    delta_b64: str
    bytes: int


def _get_y():
    try:
        import y_py
        return y_py
    except ImportError:
        return None


def _doc_file(doc_id: str) -> Path:
    safe = "".join(c for c in doc_id if c.isalnum() or c in "-_")
    if not safe or safe != doc_id:
        raise HTTPException(400, {"code": "invalid_doc_id", "message": "doc_id deve essere [A-Za-z0-9_-]+"})
    return DOCS_DIR / f"{safe}.ydoc"


@router.get("/health", response_model=dict)
async def crdt_health() -> dict:
    y = _get_y()
    DOCS_DIR.mkdir(parents=True, exist_ok=True)
    docs = list(DOCS_DIR.glob("*.ydoc"))
    return {
        "y_py_available": y is not None,
        "docs_dir": str(DOCS_DIR),
        "total_docs": len(docs),
        "step": "scaffold (Step 0) — installa python312Packages.y-py per attivare",
    }


@router.get("/docs", response_model=list[DocInfo])
async def list_docs() -> list[DocInfo]:
    DOCS_DIR.mkdir(parents=True, exist_ok=True)
    out: list[DocInfo] = []
    for f in DOCS_DIR.glob("*.ydoc"):
        stat = f.stat()
        out.append(DocInfo(
            doc_id=f.stem,
            created_at=str(int(stat.st_ctime)),
            size_bytes=stat.st_size,
            last_updated_at=str(int(stat.st_mtime)),
        ))
    return out


@router.post("/docs/{doc_id}/init", response_model=DocInfo)
async def init_doc(doc_id: str) -> DocInfo:
    y = _get_y()
    if y is None:
        raise HTTPException(503, {"code": "y_py_unavailable"})
    DOCS_DIR.mkdir(parents=True, exist_ok=True)
    f = _doc_file(doc_id)
    if f.exists():
        raise HTTPException(409, {"code": "doc_exists", "doc_id": doc_id})

    doc = y.YDoc()
    snapshot = y.encode_state_as_update(doc)
    f.write_bytes(bytes(snapshot))
    stat = f.stat()
    return DocInfo(doc_id=doc_id, created_at=str(int(stat.st_ctime)), size_bytes=stat.st_size)


@router.post("/docs/{doc_id}/update", response_model=DocInfo)
async def apply_update(doc_id: str, req: UpdateRequest) -> DocInfo:
    y = _get_y()
    if y is None:
        raise HTTPException(503, {"code": "y_py_unavailable"})
    f = _doc_file(doc_id)
    if not f.exists():
        raise HTTPException(404, {"code": "doc_not_found"})

    try:
        update = base64.b64decode(req.update_b64)
    except (ValueError, TypeError):
        raise HTTPException(400, {"code": "invalid_base64"})

    doc = y.YDoc()
    y.apply_update(doc, f.read_bytes())
    y.apply_update(doc, update)
    f.write_bytes(bytes(y.encode_state_as_update(doc)))

    stat = f.stat()
    return DocInfo(doc_id=doc_id, created_at=str(int(stat.st_ctime)), size_bytes=stat.st_size, last_updated_at=str(int(stat.st_mtime)))


@router.get("/docs/{doc_id}/state", response_model=StateVector)
async def get_state_vector(doc_id: str) -> StateVector:
    y = _get_y()
    if y is None:
        raise HTTPException(503, {"code": "y_py_unavailable"})
    f = _doc_file(doc_id)
    if not f.exists():
        raise HTTPException(404, {"code": "doc_not_found"})

    doc = y.YDoc()
    y.apply_update(doc, f.read_bytes())
    sv = y.encode_state_vector(doc)
    return StateVector(state_vector_b64=base64.b64encode(bytes(sv)).decode())


@router.post("/docs/{doc_id}/delta", response_model=DeltaResponse)
async def compute_delta(doc_id: str, req: DeltaRequest) -> DeltaResponse:
    """Restituisce SOLO le operations che il client remoto non ha ancora."""
    y = _get_y()
    if y is None:
        raise HTTPException(503, {"code": "y_py_unavailable"})
    f = _doc_file(doc_id)
    if not f.exists():
        raise HTTPException(404, {"code": "doc_not_found"})

    try:
        remote_sv = base64.b64decode(req.remote_state_vector_b64)
    except (ValueError, TypeError):
        raise HTTPException(400, {"code": "invalid_base64"})

    doc = y.YDoc()
    y.apply_update(doc, f.read_bytes())
    delta = y.encode_state_as_update(doc, remote_sv)
    delta_bytes = bytes(delta)
    return DeltaResponse(delta_b64=base64.b64encode(delta_bytes).decode(), bytes=len(delta_bytes))
