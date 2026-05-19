"""DB MIGRATIONS — sistema versionato per evoluzione schema

Step 0: schema iniziale auto-creato da db.py._init_schema().
Step 2+: schema migrations versionate qui (no destructive changes su prod).

Modello:
  - Ogni migration ha un version_id intero progressivo
  - Tabella schema_migrations traccia quali sono state applicate
  - Migration sono funzioni Python con `up(conn)` e opzionalmente `down(conn)`
  - Applicate in ordine, idempotenti

Endpoint:
  GET  /migrations            — stato corrente (applied, pending)
  POST /migrations/apply      — applica pending (owner only)
"""
from __future__ import annotations

import sqlite3
from typing import Callable

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from .db import get_conn, tx
from .users import User, get_current_user

router = APIRouter(prefix="/migrations", tags=["migrations"])


class Migration(BaseModel):
    version: int
    name: str
    description: str
    applied_at: str | None = None


# ─── Registry migrations ─────────────────────────────────────────────


def _migration_001_indexes_event_user(c: sqlite3.Connection) -> None:
    """Aggiungi indice composto eventi (user_id, ts) per query frequenti."""
    c.executescript("""
    CREATE INDEX IF NOT EXISTS idx_events_user_ts
        ON events(user_id, ts DESC);
    """)


def _migration_002_memory_user_index(c: sqlite3.Connection) -> None:
    """Indice composto per ricerche memoria per (user_id, importance)."""
    c.executescript("""
    CREATE INDEX IF NOT EXISTS idx_solem_memory_user_importance
        ON solem_memory(user_id, importance DESC);
    """)


def _migration_003_sessions_revoked_index(c: sqlite3.Connection) -> None:
    """Indice per pulizia rapida sessioni revocate/scadute."""
    c.executescript("""
    CREATE INDEX IF NOT EXISTS idx_sessions_revoked_expires
        ON sessions(revoked_at, expires_at);
    """)


MIGRATIONS: list[tuple[int, str, str, Callable[[sqlite3.Connection], None]]] = [
    (1, "events_user_ts_index",       "Indice (user_id, ts DESC) su events", _migration_001_indexes_event_user),
    (2, "memory_user_importance_idx", "Indice (user_id, importance DESC) su solem_memory", _migration_002_memory_user_index),
    (3, "sessions_revoked_idx",       "Indice (revoked_at, expires_at) su sessions", _migration_003_sessions_revoked_index),
]


# ─── Helpers ──────────────────────────────────────────────────────────


def _ensure_migrations_table() -> None:
    c = get_conn()
    c.executescript("""
    CREATE TABLE IF NOT EXISTS schema_migrations (
        version    INTEGER PRIMARY KEY,
        name       TEXT NOT NULL,
        applied_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    """)


def _applied_versions() -> set[int]:
    _ensure_migrations_table()
    c = get_conn()
    return {r["version"] for r in c.execute("SELECT version FROM schema_migrations")}


def _migration_status() -> list[Migration]:
    applied = {}
    _ensure_migrations_table()
    c = get_conn()
    for r in c.execute("SELECT version, applied_at FROM schema_migrations"):
        applied[r["version"]] = r["applied_at"]

    out = []
    for v, name, desc, _fn in MIGRATIONS:
        out.append(Migration(version=v, name=name, description=desc,
                             applied_at=applied.get(v)))
    return out


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("", response_model=dict)
async def status() -> dict:
    migs = _migration_status()
    applied = sum(1 for m in migs if m.applied_at)
    return {
        "total": len(migs),
        "applied": applied,
        "pending": len(migs) - applied,
        "migrations": [m.model_dump() for m in migs],
    }


@router.post("/apply", response_model=dict)
async def apply_pending(user: User = Depends(get_current_user)) -> dict:
    if user.role != "owner":
        raise HTTPException(403, {"code": "forbidden", "message": "Solo owner applica migrations"})

    applied_now = []
    skipped = []
    failed = []

    applied_set = _applied_versions()
    for version, name, desc, fn in MIGRATIONS:
        if version in applied_set:
            skipped.append(version)
            continue
        try:
            with tx() as t:
                fn(t)
                t.execute(
                    "INSERT INTO schema_migrations (version, name) VALUES (?, ?)",
                    (version, name),
                )
            applied_now.append(version)
        except Exception as e:
            failed.append({"version": version, "name": name, "error": str(e)})
            break  # ferma alla prima failure (no salti)

    return {
        "applied_now": applied_now,
        "skipped_already_applied": skipped,
        "failed": failed,
    }


# ─── Auto-apply at import time ───────────────────────────────────────
# Applica migrations pending al boot del server (best-effort, log errori).

def auto_apply_at_startup() -> None:
    try:
        _ensure_migrations_table()
        applied_set = _applied_versions()
        for version, name, _desc, fn in MIGRATIONS:
            if version in applied_set:
                continue
            try:
                with tx() as t:
                    fn(t)
                    t.execute(
                        "INSERT INTO schema_migrations (version, name) VALUES (?, ?)",
                        (version, name),
                    )
            except Exception:
                # Log warning ma non blocca avvio
                pass
    except Exception:
        pass
