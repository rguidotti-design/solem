"""MEMORY FEDERATION — GAVIO memory sincronizzata cross-device.

Single responsibility: SOLO sync delle memorie GAVIO tra device del cluster.
Niente generazione memorie (è GAVIO che le produce). Niente reasoning.

Modello:
  - Ogni memoria = {id, text, kind, created_at, device_origin, vector_clock}
  - Operazioni: ADD, UPDATE, DELETE (tombstone)
  - Conflict resolution: vector clock per device, last-write-wins per id stesso
  - Storage: SQLite locale + sync via /cluster/dispatch verso peer

Tipi memoria (replica i tipi del memory system GAVIO):
  - user        — fatti sull'utente (ruolo, preferenze)
  - feedback    — correzioni esplicite
  - project     — stato progetti in corso
  - reference   — pointer a sistemi esterni

Endpoint:
  GET    /memory/all                  — tutte le memorie locali
  POST   /memory                      — aggiungi memoria (broadcast cluster)
  GET    /memory/{id}                 — dettaglio
  PUT    /memory/{id}                 — update
  DELETE /memory/{id}                 — tombstone
  POST   /memory/sync                 — pull da gateway / merge
  GET    /memory/diff?since={vc}      — delta dopo vector clock (per altri device)
"""
from __future__ import annotations

import json
import os
import sqlite3
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/memory", tags=["memory-federation"])

DB_PATH = Path(os.environ.get("SOLEM_MEMORY_DB", "/var/lib/solem/memory.db"))
DEVICE_ID = os.environ.get("SOLEM_DEVICE_ID", "default")
GATEWAY = os.environ.get("SOLEM_CLUSTER_GATEWAY", "http://127.0.0.1:8001")


class Memory(BaseModel):
    id: str = Field(default_factory=lambda: uuid.uuid4().hex[:12])
    kind: Literal["user", "feedback", "project", "reference"] = "user"
    text: str = Field(..., min_length=1)
    created_at: str = Field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    updated_at: str = Field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    device_origin: str = Field(default=DEVICE_ID)
    tombstoned: bool = False
    vector_clock: dict[str, int] = Field(default_factory=dict)
    tags: list[str] = Field(default_factory=list)


class MemoryDiff(BaseModel):
    since: dict[str, int] = Field(default_factory=dict)
    memories: list[Memory]
    new_vector_clock: dict[str, int]


# ─── SQLite storage ───────────────────────────────────────────────────


def _db() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    c = sqlite3.connect(DB_PATH)
    c.row_factory = sqlite3.Row
    c.execute("PRAGMA journal_mode=WAL")
    c.execute("""
        CREATE TABLE IF NOT EXISTS memories (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            text TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            device_origin TEXT NOT NULL,
            tombstoned INTEGER DEFAULT 0,
            vector_clock TEXT NOT NULL DEFAULT '{}',
            tags TEXT NOT NULL DEFAULT '[]'
        )
    """)
    c.execute("CREATE INDEX IF NOT EXISTS idx_kind ON memories(kind)")
    c.execute("CREATE INDEX IF NOT EXISTS idx_updated ON memories(updated_at)")
    return c


def _to_memory(row) -> Memory:
    return Memory(
        id=row["id"],
        kind=row["kind"],
        text=row["text"],
        created_at=row["created_at"],
        updated_at=row["updated_at"],
        device_origin=row["device_origin"],
        tombstoned=bool(row["tombstoned"]),
        vector_clock=json.loads(row["vector_clock"]),
        tags=json.loads(row["tags"]),
    )


def _save(c: sqlite3.Connection, m: Memory) -> None:
    c.execute("""
        INSERT INTO memories(id,kind,text,created_at,updated_at,device_origin,tombstoned,vector_clock,tags)
        VALUES (?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET
            kind=excluded.kind,
            text=excluded.text,
            updated_at=excluded.updated_at,
            tombstoned=excluded.tombstoned,
            vector_clock=excluded.vector_clock,
            tags=excluded.tags
    """, (m.id, m.kind, m.text, m.created_at, m.updated_at, m.device_origin,
          int(m.tombstoned), json.dumps(m.vector_clock), json.dumps(m.tags)))
    c.commit()


# ─── Vector clock helpers ─────────────────────────────────────────────


def _bump_vc(vc: dict[str, int]) -> dict[str, int]:
    """Incrementa il vector clock per QUESTO device."""
    new = dict(vc)
    new[DEVICE_ID] = new.get(DEVICE_ID, 0) + 1
    return new


def _vc_greater_or_equal(a: dict[str, int], b: dict[str, int]) -> bool:
    """a ≥ b (a domina b) se a[k] ≥ b[k] per ogni k in b."""
    return all(a.get(k, 0) >= v for k, v in b.items())


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/health", response_model=dict)
async def mem_health() -> dict:
    c = _db()
    try:
        n = c.execute("SELECT COUNT(*) AS n FROM memories WHERE tombstoned=0").fetchone()["n"]
        n_tomb = c.execute("SELECT COUNT(*) AS n FROM memories WHERE tombstoned=1").fetchone()["n"]
        return {
            "db_path": str(DB_PATH),
            "device_id": DEVICE_ID,
            "live_memories": n,
            "tombstoned": n_tomb,
            "gateway": GATEWAY,
        }
    finally:
        c.close()


