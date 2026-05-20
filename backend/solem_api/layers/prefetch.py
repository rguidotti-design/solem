"""PREFETCH — routine learning: GAVIO prepara il sistema in anticipo.

Single responsibility: SOLO osservare pattern temporali di uso (apri X
ogni giorno alle 09:00) e PRE-CARICARE risorse (modello LLM, embedding,
app) prima che servano.

Algoritmo (minimo):
  - log_event(kind, tag) appende eventi con timestamp
  - hourly_aggregate() conta eventi per (hour_of_day, weekday, tag)
  - predict_next(now) ritorna tag con probabilità per i prossimi 60 min
  - prefetch_actions() trasforma predizione in azioni concrete
    (es. "ollama pull qwen-coder", "systemctl start logseq")

Tutto deterministico, niente ML autonomo. La "smartness" è statistica.
"""
from __future__ import annotations

import json
import time
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path

from fastapi import APIRouter
from pydantic import BaseModel, Field

router = APIRouter(prefix="/prefetch", tags=["prefetch"])

EVENTS_FILE = Path("/var/lib/solem/prefetch_events.jsonl")
MAX_EVENTS = 10_000  # cap


class LogEvent(BaseModel):
    kind: str = Field(..., description="app_open|file_open|task_start|...")
    tag: str = Field(..., description="es. 'logseq', 'firefox', 'ollama:qwen-coder'")
    weight: float = Field(1.0, ge=0)


class Prediction(BaseModel):
    tag: str
    score: float
    next_likely_time_iso: str | None = None
    history_count: int


class PrefetchPlan(BaseModel):
    horizon_min: int
    predictions: list[Prediction]
    suggested_actions: list[str]


def _append(ev: LogEvent) -> None:
    EVENTS_FILE.parent.mkdir(parents=True, exist_ok=True)
    line = json.dumps({"ts": time.time(), **ev.model_dump()})
    with EVENTS_FILE.open("a", encoding="utf-8") as f:
        f.write(line + "\n")
    # Truncate quando troppo grande
    lines = EVENTS_FILE.read_text(encoding="utf-8").splitlines()
    if len(lines) > MAX_EVENTS:
        EVENTS_FILE.write_text("\n".join(lines[-MAX_EVENTS:]) + "\n", encoding="utf-8")


def _read_events() -> list[dict]:
    if not EVENTS_FILE.exists():
        return []
    out = []
    for line in EVENTS_FILE.read_text(encoding="utf-8").splitlines():
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return out


def _bucket_match(events: list[dict], target_hour: int, target_wday: int,
                  window_hours: int = 1) -> Counter:
    """Conta tag negli eventi che cadono in (hour ± window) e weekday match."""
    c: Counter = Counter()
    for e in events:
        try:
            dt = datetime.fromtimestamp(e["ts"], tz=timezone.utc).astimezone()
        except (KeyError, ValueError, OverflowError):
            continue
        if dt.weekday() != target_wday:
            continue
        diff = abs(dt.hour - target_hour)
        if diff > window_hours and (24 - diff) > window_hours:
            continue
        c[e.get("tag", "?")] += e.get("weight", 1.0)
    return c


@router.get("/health", response_model=dict)
async def prefetch_health() -> dict:
    events = _read_events()
    return {
        "total_events": len(events),
        "events_file": str(EVENTS_FILE),
        "policy": "statistical hour-of-day + weekday matching, no ML",
    }


@router.post("/log", response_model=dict)
async def log_event(ev: LogEvent) -> dict:
    _append(ev)
    return {"logged": True}


@router.get("/predict", response_model=list[Prediction])
async def predict(horizon_min: int = 60) -> list[Prediction]:
    events = _read_events()
    if len(events) < 10:
        return []

    now = datetime.now().astimezone()
    target = now + timedelta(minutes=horizon_min)
    counter = _bucket_match(events, target.hour, target.weekday(), window_hours=1)

    total = sum(counter.values())
    if total == 0:
        return []

    out: list[Prediction] = []
    for tag, count in counter.most_common(10):
        out.append(Prediction(
            tag=tag,
            score=round(count / total, 3),
            next_likely_time_iso=target.replace(minute=0, second=0, microsecond=0).isoformat(),
            history_count=int(count),
        ))
    return out


@router.get("/plan", response_model=PrefetchPlan)
async def plan(horizon_min: int = 60) -> PrefetchPlan:
    """Predizioni + azioni concrete suggerite (NON eseguite automaticamente)."""
    preds = await predict(horizon_min)
    actions: list[str] = []
    for p in preds:
        if p.score < 0.15:
            continue
        if p.tag.startswith("ollama:"):
            actions.append(f"ollama pull {p.tag.split(':',1)[1]}  # probabile uso fra {horizon_min} min")
        elif p.tag.startswith("app:"):
            actions.append(f"systemctl --user start {p.tag.split(':',1)[1]}.service  # pre-warm")
        elif p.tag.startswith("file:"):
            actions.append(f"# scalda page cache: head -c 1M {p.tag.split(':',1)[1]}")
        else:
            actions.append(f"# probabile: {p.tag}")
    return PrefetchPlan(horizon_min=horizon_min, predictions=preds, suggested_actions=actions)


@router.delete("/events")
async def wipe_events() -> dict:
    """Reset completo (privacy)."""
    if EVENTS_FILE.exists():
        EVENTS_FILE.unlink()
    return {"wiped": True}
