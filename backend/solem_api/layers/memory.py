"""L5 — MEMORY & KNOWLEDGE (3 livelli)

Memoria assoluta per-utente. Step 0: SQLite + BLOB embedding placeholder
(slot pronto ma embedding calcolato Step 3+ quando arrivano sentence-transformers
locali o OpenAI embeddings).

Tre livelli:
  A. solem_memory          — interazioni dirette con SOLEM/GAVIO
  B. user_universe_memory  — universo esterno catturato (email, calendar, file)
  C. context_snapshots     — gestita da context.py (questo modulo non la duplica)

Endpoint:
  POST /memory/store         → salva nuovo memory record (livello A)
  GET  /memory/recent        → ultimi N record (filtrabili per source)
  POST /memory/search        → ricerca per testo (LIKE fallback; vector Step 3+)

  POST /memory/universe/store  → ingest universo esterno (livello B)
  GET  /memory/universe/recent → ultimi N record universo

Privacy levels (Livello B):
  public    — condivisibile con AI esterne
  work      — solo durante ruoli lavorativi
  personal  — default, accessibile a GAVIO sempre
  sacred    — MAI inviato a LLM esterni, solo modelli locali (Ollama)
"""
from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any, Literal

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field

from .db import get_conn, tx

router = APIRouter(prefix="/memory", tags=["memory"])

DEFAULT_USER_ID = "00000000-0000-0000-0000-000000000001"

SourceA = Literal["chat", "decision", "idea", "task", "identity_change", "wiki_entry", "command"]
SourceB = Literal["email", "calendar", "file", "photo", "browser", "voice", "other"]
PrivacyLevel = Literal["public", "work", "personal", "sacred"]


# ─── Schemas ──────────────────────────────────────────────────────────


class MemoryRecord(BaseModel):
    id: int | None = None
    user_id: str = DEFAULT_USER_ID
    source: SourceA
    content: str = Field(..., min_length=1)
    metadata: dict[str, Any] = Field(default_factory=dict)
    importance: float = Field(0.5, ge=0.0, le=1.0)
    created_at: str | None = None


class UniverseRecord(BaseModel):
    id: int | None = None
    user_id: str = DEFAULT_USER_ID
    source_type: SourceB
    source_id: str
    content: str
    metadata: dict[str, Any] = Field(default_factory=dict)
    privacy_level: PrivacyLevel = "personal"
    original_ts: str | None = None
    captured_at: str | None = None


class SearchRequest(BaseModel):
    query: str = Field(..., min_length=1)
    limit: int = Field(20, ge=1, le=100)
    source: SourceA | None = None
    min_importance: float = Field(0.0, ge=0.0, le=1.0)


class SearchHit(BaseModel):
    record: MemoryRecord
    score: float = Field(..., description="ranking score; Step 0 = match conteggio LIKE; Step 3+ = cosine vector")


# ─── Endpoints — Livello A (SOLEM memory) ────────────────────────────


@router.post("/store", response_model=MemoryRecord, status_code=201)
async def store(rec: MemoryRecord) -> MemoryRecord:
    """Salva nuovo record memoria SOLEM. Embedding NULL (calcolato Step 3+)."""
    with tx() as t:
        cur = t.execute(
            """INSERT INTO solem_memory (user_id, source, content, metadata, importance)
               VALUES (?, ?, ?, ?, ?)""",
            (
                rec.user_id,
                rec.source,
                rec.content,
                json.dumps(rec.metadata, ensure_ascii=False),
                rec.importance,
            ),
        )
        new_id = cur.lastrowid

    row = get_conn().execute("SELECT * FROM solem_memory WHERE id = ?", (new_id,)).fetchone()
    return _row_to_memory(row)


@router.get("/recent", response_model=list[MemoryRecord])
async def recent(
    limit: int = Query(20, ge=1, le=200),
    source: SourceA | None = None,
) -> list[MemoryRecord]:
    c = get_conn()
    if source:
        rows = c.execute(
            "SELECT * FROM solem_memory WHERE user_id = ? AND source = ? ORDER BY created_at DESC LIMIT ?",
            (DEFAULT_USER_ID, source, limit),
        ).fetchall()
    else:
        rows = c.execute(
            "SELECT * FROM solem_memory WHERE user_id = ? ORDER BY created_at DESC LIMIT ?",
            (DEFAULT_USER_ID, limit),
        ).fetchall()
    return [_row_to_memory(r) for r in rows]