@router.get("/all", response_model=list[Memory])
async def list_all(kind: str | None = None, include_tombstoned: bool = False) -> list[Memory]:
    c = _db()
    try:
        q = "SELECT * FROM memories"
        params = []
        clauses = []
        if not include_tombstoned:
            clauses.append("tombstoned = 0")
        if kind:
            clauses.append("kind = ?")
            params.append(kind)
        if clauses:
            q += " WHERE " + " AND ".join(clauses)
        q += " ORDER BY updated_at DESC"
        rows = c.execute(q, params).fetchall()
        return [_to_memory(r) for r in rows]
    finally:
        c.close()


@router.post("", response_model=Memory)
async def add(m: Memory) -> Memory:
    m.device_origin = DEVICE_ID
    m.created_at = m.created_at or datetime.now(timezone.utc).isoformat()
    m.updated_at = datetime.now(timezone.utc).isoformat()
    m.vector_clock = _bump_vc(m.vector_clock)
    c = _db()
    try:
        _save(c, m)
        return m
    finally:
        c.close()


@router.get("/{mem_id}", response_model=Memory)
async def get_one(mem_id: str) -> Memory:
    c = _db()
    try:
        row = c.execute("SELECT * FROM memories WHERE id = ?", (mem_id,)).fetchone()
        if not row:
            raise HTTPException(404, {"code": "memory_not_found"})
        return _to_memory(row)
    finally:
        c.close()


@router.put("/{mem_id}", response_model=Memory)
async def update(mem_id: str, patch: Memory) -> Memory:
    c = _db()
    try:
        row = c.execute("SELECT * FROM memories WHERE id = ?", (mem_id,)).fetchone()
        if not row:
            raise HTTPException(404, {"code": "memory_not_found"})
        cur = _to_memory(row)
        cur.text = patch.text or cur.text
        cur.kind = patch.kind or cur.kind
        cur.tags = patch.tags or cur.tags
        cur.updated_at = datetime.now(timezone.utc).isoformat()
        cur.vector_clock = _bump_vc(cur.vector_clock)
        _save(c, cur)
        return cur
    finally:
        c.close()


@router.delete("/{mem_id}")
async def remove(mem_id: str) -> dict:
    c = _db()
    try:
        row = c.execute("SELECT * FROM memories WHERE id = ?", (mem_id,)).fetchone()
        if not row:
            raise HTTPException(404, {"code": "memory_not_found"})
        cur = _to_memory(row)
        cur.tombstoned = True
        cur.updated_at = datetime.now(timezone.utc).isoformat()
        cur.vector_clock = _bump_vc(cur.vector_clock)
        _save(c, cur)
        return {"tombstoned": True, "id": mem_id}
    finally:
        c.close()


@router.get("/diff/since", response_model=MemoryDiff)
async def diff_since(vc_b64: str = "{}") -> MemoryDiff:
    """Ritorna le memorie che hanno vector_clock NON dominato dal vc del peer."""
    import base64
    try:
        their_vc = json.loads(base64.urlsafe_b64decode(vc_b64 + "=="))
        if not isinstance(their_vc, dict):
            their_vc = {}
    except (ValueError, json.JSONDecodeError):
        their_vc = {}

    c = _db()
    try:
        all_rows = c.execute("SELECT * FROM memories").fetchall()
        delta = []
        max_vc: dict[str, int] = {}
        for row in all_rows:
            m = _to_memory(row)
            for k, v in m.vector_clock.items():
                max_vc[k] = max(max_vc.get(k, 0), v)
            if not _vc_greater_or_equal(their_vc, m.vector_clock):
                delta.append(m)
        return MemoryDiff(since=their_vc, memories=delta, new_vector_clock=max_vc)
    finally:
        c.close()


@router.post("/sync", response_model=dict)
async def sync_from_gateway() -> dict:
    """Pull dal gateway: cerca peer migliore via cluster, scarica diff, merge."""
    c = _db()
    try:
        # Vector clock locale = max per device
        rows = c.execute("SELECT vector_clock FROM memories").fetchall()
        my_vc: dict[str, int] = {}
        for r in rows:
            try:
                vc = json.loads(r["vector_clock"])
                for k, v in vc.items():
                    my_vc[k] = max(my_vc.get(k, 0), v)
            except (json.JSONDecodeError, TypeError):
                continue
    finally:
        c.close()

    import base64
    vc_b64 = base64.urlsafe_b64encode(json.dumps(my_vc).encode()).rstrip(b"=").decode()

    try:
        async with httpx.AsyncClient(timeout=15.0) as cli:
            r = await cli.get(f"{GATEWAY}/solem/memory/diff/since?vc_b64={vc_b64}")
            if r.status_code != 200:
                return {"synced": False, "reason": f"gateway returned {r.status_code}"}
            diff = r.json()
    except httpx.HTTPError as e:
        return {"synced": False, "reason": str(e)}

    # Merge: last-write-wins su update_at
    c = _db()
    merged = 0
    try:
        for raw in diff.get("memories", []):
            m = Memory(**raw)
            existing = c.execute("SELECT updated_at FROM memories WHERE id = ?", (m.id,)).fetchone()
            if existing and existing["updated_at"] >= m.updated_at:
                continue
            _save(c, m)
            merged += 1
    finally:
        c.close()

    return {"synced": True, "merged": merged, "from": GATEWAY}
