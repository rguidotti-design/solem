"""ACTIVITY — log attività utente + AI recall (privacy-first).

Single responsibility: SOLO append-only log eventi + query semantica.
Niente screenshot/screen recording. Solo: app focus, window title hashed,
file path aperti, ricerche universal_search.

Privacy:
  - Tutto locale, mai uplodato
  - Window title hashato di default (privacy_mode = "hashed")
  - Modalità "off" disabilita TUTTO logging
  - L'utente può cancellare tutto via DELETE /activity

Endpoint:
  POST /activity/log       — append evento (chiamato da hyprland hook)
  GET  /activity/today     — eventi oggi
  POST /activity/recall    — "cosa ho fatto martedì alle 15?"
  GET  /activity/summary   — riassunto AI ultima settimana
  DELETE /activity         — wipe totale (panic)
"""
from __future__ import annotations

import hashlib
import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path

import httpx
from fastapi import APIRouter
from pydantic import BaseModel, Field

router = APIRouter(prefix="/activity", tags=["activity"])

ACTIVITY_DIR = Path("/var/lib/solem/activity")
SOLEM_URL = os.environ.get("SOLEM_INTERNAL_URL", "http://127.0.0.1:8001")
PRIVACY_MODE = os.environ.get("SOLEM_ACTIVITY_PRIVACY", "hashed")  # off|hashed|full


class ActivityEvent(BaseModel):
    ts: float = Field(default_factory=time.time)
    kind: str = Field(..., description="app_focus|file_open|search|command")
    payload: dict = Field(default_factory=dict)


class EventOut(BaseModel):
    iso_time: str
    kind: str
    payload: dict


class RecallRequest(BaseModel):
    question: str = Field(..., min_length=3)
    since_hours: int = Field(168, ge=1, le=720)


def _today_file() -> Path:
    ACTIVITY_DIR.mkdir(parents=True, exist_ok=True)
    return ACTIVITY_DIR / f"{datetime.now(timezone.utc).strftime('%Y-%m-%d')}.jsonl"


def _sanitize(payload: dict) -> dict:
    if PRIVACY_MODE == "off":
        return {}
    if PRIVACY_MODE == "full":
        return payload
    # hashed
    out: dict = {}
    for k, v in payload.items():
        if isinstance(v, str) and k in ("window_title", "file_path", "url"):
            out[f"{k}_hash"] = hashlib.sha256(v.encode()).hexdigest()[:12]
            out[k] = "<redacted>"
        else:
            out[k] = v
    return out


def _read_recent(hours: int) -> list[dict]:
    if not ACTIVITY_DIR.exists():
        return []
    cutoff = time.time() - hours * 3600
    events: list[dict] = []
    for f in sorted(ACTIVITY_DIR.glob("*.jsonl"), reverse=True):
        try:
            for line in f.read_text(encoding="utf-8", errors="replace").splitlines():
                try:
                    e = json.loads(line)
                    if e.get("ts", 0) >= cutoff:
                        events.append(e)
                except json.JSONDecodeError:
                    pass
        except OSError:
            pass
        if events and events[0].get("ts", 0) < cutoff - 86400:
            break
    return sorted(events, key=lambda e: e.get("ts", 0))


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/health", response_model=dict)
async def act_health() -> dict:
    return {
        "privacy_mode": PRIVACY_MODE,
        "activity_dir": str(ACTIVITY_DIR),
        "today_events": sum(1 for _ in _today_file().open()) if _today_file().exists() else 0,
    }


@router.post("/log", response_model=dict)
async def log_event(ev: ActivityEvent) -> dict:
    if PRIVACY_MODE == "off":
        return {"logged": False, "reason": "privacy_mode=off"}
    sanitized = ActivityEvent(ts=ev.ts, kind=ev.kind, payload=_sanitize(ev.payload))
    with _today_file().open("a", encoding="utf-8") as f:
        f.write(sanitized.model_dump_json() + "\n")
    return {"logged": True}


@router.get("/today", response_model=list[EventOut])
async def today() -> list[EventOut]:
    f = _today_file()
    if not f.exists():
        return []
    out: list[EventOut] = []
    for line in f.read_text(encoding="utf-8", errors="replace").splitlines():
        try:
            e = json.loads(line)
            out.append(EventOut(
                iso_time=datetime.fromtimestamp(e["ts"], tz=timezone.utc).isoformat(),
                kind=e["kind"],
                payload=e.get("payload", {}),
            ))
        except (json.JSONDecodeError, KeyError):
            continue
    return out


@router.post("/recall", response_model=dict)
async def recall(req: RecallRequest) -> dict:
    events = _read_recent(req.since_hours)
    if not events:
        return {"answer": "Nessuna attività registrata nel periodo.", "events_searched": 0}

    # Aggregate per giorno
    by_day: dict[str, list[dict]] = {}
    for e in events:
        day = datetime.fromtimestamp(e["ts"], tz=timezone.utc).strftime("%Y-%m-%d")
        by_day.setdefault(day, []).append(e)

    summary_lines: list[str] = []
    for day, evs in sorted(by_day.items())[-7:]:
        kinds = {}
        for e in evs:
            kinds[e["kind"]] = kinds.get(e["kind"], 0) + 1
        summary_lines.append(f"{day}: " + ", ".join(f"{k}×{v}" for k, v in kinds.items()))

    context = "\n".join(summary_lines)
    prompt = (
        f"Activity log della settimana (timestamp aggregati per giorno e tipo evento):\n{context}\n\n"
        f"Question: {req.question}\n\n"
        "Rispondi in italiano basandoti SOLO sul log. Se i dati non bastano dillo."
    )

    try:
        async with httpx.AsyncClient(timeout=60.0) as c:
            r = await c.post(
                f"{SOLEM_URL}/solem/ai/route",
                json={"messages": [{"role": "user", "content": prompt}], "hint": "auto", "max_tokens": 600},
            )
            if r.status_code != 200:
                return {"answer": "AI router non disponibile.", "events_searched": len(events)}
            answer = r.json().get("content", "")
    except httpx.HTTPError:
        return {"answer": "AI router non raggiungibile.", "events_searched": len(events)}

    return {
        "answer": answer,
        "events_searched": len(events),
        "days_covered": len(by_day),
    }


@router.delete("")
async def wipe_all() -> dict:
    """Panic delete: cancella TUTTO il log attività."""
    if not ACTIVITY_DIR.exists():
        return {"deleted": 0}
    deleted = 0
    for f in ACTIVITY_DIR.glob("*.jsonl"):
        f.unlink()
        deleted += 1
    return {"deleted": deleted}