@router.post("/search", response_model=list[SearchHit])
async def search(req: SearchRequest) -> list[SearchHit]:
    """Ricerca testuale. Step 0: LIKE su content. Step 3+: cosine su embedding."""
    pattern = f"%{req.query}%"
    c = get_conn()
    if req.source:
        rows = c.execute(
            """SELECT *, (LENGTH(content) - LENGTH(REPLACE(LOWER(content), LOWER(?), ''))) / NULLIF(LENGTH(?), 0) AS hits
               FROM solem_memory
               WHERE user_id = ? AND content LIKE ? AND source = ? AND importance >= ?
               ORDER BY hits DESC, importance DESC, created_at DESC LIMIT ?""",
            (req.query, req.query, DEFAULT_USER_ID, pattern, req.source, req.min_importance, req.limit),
        ).fetchall()
    else:
        rows = c.execute(
            """SELECT *, (LENGTH(content) - LENGTH(REPLACE(LOWER(content), LOWER(?), ''))) / NULLIF(LENGTH(?), 0) AS hits
               FROM solem_memory
               WHERE user_id = ? AND content LIKE ? AND importance >= ?
               ORDER BY hits DESC, importance DESC, created_at DESC LIMIT ?""",
            (req.query, req.query, DEFAULT_USER_ID, pattern, req.min_importance, req.limit),
        ).fetchall()

    return [
        SearchHit(
            record=_row_to_memory(r),
            score=float(r["hits"] or 0) * 0.5 + float(r["importance"]) * 0.5,
        )
        for r in rows
    ]


# ─── Endpoints — Livello B (Universe memory) ─────────────────────────


@router.post("/universe/store", response_model=UniverseRecord, status_code=201)
async def universe_store(rec: UniverseRecord) -> UniverseRecord:
    """Ingest record dall'universo utente (email, file, ecc.)."""
    with tx() as t:
        cur = t.execute(
            """INSERT INTO user_universe_memory
               (user_id, source_type, source_id, content, metadata, privacy_level, original_ts)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (
                rec.user_id,
                rec.source_type,
                rec.source_id,
                rec.content,
                json.dumps(rec.metadata, ensure_ascii=False),
                rec.privacy_level,
                rec.original_ts,
            ),
        )
        new_id = cur.lastrowid

    row = get_conn().execute("SELECT * FROM user_universe_memory WHERE id = ?", (new_id,)).fetchone()
    return _row_to_universe(row)


@router.get("/universe/recent", response_model=list[UniverseRecord])
async def universe_recent(
    limit: int = Query(20, ge=1, le=200),
    source_type: SourceB | None = None,
) -> list[UniverseRecord]:
    c = get_conn()
    if source_type:
        rows = c.execute(
            "SELECT * FROM user_universe_memory WHERE user_id = ? AND source_type = ? ORDER BY captured_at DESC LIMIT ?",
            (DEFAULT_USER_ID, source_type, limit),
        ).fetchall()
    else:
        rows = c.execute(
            "SELECT * FROM user_universe_memory WHERE user_id = ? ORDER BY captured_at DESC LIMIT ?",
            (DEFAULT_USER_ID, limit),
        ).fetchall()
    return [_row_to_universe(r) for r in rows]


# ─── Helpers ──────────────────────────────────────────────────────────


def _row_to_memory(r) -> MemoryRecord:
    return MemoryRecord(
        id=r["id"],
        user_id=r["user_id"],
        source=r["source"],
        content=r["content"],
        metadata=json.loads(r["metadata"]) if r["metadata"] else {},
        importance=r["importance"],
        created_at=r["created_at"],
    )


def _row_to_universe(r) -> UniverseRecord:
    return UniverseRecord(
        id=r["id"],
        user_id=r["user_id"],
        source_type=r["source_type"],
        source_id=r["source_id"],
        content=r["content"],
        metadata=json.loads(r["metadata"]) if r["metadata"] else {},
        privacy_level=r["privacy_level"],
        original_ts=r["original_ts"],
        captured_at=r["captured_at"],
    )
