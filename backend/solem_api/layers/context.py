"""L2 — CONTEXT ENGINE

Stato attuale di cosa l'utente sta facendo: dove, quando, con quale device,
in quale ruolo, su quale task. Snapshot persistenti ogni 5 minuti (o
on-demand via push esplicito).

Modello a 4 livelli (spec founder):
  1. Fisico        — location, device, ora
  2. Comportamentale — apps_open, current_task, thread_id
  3. Identitario   — active_role (link a L1 Identity)
  4. Predittivo    — emotional_state, deduzioni da pattern (Step 3+)

Endpoint:
  GET  /context/now             → ultimo snapshot disponibile + deduzioni live
  POST /context/snapshot        → push manuale snapshot (da device client)
  GET  /context/history         → cronologia snapshot (ultimi 50)
"""
from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field

from .db import get_conn, tx

router = APIRouter(prefix="/context", tags=["context"])

DEFAULT_USER_ID = "00000000-0000-0000-0000-000000000001"


# ─── Schemas ──────────────────────────────────────────────────────────


class ContextSnapshot(BaseModel):
    user_id: str = DEFAULT_USER_ID
    ts: str = Field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    location: str | None = Field(None, description="es. 'casa', 'ufficio', coordinate, BSSID WiFi")
    device_id: str | None = None
    active_role: str | None = None
    current_task: str | None = None
    apps_open: list[str] = Field(default_factory=list)
    thread_id: str | None = None
    emotional_state: str | None = None


class ContextNow(ContextSnapshot):
    """Snapshot ultimo + arricchimenti server-side (uptime, ora UTC, ecc.)."""
    server_ts: str
    seconds_since_snapshot: int


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/now", response_model=ContextNow)
async def context_now() -> ContextNow:
    """Stato attuale: ultimo snapshot disponibile + delta tempo dal server."""
    c = get_conn()
    row = c.execute(
        """SELECT * FROM context_snapshots
           WHERE user_id = ?
           ORDER BY ts DESC LIMIT 1""",
        (DEFAULT_USER_ID,),
    ).fetchone()

    now_utc = datetime.now(timezone.utc)
    if row is None:
        # Nessuno snapshot ancora: ritorna struttura vuota con timestamp server
        return ContextNow(
            ts=now_utc.isoformat(),
            server_ts=now_utc.isoformat(),
            seconds_since_snapshot=0,
        )

    snapshot_ts = datetime.fromisoformat(row["ts"].replace(" ", "T")).replace(tzinfo=timezone.utc)
    delta = int((now_utc - snapshot_ts).total_seconds())

    apps = json.loads(row["apps_open"]) if row["apps_open"] else []

    return ContextNow(
        user_id=row["user_id"],
        ts=row["ts"],
        location=row["location"],
        device_id=row["device_id"],
        active_role=row["active_role"],
        current_task=row["current_task"],
        apps_open=apps,
        thread_id=row["thread_id"],
        emotional_state=row["emotional_state"],
        server_ts=now_utc.isoformat(),
        seconds_since_snapshot=delta,
    )


@router.post("/snapshot", response_model=ContextSnapshot, status_code=201)
async def push_snapshot(snap: ContextSnapshot) -> ContextSnapshot:
    """Inserisce un nuovo snapshot. Chiamato dal cron 5min o da device client."""
    with tx() as t:
        cur = t.execute(
            """INSERT INTO context_snapshots
               (user_id, location, device_id, active_role, current_task,
                apps_open, thread_id, emotional_state)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                snap.user_id or DEFAULT_USER_ID,
                snap.location,
                snap.device_id,
                snap.active_role,
                snap.current_task,
                json.dumps(snap.apps_open),
                snap.thread_id,
                snap.emotional_state,
            ),
        )
        new_id = cur.lastrowid

    row = get_conn().execute(
        "SELECT * FROM context_snapshots WHERE id = ?", (new_id,)
    ).fetchone()
    return ContextSnapshot(
        user_id=row["user_id"],
        ts=row["ts"],
        location=row["location"],
        device_id=row["device_id"],
        active_role=row["active_role"],
        current_task=row["current_task"],
        apps_open=json.loads(row["apps_open"]) if row["apps_open"] else [],
        thread_id=row["thread_id"],
        emotional_state=row["emotional_state"],
    )


@router.get("/history", response_model=list[ContextSnapshot])
async def history(limit: int = Query(50, ge=1)) -> list[ContextSnapshot]:
    """Ultimi N snapshot per analisi pattern. Clamp a 500 lato server."""
    limit = min(limit, 500)
    c = get_conn()
    rows = c.execute(
        """SELECT * FROM context_snapshots
           WHERE user_id = ?
           ORDER BY ts DESC, id DESC LIMIT ?""",
        (DEFAULT_USER_ID, limit),
    ).fetchall()
    return [
        ContextSnapshot(
            user_id=r["user_id"],
            ts=r["ts"],
            location=r["location"],
            device_id=r["device_id"],
            active_role=r["active_role"],
            current_task=r["current_task"],
            apps_open=json.loads(r["apps_open"]) if r["apps_open"] else [],
            thread_id=r["thread_id"],
            emotional_state=r["emotional_state"],
        )
        for r in rows
    ]
