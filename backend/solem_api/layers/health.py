"""HEALTH DEEP — diagnostica approfondita per liveness/readiness.

Endpoint:
  GET /health/deep         — check DB + ollama + gavio + disk + memory
  GET /health/ready        — readiness probe (per k8s/load balancer)
  GET /health/live         — liveness probe (sempre 200 se processo gira)
"""
from __future__ import annotations

import shutil
from pathlib import Path
from typing import Literal

import httpx
from fastapi import APIRouter, Response
from pydantic import BaseModel

from .db import get_conn

router = APIRouter(prefix="/health", tags=["meta"])


class HealthCheck(BaseModel):
    component: str
    status: Literal["ok", "degraded", "down"]
    detail: str = ""


class DeepHealthResponse(BaseModel):
    overall: Literal["ok", "degraded", "down"]
    checks: list[HealthCheck]


@router.get("/live", response_model=dict)
async def live() -> dict:
    """Liveness — sempre 200 se il processo solem-api risponde."""
    return {"alive": True}


@router.get("/ready", response_model=dict)
async def ready(response: Response) -> dict:
    """Readiness — 200 se DB raggiungibile, altrimenti 503."""
    try:
        get_conn().execute("SELECT 1").fetchone()
        return {"ready": True}
    except Exception as e:
        response.status_code = 503
        return {"ready": False, "error": str(e)}


@router.get("/deep", response_model=DeepHealthResponse)
async def deep(response: Response) -> DeepHealthResponse:
    """Check approfondito: DB schema + ollama + gavio + disk + memory."""
    checks: list[HealthCheck] = []

    # DB SQLite + schema
    try:
        c = get_conn()
        tables = [r[0] for r in c.execute(
            "SELECT name FROM sqlite_master WHERE type='table'"
        ).fetchall()]
        expected = {"identities", "context_snapshots", "events", "solem_memory", "users"}
        missing = expected - set(tables)
        if missing:
            checks.append(HealthCheck(component="db.schema", status="degraded",
                                      detail=f"missing tables: {missing}"))
        else:
            checks.append(HealthCheck(component="db.schema", status="ok",
                                      detail=f"{len(tables)} tables"))
    except Exception as e:
        checks.append(HealthCheck(component="db.schema", status="down", detail=str(e)))

    # Ollama API
    try:
        async with httpx.AsyncClient(timeout=2.0) as c:
            r = await c.get("http://127.0.0.1:11434/api/version")
            if r.status_code == 200:
                ver = r.json().get("version", "?")
                checks.append(HealthCheck(component="ollama", status="ok", detail=f"v{ver}"))
            else:
                checks.append(HealthCheck(component="ollama", status="degraded",
                                          detail=f"HTTP {r.status_code}"))
    except (httpx.HTTPError, OSError) as e:
        checks.append(HealthCheck(component="ollama", status="down", detail=str(e)[:80]))

    # GAVIO API
    try:
        async with httpx.AsyncClient(timeout=2.0) as c:
            r = await c.get("http://127.0.0.1:8000/health")
            if r.status_code == 200:
                checks.append(HealthCheck(component="gavio", status="ok", detail="responding"))
            else:
                checks.append(HealthCheck(component="gavio", status="degraded",
                                          detail=f"HTTP {r.status_code}"))
    except (httpx.HTTPError, OSError):
        checks.append(HealthCheck(component="gavio", status="down", detail="unreachable"))

    # Disk
    try:
        usage = shutil.disk_usage("/")
        free_gb = usage.free // (1024**3)
        pct = (usage.used / usage.total) * 100
        if pct > 95:
            checks.append(HealthCheck(component="disk", status="down",
                                      detail=f"{free_gb}GB free, {pct:.0f}% used"))
        elif pct > 85:
            checks.append(HealthCheck(component="disk", status="degraded",
                                      detail=f"{free_gb}GB free, {pct:.0f}% used"))
        else:
            checks.append(HealthCheck(component="disk", status="ok",
                                      detail=f"{free_gb}GB free"))
    except OSError as e:
        checks.append(HealthCheck(component="disk", status="down", detail=str(e)))

    # Memory
    try:
        with open("/proc/meminfo") as f:
            info = {}
            for line in f:
                if line.startswith(("MemTotal:", "MemAvailable:")):
                    k, v = line.split()[0:2]
                    info[k.rstrip(":")] = int(v) // 1024  # MB
        total = info.get("MemTotal", 0)
        avail = info.get("MemAvailable", 0)
        if total:
            pct = (1 - avail / total) * 100
            if pct > 95:
                checks.append(HealthCheck(component="memory", status="down",
                                          detail=f"{avail}MB free, {pct:.0f}% used"))
            elif pct > 85:
                checks.append(HealthCheck(component="memory", status="degraded",
                                          detail=f"{avail}MB free, {pct:.0f}% used"))
            else:
                checks.append(HealthCheck(component="memory", status="ok",
                                          detail=f"{avail}/{total} MB"))
    except OSError as e:
        checks.append(HealthCheck(component="memory", status="degraded", detail=str(e)))

    # Overall verdict
    if any(c.status == "down" for c in checks):
        overall = "down"
        response.status_code = 503
    elif any(c.status == "degraded" for c in checks):
        overall = "degraded"
    else:
        overall = "ok"

    return DeepHealthResponse(overall=overall, checks=checks)
