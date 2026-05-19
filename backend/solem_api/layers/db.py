"""SOLEM Backend — connessione SQLite condivisa tra i layer.

Step 0: SQLite locale in /var/lib/solem/solem.db (single-file, zero-deps).
Step 2: migrazione opzionale a Supabase Postgres (stesso schema multi-tenant).

Schema multi-tenant by design: ogni tabella ha colonna `user_id` (UUID)
anche se Step 0 ha un solo utente. Quando arriverà multi-tenant si abilita
solo il filtro per-user.
"""
from __future__ import annotations

import os
import sqlite3
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

# Path DB: var/lib/solem in produzione (creato da systemd-tmpfiles),
# fallback locale per dev (es. test fuori dalla VM).
DB_PATH = Path(os.environ.get("SOLEM_DB_PATH", "/var/lib/solem/solem.db"))

# Singleton connection: SQLite supporta multi-thread con check_same_thread=False
_conn: sqlite3.Connection | None = None


def get_conn() -> sqlite3.Connection:
    """Connessione globale al DB SOLEM. Crea schema al primo accesso."""
    global _conn
    if _conn is not None:
        return _conn

    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    _conn = sqlite3.connect(
        str(DB_PATH),
        check_same_thread=False,
        isolation_level=None,  # autocommit; transazioni esplicite con BEGIN
    )
    _conn.row_factory = sqlite3.Row
    _conn.execute("PRAGMA journal_mode = WAL;")
    _conn.execute("PRAGMA foreign_keys = ON;")
    _conn.execute("PRAGMA busy_timeout = 5000;")

    _init_schema(_conn)
    return _conn


def _init_schema(c: sqlite3.Connection) -> None:
    """Crea tutte le tabelle se non esistono. Idempotente."""
    c.executescript("""
    -- ─── USERS + SESSIONS (multi-tenant Step 0 con 1 user, Step 4 attivato) ─
    CREATE TABLE IF NOT EXISTS users (
        user_id      TEXT PRIMARY KEY,         -- UUID
        username     TEXT UNIQUE NOT NULL,
        email        TEXT UNIQUE NOT NULL,
        password_hash TEXT,                    -- argon2/bcrypt; NULL = OAuth-only (Step 2+)
        role         TEXT NOT NULL DEFAULT 'user' CHECK(role IN ('owner','user','readonly')),
        created_at   TEXT NOT NULL DEFAULT (datetime('now')),
        last_login   TEXT,
        is_active    INTEGER NOT NULL DEFAULT 1
    );

    CREATE TABLE IF NOT EXISTS sessions (
        token        TEXT PRIMARY KEY,         -- random 32-byte URL-safe
        user_id      TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
        created_at   TEXT NOT NULL DEFAULT (datetime('now')),
        expires_at   TEXT NOT NULL,
        last_used    TEXT,
        ip           TEXT,
        user_agent   TEXT,
        revoked_at   TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);
    CREATE INDEX IF NOT EXISTS idx_sessions_expires ON sessions(expires_at);

    -- ─── L1 IDENTITY ENGINE ──────────────────────────────────────────
    CREATE TABLE IF NOT EXISTS identities (
        user_id        TEXT PRIMARY KEY,
        name           TEXT NOT NULL,
        email          TEXT NOT NULL,
        created_at     TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at     TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS identity_sections (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id        TEXT NOT NULL REFERENCES identities(user_id) ON DELETE CASCADE,
        section_key    TEXT NOT NULL,   -- es. roles, values, goals, routine, persone, custom_*
        content        TEXT NOT NULL,   -- JSON serializzato
        version        INTEGER NOT NULL DEFAULT 1,
        updated_at     TEXT NOT NULL DEFAULT (datetime('now')),
        UNIQUE(user_id, section_key)
    );

    CREATE INDEX IF NOT EXISTS idx_identity_sections_user
        ON identity_sections(user_id);

    -- ─── L2 CONTEXT ENGINE ───────────────────────────────────────────
    CREATE TABLE IF NOT EXISTS context_snapshots (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id         TEXT NOT NULL,
        ts              TEXT NOT NULL DEFAULT (datetime('now')),
        location        TEXT,
        device_id       TEXT,
        active_role     TEXT,
        current_task    TEXT,
        apps_open       TEXT,  -- JSON array
        thread_id       TEXT,
        emotional_state TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_context_user_ts
        ON context_snapshots(user_id, ts DESC);

    -- ─── L3 EVENT BUS (persistenza opzionale eventi) ─────────────────
    CREATE TABLE IF NOT EXISTS events (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        ts          TEXT NOT NULL DEFAULT (datetime('now')),
        user_id     TEXT,
        source      TEXT NOT NULL,    -- es. gavio, solem.api, mesh.pairing
        topic       TEXT NOT NULL,    -- es. user.intent, system.alert
        payload     TEXT NOT NULL     -- JSON serializzato
    );

    CREATE INDEX IF NOT EXISTS idx_events_topic_ts
        ON events(topic, ts DESC);

    -- ─── L5 MEMORY (3 livelli) ──────────────────────────────────────
    -- Livello A: interazioni con SOLEM/GAVIO
    CREATE TABLE IF NOT EXISTS solem_memory (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id     TEXT NOT NULL,
        source      TEXT NOT NULL,    -- chat, decision, idea, task, identity_change, wiki_entry
        content     TEXT NOT NULL,
        embedding   BLOB,             -- vector float32[1536] o NULL se non ancora calcolato
        metadata    TEXT,             -- JSON
        importance  REAL DEFAULT 0.5, -- 0-1 calcolato da LLM
        created_at  TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE INDEX IF NOT EXISTS idx_solem_memory_user_ts
        ON solem_memory(user_id, created_at DESC);

    -- Livello B: universo esterno dell'utente (catturato con permesso)
    CREATE TABLE IF NOT EXISTS user_universe_memory (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id         TEXT NOT NULL,
        source_type     TEXT NOT NULL,    -- email, calendar, file, photo, browser
        source_id       TEXT NOT NULL,
        content         TEXT NOT NULL,
        embedding       BLOB,
        metadata        TEXT,
        privacy_level   TEXT CHECK(privacy_level IN ('public','work','personal','sacred')) DEFAULT 'personal',
        captured_at     TEXT NOT NULL DEFAULT (datetime('now')),
        original_ts     TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_universe_user_type
        ON user_universe_memory(user_id, source_type);

    -- ─── PAIRING (sostituisce dict in-memory di main.py) ─────────────
    CREATE TABLE IF NOT EXISTS paired_devices (
        device_id    TEXT PRIMARY KEY,
        user_id      TEXT NOT NULL,
        name         TEXT NOT NULL,
        wg_pubkey    TEXT NOT NULL,
        assigned_ip  TEXT NOT NULL,
        paired_at    TEXT NOT NULL DEFAULT (datetime('now')),
        last_seen    TEXT,
        revoked_at   TEXT
    );
    """)


@contextmanager
def tx() -> Iterator[sqlite3.Connection]:
    """Transazione esplicita: BEGIN/COMMIT, ROLLBACK su eccezione."""
    c = get_conn()
    c.execute("BEGIN")
    try:
        yield c
        c.execute("COMMIT")
    except Exception:
        c.execute("ROLLBACK")
        raise


def close() -> None:
    """Chiude il singleton (per teardown test)."""
    global _conn
    if _conn:
        _conn.close()
        _conn = None
