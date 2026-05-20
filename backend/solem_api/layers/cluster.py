"""CLUSTER — distributed compute tra device dello stesso account SOLEM.

Single responsibility: SOLO registry device della mesh + routing
"chi ha il muscolo per eseguire questo task". Niente esecuzione (delega
a worker daemon su ogni nodo via llama.cpp RPC / SOLEM RPC).

Modello:
  - Ogni device paired (vedi /pairing) registra le sue capacità qui:
    cpu_cores, ram_gb, gpu (none|nvidia|amd|intel), gpu_vram_gb, load_pct
  - Ogni 30s ogni worker fa heartbeat con load live
  - GAVIO/SOLEM chiama POST /cluster/dispatch con task_kind + size_hint
    → ritorna l'endpoint del device migliore (può essere localhost)
  - Worker locale esegue + ritorna risultato

Esempio: GAVIO vuole inference su llama-70b → cluster.dispatch sceglie
il NVIDIA server (24 GB VRAM) invece del laptop (8 GB RAM, no GPU).
Se il server è offline, fallback al locale (modello più piccolo).

100% FOSS. Niente cloud, tutto sulla tua mesh WireGuard.
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

router = APIRouter(prefix="/cluster", tags=["cluster"])

REGISTRY_FILE = Path("/var/lib/solem/cluster.json")
HEARTBEAT_TTL_SEC = 90  # device offline se nessun beat per 90s


class GPUInfo(BaseModel):
    kind: Literal["none", "nvidia", "amd", "intel"] = "none"
    model: str | None = None
    vram_gb: float = 0.0


class DeviceCapabilities(BaseModel):
    cpu_cores: int = Field(..., ge=1)
    cpu_model: str = "?"
    ram_gb: float = Field(..., gt=0)
    disk_free_gb: float = 0
    gpu: GPUInfo = Field(default_factory=GPUInfo)
    arch: str = "x86_64"
    os: str = "linux"
    device_class: str = Field(
        "workstation",
        description="workstation|edge-cpu|edge-gpu|iot|glass-companion|mobile",
    )


class DeviceRegister(BaseModel):
    device_id: str = Field(..., min_length=4)
    name: str = Field(..., min_length=1)
    endpoint: str = Field(..., description="es. http://10.42.0.10:8001 (mesh-only)")
    capabilities: DeviceCapabilities
    roles: list[str] = Field(default_factory=lambda: ["worker"], description="worker|gateway|storage|gpu-server")


class DeviceHeartbeat(BaseModel):
    device_id: str
    load_pct: float = Field(..., ge=0, le=100, description="0..100, load CPU+GPU medio")
    ram_used_pct: float = Field(..., ge=0, le=100)
    gpu_used_pct: float = 0.0
    inflight_tasks: int = 0


class Device(BaseModel):
    device_id: str
    name: str
    endpoint: str
    capabilities: DeviceCapabilities
    roles: list[str]
    online: bool
    last_seen: str | None = None
    load_pct: float = 0
    ram_used_pct: float = 0
    gpu_used_pct: float = 0
    inflight_tasks: int = 0
    score: float = 0


class DispatchRequest(BaseModel):
    task_kind: Literal["llm_inference", "embedding", "stt", "tts", "vision", "generic_cpu", "generic_gpu"]
    size_hint: Literal["tiny", "small", "medium", "large", "xlarge"] = "small"
    requires_gpu: bool = False
    min_ram_gb: float = 0
    min_vram_gb: float = 0
    prefer_local: bool = Field(False, description="Se True, locale ha bonus score")


class DispatchResponse(BaseModel):
    device_id: str
    name: str
    endpoint: str
    reason: str
    score: float
    alternatives: list[Device] = Field(default_factory=list)


# ─── State ─────────────────────────────────────────────────────────────


def _load() -> dict:
    if not REGISTRY_FILE.exists():
        return {"devices": {}, "heartbeats": {}}
    try:
        return json.loads(REGISTRY_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        return {"devices": {}, "heartbeats": {}}


def _save(state: dict) -> None:
    REGISTRY_FILE.parent.mkdir(parents=True, exist_ok=True)
    REGISTRY_FILE.write_text(json.dumps(state, indent=2))


def _device_view(dev_id: str, state: dict) -> Device:
    d = state["devices"][dev_id]
    hb = state.get("heartbeats", {}).get(dev_id, {})
    last_ts = hb.get("ts", 0)
    online = (time.time() - last_ts) < HEARTBEAT_TTL_SEC
    return Device(
        device_id=dev_id,
        name=d["name"],
        endpoint=d["endpoint"],
        capabilities=DeviceCapabilities(**d["capabilities"]),
        roles=d.get("roles", ["worker"]),
        online=online,
        last_seen=(datetime.fromtimestamp(last_ts, tz=timezone.utc).isoformat() if last_ts else None),
        load_pct=hb.get("load_pct", 0),
        ram_used_pct=hb.get("ram_used_pct", 0),
        gpu_used_pct=hb.get("gpu_used_pct", 0),
        inflight_tasks=hb.get("inflight_tasks", 0),
    )


# ─── Scoring ───────────────────────────────────────────────────────────


SIZE_RAM_GB = {"tiny": 1, "small": 4, "medium": 8, "large": 16, "xlarge": 32}
SIZE_VRAM_GB = {"tiny": 0, "small": 2, "medium": 6, "large": 12, "xlarge": 24}


def _score(dev: Device, req: DispatchRequest) -> float:
    """Score più alto = device migliore per il task."""
    if not dev.online:
        return -1000.0

    cap = dev.capabilities
    ram_needed = max(req.min_ram_gb, SIZE_RAM_GB.get(req.size_hint, 4))
    vram_needed = max(req.min_vram_gb, SIZE_VRAM_GB.get(req.size_hint, 0)) if req.requires_gpu else 0

    if cap.ram_gb < ram_needed:
        return -1000.0
    if req.requires_gpu and cap.gpu.kind == "none":
        return -1000.0
    if vram_needed > 0 and cap.gpu.vram_gb < vram_needed:
        return -1000.0

    # Base: capacità - load
    score = 0.0
    score += cap.cpu_cores * 5
    score += cap.ram_gb * 3
    score += cap.gpu.vram_gb * 20 if req.requires_gpu else cap.gpu.vram_gb * 2
    score -= dev.load_pct * 2
    score -= dev.ram_used_pct * 1
    score -= dev.gpu_used_pct * 3
    score -= dev.inflight_tasks * 10

    # Bonus task-specific
    if req.task_kind == "llm_inference" and cap.gpu.kind != "none":
        score += 200
    if req.task_kind == "embedding" and cap.ram_gb >= 8:
        score += 50
    if req.task_kind in ("stt", "tts"):
        score += 30  # CPU-bound, ogni device va bene

    # ── Device class awareness (multi-arch) ──
    dc = getattr(cap, "device_class", "workstation")
    if dc == "workstation":
        score += 10  # bias verso workstation per workload pesanti
    elif dc == "edge-gpu":
        # Jetson Nano/Orin: bonus per vision/embedding leggeri
        if req.task_kind in ("vision", "embedding", "llm_inference") and req.size_hint in ("tiny", "small"):
            score += 50
        elif req.size_hint in ("large", "xlarge"):
            score -= 30  # troppo pesante per edge GPU
    elif dc == "edge-cpu":
        # Raspberry: penalizza task pesanti, premia STT/TTS/IoT
        if req.task_kind in ("stt", "tts") and req.size_hint == "tiny":
            score += 40
        if req.size_hint in ("medium", "large", "xlarge"):
            score -= 60  # mai task grandi su Pi
    elif dc == "iot":
        # IoT/Pico: solo sensor read e action minimali
        if req.size_hint != "tiny":
            score -= 200
    elif dc == "glass-companion" or dc == "mobile":
        # PWA mobile/glasses: solo task minimi (STT, comandi brevi)
        if req.task_kind in ("stt", "tts", "generic_cpu") and req.size_hint == "tiny":
            score += 20
        else:
            score -= 100  # raramente vogliamo dispatchare a un telefono/glass

    return score


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/health", response_model=dict)
async def cluster_health() -> dict:
    state = _load()
    devs = list(state["devices"].keys())
    online = sum(1 for d in devs if (time.time() - state.get("heartbeats", {}).get(d, {}).get("ts", 0)) < HEARTBEAT_TTL_SEC)
    return {
        "registry_file": str(REGISTRY_FILE),
        "total_devices": len(devs),
        "online_devices": online,
        "heartbeat_ttl_sec": HEARTBEAT_TTL_SEC,
        "policy": "FOSS, 100% mesh-local, no cloud coord",
    }


@router.post("/register", response_model=Device)
async def register(req: DeviceRegister) -> Device:
    state = _load()
    state["devices"][req.device_id] = {
        "name": req.name,
        "endpoint": req.endpoint,
        "capabilities": req.capabilities.model_dump(),
        "roles": req.roles,
        "registered_at": datetime.now(timezone.utc).isoformat(),
    }
    # Primo heartbeat implicito
    state.setdefault("heartbeats", {})[req.device_id] = {
        "ts": time.time(), "load_pct": 0, "ram_used_pct": 0, "gpu_used_pct": 0, "inflight_tasks": 0,
    }
    _save(state)
    return _device_view(req.device_id, state)


@router.post("/heartbeat", response_model=dict)
async def heartbeat(hb: DeviceHeartbeat) -> dict:
    state = _load()
    if hb.device_id not in state["devices"]:
        raise HTTPException(404, {"code": "device_not_registered", "hint": "call /cluster/register first"})
    state.setdefault("heartbeats", {})[hb.device_id] = {
        "ts": time.time(),
        "load_pct": hb.load_pct,
        "ram_used_pct": hb.ram_used_pct,
        "gpu_used_pct": hb.gpu_used_pct,
        "inflight_tasks": hb.inflight_tasks,
    }
    _save(state)
    return {"ok": True, "device_id": hb.device_id, "next_in_sec": HEARTBEAT_TTL_SEC // 3}


@router.get("/devices", response_model=list[Device])
async def list_devices() -> list[Device]:
    state = _load()
    return [_device_view(d, state) for d in state["devices"].keys()]


@router.delete("/devices/{device_id}")
async def remove_device(device_id: str) -> dict:
    state = _load()
    state["devices"].pop(device_id, None)
    state.get("heartbeats", {}).pop(device_id, None)
    _save(state)
    return {"removed": True, "device_id": device_id}


@router.post("/dispatch", response_model=DispatchResponse)
async def dispatch(req: DispatchRequest) -> DispatchResponse:
    """Sceglie il device migliore per il task. Niente esecuzione qui."""
    state = _load()
    devices = [_device_view(d, state) for d in state["devices"].keys()]
    if not devices:
        raise HTTPException(503, {"code": "no_devices_registered"})

    scored: list[tuple[float, Device]] = []
    for dev in devices:
        s = _score(dev, req)
        if req.prefer_local and "localhost" in dev.endpoint:
            s += 30
        dev.score = s
        scored.append((s, dev))

    scored.sort(key=lambda x: -x[0])

    if scored[0][0] < 0:
        raise HTTPException(503, {
            "code": "no_capable_device",
            "task": req.model_dump(),
            "devices_checked": len(devices),
        })

    best = scored[0][1]
    reasons = []
    cap = best.capabilities
    if cap.gpu.kind != "none" and req.requires_gpu:
        reasons.append(f"GPU {cap.gpu.kind} {cap.gpu.vram_gb}GB")
    reasons.append(f"{cap.cpu_cores}c/{cap.ram_gb}GB RAM")
    reasons.append(f"load {best.load_pct:.0f}%")
    if best.inflight_tasks > 0:
        reasons.append(f"{best.inflight_tasks} task in coda")

    return DispatchResponse(
        device_id=best.device_id,
        name=best.name,
        endpoint=best.endpoint,
        reason=" · ".join(reasons),
        score=round(best.score, 1),
        alternatives=[d for _, d in scored[1:6] if _ > 0],
    )


@router.get("/topology", response_model=dict)
async def topology() -> dict:
    """Riassunto risorse totali del cluster (somma device online)."""
    state = _load()
    devices = [_device_view(d, state) for d in state["devices"].keys() if _device_view(d, state).online]

    return {
        "online_devices": len(devices),
        "total_cpu_cores": sum(d.capabilities.cpu_cores for d in devices),
        "total_ram_gb": round(sum(d.capabilities.ram_gb for d in devices), 1),
        "total_vram_gb": round(sum(d.capabilities.gpu.vram_gb for d in devices), 1),
        "gpu_devices": sum(1 for d in devices if d.capabilities.gpu.kind != "none"),
        "by_role": {
            role: sum(1 for d in devices if role in d.roles)
            for role in {"worker", "gateway", "storage", "gpu-server"}
        },
        "devices": [d.model_dump() for d in devices],
    }
