"""CLUSTER MIGRATION — job migration live tra device del cluster.

Single responsibility: SOLO tracking task running + re-dispatch quando il
device su cui giravano va offline. Niente checkpoint state (delega
all'esecutore: il task DEVE essere idempotente o riavviabile).

Modello Erlang-style:
  - Quando un task viene dispatched, registriamo task_id + device_id + payload
  - Heartbeat task ogni 15s da chi lo esegue (status "running")
  - Se device_id offline (no heartbeat per > 60s) → task marcato "orphaned"
  - Re-dispatch automatico via /cluster/dispatch verso un altro device
  - Notifica al client originale via SSE

Limitazione esplicita: SOLEM non fa checkpointing process state. Solo
re-dispatch idempotente. Il task DEVE:
  - essere ripetibile (es. inference LLM stesso prompt → stesso output ok)
  - oppure salvare progress lui stesso (es. cron job che ripartisce da N)

Endpoint:
  POST /migration/register   — task viene assegnato a un device
  POST /migration/heartbeat  — il device esecutore conferma "vivo"
  POST /migration/complete   — task terminato (success/fail)
  GET  /migration/active     — task running
  GET  /migration/orphaned   — task che hanno perso il device
  POST /migration/sweep      — scansiona + re-dispatch orphaned (chiamato da timer)
"""
from __future__ import annotations

import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/migration", tags=["cluster-migration"])

STATE_FILE = Path("/var/lib/solem/cluster_migration.json")
SOLEM_URL = os.environ.get("SOLEM_INTERNAL_URL", "http://127.0.0.1:8001")
HEARTBEAT_TTL_SEC = 60       # task orphaned se nessun beat per 60s
TASK_TIMEOUT_SEC = 1800      # 30 min max per task


class TaskRegister(BaseModel):
    task_id: str = Field(..., min_length=4)
    task_kind: Literal["llm_inference", "embedding", "stt", "tts", "vision",
                       "generic_cpu", "generic_gpu"] = "generic_cpu"
    device_id: str
    payload: dict = Field(default_factory=dict)
    size_hint: Literal["tiny", "small", "medium", "large", "xlarge"] = "small"
    requires_gpu: bool = False


class TaskHeartbeat(BaseModel):
    task_id: str
    device_id: str
    progress_pct: float = Field(0.0, ge=0.0, le=100.0)


class TaskComplete(BaseModel):
    task_id: str
    device_id: str
    success: bool
    result_summary: str = ""


class TaskRecord(BaseModel):
    task_id: str
    task_kind: str
    current_device: str
    original_device: str
    payload: dict
    size_hint: str
    requires_gpu: bool
    state: Literal["running", "orphaned", "migrated", "done", "failed"]
    started_at: float
    last_heartbeat: float
    progress_pct: float = 0.0
    migrations: list[dict] = Field(default_factory=list)


# ─── State persistence ────────────────────────────────────────────────


def _load() -> dict:
    if not STATE_FILE.exists():
        return {"tasks": {}}
    try:
        return json.loads(STATE_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        return {"tasks": {}}


def _save(state: dict) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=2))


def _to_record(d: dict) -> TaskRecord:
    return TaskRecord(**d)


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/health", response_model=dict)
async def mig_health() -> dict:
    state = _load()
    counts: dict[str, int] = {}
    for t in state["tasks"].values():
        s = t.get("state", "?")
        counts[s] = counts.get(s, 0) + 1
    return {
        "state_file": str(STATE_FILE),
        "heartbeat_ttl_sec": HEARTBEAT_TTL_SEC,
        "task_timeout_sec": TASK_TIMEOUT_SEC,
        "tasks_by_state": counts,
    }


@router.post("/register", response_model=TaskRecord)
async def register_task(req: TaskRegister) -> TaskRecord:
    state = _load()
    now = time.time()
    rec = {
        "task_id": req.task_id,
        "task_kind": req.task_kind,
        "current_device": req.device_id,
        "original_device": req.device_id,
        "payload": req.payload,
        "size_hint": req.size_hint,
        "requires_gpu": req.requires_gpu,
        "state": "running",
        "started_at": now,
        "last_heartbeat": now,
        "progress_pct": 0.0,
        "migrations": [],
    }
    state["tasks"][req.task_id] = rec
    _save(state)
    return _to_record(rec)


