"""L3 — EVENT BUS

Pub/sub interno per coordinare AI multiple e capabilities. Step 0: in-memory
asyncio queue + persistenza opzionale in DB per replay/audit. Step 2:
migrazione a Redis/NATS quando arrivano AI specialiste oltre GAVIO.

Modello eventi:
  topic       — gerarchia "dominio.azione" es. user.intent, system.alert,
                gavio.response, mesh.device_paired
  source      — chi emette (gavio, solem.api, mesh.pairing, extension.foo)
  payload     — dict JSON-serializzabile
  user_id     — utente associato (None per system-wide)

Endpoint:
  POST /events/publish              → pubblica evento
  GET  /events/stream?topic=...     → SSE stream live (long-polling)
  GET  /events/history?topic=...    → ultimi N eventi persistiti
"""
from __future__ import annotations

import asyncio
import json
from datetime import datetime, timezone
from typing import Any, AsyncIterator

from fastapi import APIRouter, Query
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from .db import get_conn, tx

router = APIRouter(prefix="/events", tags=["events"])

# Bus in-memory: lista di subscribers asyncio.Queue.
# Ogni publish broadcastea l'evento a tutte le queue attive.
_subscribers: list[asyncio.Queue] = []


# ─── Schemas ──────────────────────────────────────────────────────────


class Event(BaseModel):
    ts: str = Field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    source: str = Field(..., description="emittente (gavio, solem.api, mesh.*, extension.*)")
    topic: str = Field(..., description="gerarchia 'dominio.azione', es. user.intent")
    payload: dict[str, Any] = Field(default_factory=dict)
    user_id: str | None = None


class PublishResult(BaseModel):
    event_id: int
    delivered_to: int = Field(..., description="numero di subscribers che hanno ricevuto live")


# ─── Endpoints ────────────────────────────────────────────────────────


@router.post("/publish", response_model=PublishResult)
async def publish(ev: Event) -> PublishResult:
    """Pubblica evento. Salva in DB (per audit/replay) e broadcast ai subscribers live."""
    # 1. Persisti
    with tx() as t:
        cur = t.execute(
            "INSERT INTO events (user_id, source, topic, payload) VALUES (?, ?, ?, ?)",
            (ev.user_id, ev.source, ev.topic, json.dumps(ev.payload, ensure_ascii=False)),
        )
        event_id = cur.lastrowid

    # 2. Broadcast in-memory (non bloccante)
    delivered = 0
    for q in list(_subscribers):
        try:
            q.put_nowait(ev.model_dump())
            delivered += 1
        except asyncio.QueueFull:
            pass  # subscriber lento → skip
        except Exception:
            pass

    return PublishResult(event_id=event_id, delivered_to=delivered)


@router.get("/stream")
async def stream(
    topic: str | None = Query(None, description="filtro topic prefix (es. 'user.' matcha user.intent)"),
):
    """SSE stream live di eventi. Mantiene la connessione aperta finché client disconnect."""
    q: asyncio.Queue = asyncio.Queue(maxsize=100)
    _subscribers.append(q)

    async def gen() -> AsyncIterator[bytes]:
        try:
            # Heartbeat iniziale
            yield b": connected\n\n"
            while True:
                try:
                    ev = await asyncio.wait_for(q.get(), timeout=15.0)
                    if topic is None or ev.get("topic", "").startswith(topic):
                        yield f"data: {json.dumps(ev)}\n\n".encode("utf-8")
                except asyncio.TimeoutError:
                    # Heartbeat ogni 15s per tenere viva la connessione
                    yield b": ping\n\n"
        finally:
            if q in _subscribers:
                _subscribers.remove(q)

    return StreamingResponse(gen(), media_type="text/event-stream")


@router.get("/history", response_model=list[Event])
async def history(
    topic: str | None = None,
    limit: int = Query(100, ge=1, le=1000),
) -> list[Event]:
    """Ultimi N eventi persistiti, filtrabili per topic prefix."""
    c = get_conn()
    if topic:
        rows = c.execute(
            "SELECT ts, source, topic, payload, user_id FROM events WHERE topic LIKE ? ORDER BY ts DESC LIMIT ?",
            (topic + "%", limit),
        ).fetchall()
    else:
        rows = c.execute(
            "SELECT ts, source, topic, payload, user_id FROM events ORDER BY ts DESC LIMIT ?",
            (limit,),
        ).fetchall()
    return [
        Event(
            ts=r["ts"],
            source=r["source"],
            topic=r["topic"],
            payload=json.loads(r["payload"]),
            user_id=r["user_id"],
        )
        for r in rows
    ]
