"""VECTOR STORE — wrapper LanceDB per L5 embedding cosine search.

Single responsibility: SOLO interfaccia con vector DB.
ADR-009 → LanceDB scelto come engine embedded.

Modelli embedding via Ollama:
  - nomic-embed-text (768 dim, default)
  - mxbai-embed-large (1024 dim, opzionale Step 3+)

Endpoint:
  POST /vector/index/{table}        — indicizza documento (testo → embedding)
  POST /vector/search/{table}       — cosine search top-K
  GET  /vector/tables               — lista tabelle disponibili
  DELETE /vector/index/{table}/{id} — elimina record

Step 0: scaffold. LanceDB deps richiede `python312Packages.lancedb` in
solem-api.nix pyDeps (da aggiungere quando attivato).
"""
from __future__ import annotations

import os
from pathlib import Path
from typing import Any

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/vector", tags=["vector"])

LANCE_DIR = Path(os.environ.get("SOLEM_LANCE_DIR", "/var/lib/gavio/memory/lance"))
OLLAMA_URL = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434")
EMBED_MODEL = os.environ.get("SOLEM_EMBED_MODEL", "nomic-embed-text")
EMBED_DIM = 768


class IndexRequest(BaseModel):
    id: str = Field(..., description="ID univoco del documento")
    text: str = Field(..., min_length=1)
    metadata: dict[str, Any] = Field(default_factory=dict)


class SearchRequest(BaseModel):
    query: str = Field(..., min_length=1)
    top_k: int = Field(10, ge=1, le=100)
    where: dict[str, Any] | None = Field(None, description="Filtro metadata (es. {source: 'chat'})")


class SearchHit(BaseModel):
    id: str
    score: float
    text: str
    metadata: dict[str, Any]


# ─── LanceDB lazy import (deps opzionale Step 0) ──────────────────────


def _get_lance():
    """Import LanceDB se disponibile. Altrimenti None (modulo stub)."""
    try:
        import lancedb
        return lancedb
    except ImportError:
        return None


def _connect():
    lance = _get_lance()
    if lance is None:
        return None
    LANCE_DIR.mkdir(parents=True, exist_ok=True)
    return lance.connect(str(LANCE_DIR))


# ─── Embedding via Ollama ─────────────────────────────────────────────


async def _embed(text: str) -> list[float]:
    """Chiama Ollama /api/embeddings per ottenere vettore."""
    async with httpx.AsyncClient(timeout=30.0) as c:
        r = await c.post(
            f"{OLLAMA_URL}/api/embeddings",
            json={"model": EMBED_MODEL, "prompt": text},
        )
        r.raise_for_status()
        return r.json().get("embedding", [])


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/status", response_model=dict)
async def status() -> dict:
    lance = _get_lance()
    db = _connect()
    return {
        "lance_available": lance is not None,
        "lance_dir": str(LANCE_DIR),
        "embedding_model": EMBED_MODEL,
        "embedding_dim": EMBED_DIM,
        "ollama_url": OLLAMA_URL,
        "tables": db.table_names() if db else [],
        "step": "scaffold (Step 0) — attiva con pyDeps.lancedb in solem-api.nix",
    }


@router.get("/tables", response_model=list[str])
async def list_tables() -> list[str]:
    db = _connect()
    if db is None:
        raise HTTPException(503, {"code": "lance_unavailable"})
    return db.table_names()


@router.post("/index/{table}", response_model=dict)
async def index_doc(table: str, req: IndexRequest) -> dict:
    db = _connect()
    if db is None:
        raise HTTPException(503, {"code": "lance_unavailable", "hint": "installa python312Packages.lancedb"})

    vec = await _embed(req.text)
    if not vec or len(vec) != EMBED_DIM:
        raise HTTPException(500, {"code": "embedding_failed", "got_dim": len(vec) if vec else 0})

    record = {
        "id": req.id,
        "text": req.text,
        "vector": vec,
        **{f"meta_{k}": v for k, v in req.metadata.items()},
    }

    try:
        t = db.open_table(table)
        t.add([record])
    except Exception:
        # Tabella nuova
        t = db.create_table(table, [record])

    return {"indexed": True, "id": req.id, "table": table, "vector_dim": len(vec)}


@router.post("/search/{table}", response_model=list[SearchHit])
async def search(table: str, req: SearchRequest) -> list[SearchHit]:
    db = _connect()
    if db is None:
        raise HTTPException(503, {"code": "lance_unavailable"})

    try:
        t = db.open_table(table)
    except Exception:
        raise HTTPException(404, {"code": "table_not_found", "table": table})

    qvec = await _embed(req.query)
    if not qvec:
        raise HTTPException(500, {"code": "embedding_failed"})

    results = t.search(qvec).limit(req.top_k).to_list()
    out: list[SearchHit] = []
    for r in results:
        meta = {k.removeprefix("meta_"): v for k, v in r.items() if k.startswith("meta_")}
        out.append(SearchHit(
            id=r.get("id", "?"),
            score=float(r.get("_distance", 0.0)),
            text=r.get("text", ""),
            metadata=meta,
        ))
    return out


@router.delete("/index/{table}/{doc_id}")
async def delete_doc(table: str, doc_id: str) -> dict:
    db = _connect()
    if db is None:
        raise HTTPException(503, {"code": "lance_unavailable"})
    t = db.open_table(table)
    t.delete(f"id = '{doc_id}'")
    return {"deleted": True, "id": doc_id}