@router.post("/heartbeat", response_model=dict)
async def heartbeat_task(req: TaskHeartbeat) -> dict:
    state = _load()
    if req.task_id not in state["tasks"]:
        raise HTTPException(404, {"code": "task_not_registered"})
    rec = state["tasks"][req.task_id]
    rec["last_heartbeat"] = time.time()
    rec["progress_pct"] = req.progress_pct
    rec["current_device"] = req.device_id  # in caso di migration nel mezzo
    if rec["state"] == "orphaned":
        rec["state"] = "running"  # task ripreso da un altro device
    _save(state)
    return {"ok": True, "task_id": req.task_id, "state": rec["state"]}


@router.post("/complete", response_model=dict)
async def complete_task(req: TaskComplete) -> dict:
    state = _load()
    if req.task_id not in state["tasks"]:
        raise HTTPException(404, {"code": "task_not_registered"})
    rec = state["tasks"][req.task_id]
    rec["state"] = "done" if req.success else "failed"
    rec["last_heartbeat"] = time.time()
    rec["result_summary"] = req.result_summary
    _save(state)
    return {"ok": True, "task_id": req.task_id, "final_state": rec["state"]}


@router.get("/active", response_model=list[TaskRecord])
async def list_active() -> list[TaskRecord]:
    state = _load()
    return [_to_record(t) for t in state["tasks"].values() if t["state"] == "running"]


@router.get("/orphaned", response_model=list[TaskRecord])
async def list_orphaned() -> list[TaskRecord]:
    state = _load()
    return [_to_record(t) for t in state["tasks"].values() if t["state"] == "orphaned"]


@router.post("/sweep", response_model=dict)
async def sweep() -> dict:
    """Scansiona tutti i task running:
      - se last_heartbeat > HEARTBEAT_TTL_SEC → marca orphaned
      - per ogni orphaned, prova re-dispatch via /cluster/dispatch
      - se trova un nuovo device, aggiorna current_device e logga migration

    Chiamato dal timer systemd ogni 30s.
    """
    state = _load()
    now = time.time()
    marked_orphaned = 0
    migrated = 0
    timed_out = 0

    for tid, t in state["tasks"].items():
        if t["state"] not in ("running", "orphaned"):
            continue

        # Timeout assoluto
        if (now - t["started_at"]) > TASK_TIMEOUT_SEC:
            t["state"] = "failed"
            t["result_summary"] = "TIMEOUT"
            timed_out += 1
            continue

        # Check orphaned
        if (now - t["last_heartbeat"]) > HEARTBEAT_TTL_SEC and t["state"] == "running":
            t["state"] = "orphaned"
            marked_orphaned += 1

        # Re-dispatch orphaned
        if t["state"] == "orphaned":
            try:
                async with httpx.AsyncClient(timeout=5.0) as c:
                    r = await c.post(
                        f"{SOLEM_URL}/solem/cluster/dispatch",
                        json={
                            "task_kind": t["task_kind"],
                            "size_hint": t["size_hint"],
                            "requires_gpu": t["requires_gpu"],
                        },
                    )
                    if r.status_code == 200:
                        new_dev = r.json().get("device_id")
                        if new_dev and new_dev != t["current_device"]:
                            t["migrations"].append({
                                "from": t["current_device"],
                                "to": new_dev,
                                "at": datetime.now(timezone.utc).isoformat(),
                            })
                            t["current_device"] = new_dev
                            t["state"] = "migrated"
                            t["last_heartbeat"] = now
                            migrated += 1
            except httpx.HTTPError:
                pass

    _save(state)
    return {
        "swept": True,
        "marked_orphaned": marked_orphaned,
        "migrated": migrated,
        "timed_out": timed_out,
    }


@router.get("/{task_id}", response_model=TaskRecord)
async def get_task(task_id: str) -> TaskRecord:
    state = _load()
    if task_id not in state["tasks"]:
        raise HTTPException(404, {"code": "task_not_found"})
    return _to_record(state["tasks"][task_id])
