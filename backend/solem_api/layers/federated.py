"""FEDERATED — scaffold federated learning con Flower (FOSS).

Single responsibility: SOLO API per partecipare/coordinare round di
federated learning. Niente training reale (delegato a Flower client).

ADR-016 → privacy by design. Gradients ε-DP prima dell'invio, mai dati
raw. Opt-in esplicito per round; default off.

Endpoint:
  GET  /federated/status      — stato partecipazione (opt-in?)
  POST /federated/opt-in      — registra device come participant
  POST /federated/opt-out     — esce dal pool
  GET  /federated/rounds      — round storici partecipati
  POST /federated/round/start — coordinator: avvia round (admin only)

Step 0: scaffold. flwr deps richiede `python312Packages.flwr` in
solem-api.nix pyDeps (da aggiungere quando attivato).
"""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/federated", tags=["federated"])

STATE_FILE = Path("/var/lib/solem/federated.json")


class FederatedStatus(BaseModel):
    opted_in: bool
    device_id: str | None = None
    rounds_participated: int = 0
    last_round_at: str | None = None
    dp_epsilon: float = Field(1.0, description="Differential privacy budget")
    coordinator: str | None = None


class OptInRequest(BaseModel):
    device_id: str = Field(..., min_length=8)
    coordinator_url: str = Field(..., description="es. https://federated.solem.local")
    dp_epsilon: float = Field(1.0, ge=0.1, le=10.0)


class RoundRecord(BaseModel):
    round_id: str
    started_at: str
    finished_at: str | None = None
    local_examples: int
    upload_bytes: int
    coordinator: str


# ─── State persistence ────────────────────────────────────────────────


def _load_state() -> dict:
    if not STATE_FILE.exists():
        return {"opted_in": False, "rounds": []}
    try:
        return json.loads(STATE_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        return {"opted_in": False, "rounds": []}


def _save_state(state: dict) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=2))


# ─── Flower lazy import ───────────────────────────────────────────────


def _get_flwr():
    try:
        import flwr
        return flwr
    except ImportError:
        return None


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/status", response_model=FederatedStatus)
async def status() -> FederatedStatus:
    state = _load_state()
    rounds = state.get("rounds", [])
    return FederatedStatus(
        opted_in=state.get("opted_in", False),
        device_id=state.get("device_id"),
        rounds_participated=len(rounds),
        last_round_at=rounds[-1]["started_at"] if rounds else None,
        dp_epsilon=state.get("dp_epsilon", 1.0),
        coordinator=state.get("coordinator"),
    )


@router.post("/opt-in", response_model=FederatedStatus)
async def opt_in(req: OptInRequest) -> FederatedStatus:
    state = _load_state()
    state.update({
        "opted_in": True,
        "device_id": req.device_id,
        "coordinator": req.coordinator_url,
        "dp_epsilon": req.dp_epsilon,
        "opted_in_at": datetime.now(timezone.utc).isoformat(),
    })
    _save_state(state)
    return await status()


@router.post("/opt-out", response_model=FederatedStatus)
async def opt_out() -> FederatedStatus:
    state = _load_state()
    state["opted_in"] = False
    state["opted_out_at"] = datetime.now(timezone.utc).isoformat()
    _save_state(state)
    return await status()


@router.get("/rounds", response_model=list[RoundRecord])
async def list_rounds() -> list[RoundRecord]:
    state = _load_state()
    return [RoundRecord(**r) for r in state.get("rounds", [])]


@router.get("/health", response_model=dict)
async def federated_health() -> dict:
    flwr = _get_flwr()
    return {
        "flwr_available": flwr is not None,
        "flwr_version": getattr(flwr, "__version__", None) if flwr else None,
        "state_file": str(STATE_FILE),
        "step": "scaffold (Step 0) — installa python312Packages.flwr per attivare",
    }
