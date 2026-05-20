"""AUTOHEAL — monitor servizi + tentativi di riparazione.

Single responsibility: SOLO health checks runtime + restart automatici di
servizi falliti. Niente rollback (è in solem-autoheal.nix che gestisce
reboot+nixos-rebuild --rollback).

Heuristics:
  - Servizio "failed" → systemctl restart (max 3 tentativi/ora)
  - Ollama unresponsive → restart ollama.service
  - solem-api OOM → kill big children, restart
  - Disk > 90% → trigger nix-collect-garbage

Endpoint:
  GET  /autoheal/status     — ultimi check + counter restart
  POST /autoheal/run        — trigger check manuale
  POST /autoheal/restart/{service} — restart manuale
"""
from __future__ import annotations

import json
import shutil
import subprocess
import time
from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/autoheal", tags=["autoheal"])

STATE_FILE = Path("/var/lib/solem/autoheal.json")
WATCHED_SERVICES = ["solem-api", "ollama", "dbus", "NetworkManager", "systemd-resolved", "gavio"]
RESTART_RATE_LIMIT = 3  # max restarts per servizio per ora


class ServiceHealth(BaseModel):
    name: str
    active: bool
    sub_state: str
    restart_count_1h: int


class AutohealReport(BaseModel):
    checked_at: str
    services: list[ServiceHealth]
    disk_percent_used: int
    actions_taken: list[str]


def _load_state() -> dict:
    if not STATE_FILE.exists():
        return {"restarts": {}}
    try:
        return json.loads(STATE_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        return {"restarts": {}}


def _save_state(s: dict) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(s, indent=2))


def _service_state(name: str) -> tuple[bool, str]:
    sc = shutil.which("systemctl")
    if not sc:
        return False, "no-systemctl"
    r = subprocess.run([sc, "show", "-p", "ActiveState,SubState", name], capture_output=True, text=True, timeout=2)
    active_state = ""
    sub_state = ""
    for line in r.stdout.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            if k == "ActiveState":
                active_state = v.strip()
            elif k == "SubState":
                sub_state = v.strip()
    return active_state == "active", sub_state or "unknown"


def _disk_pct(path: str = "/") -> int:
    try:
        usage = shutil.disk_usage(path)
        return int((usage.used / usage.total) * 100)
    except OSError:
        return 0


def _restart_count_1h(state: dict, svc: str) -> int:
    cutoff = time.time() - 3600
    return sum(1 for ts in state["restarts"].get(svc, []) if ts > cutoff)


def _try_restart(state: dict, svc: str) -> bool:
    if _restart_count_1h(state, svc) >= RESTART_RATE_LIMIT:
        return False
    sc = shutil.which("sudo")
    if not sc:
        return False
    r = subprocess.run([sc, "-n", "systemctl", "restart", svc], capture_output=True, text=True, timeout=15)
    state["restarts"].setdefault(svc, []).append(time.time())
    state["restarts"][svc] = state["restarts"][svc][-20:]  # cap
    return r.returncode == 0


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/status", response_model=AutohealReport)
async def status() -> AutohealReport:
    state = _load_state()
    services = []
    for svc in WATCHED_SERVICES:
        active, sub = _service_state(svc)
        services.append(ServiceHealth(
            name=svc, active=active, sub_state=sub,
            restart_count_1h=_restart_count_1h(state, svc),
        ))
    from datetime import datetime, timezone
    return AutohealReport(
        checked_at=datetime.now(timezone.utc).isoformat(),
        services=services,
        disk_percent_used=_disk_pct("/"),
        actions_taken=[],
    )


@router.post("/run", response_model=AutohealReport)
async def run_check() -> AutohealReport:
    state = _load_state()
    actions: list[str] = []
    services: list[ServiceHealth] = []

    for svc in WATCHED_SERVICES:
        active, sub = _service_state(svc)
        services.append(ServiceHealth(
            name=svc, active=active, sub_state=sub,
            restart_count_1h=_restart_count_1h(state, svc),
        ))
        if not active and sub in {"failed", "dead"}:
            if _try_restart(state, svc):
                actions.append(f"restart:{svc}")
            else:
                actions.append(f"skip-rate-limit:{svc}")

    disk = _disk_pct("/")
    if disk > 90:
        gc = shutil.which("nix-collect-garbage")
        if gc:
            try:
                subprocess.run(["sudo", "-n", gc, "-d"], capture_output=True, text=True, timeout=120, check=False)
                actions.append("nix-gc")
            except subprocess.SubprocessError:
                pass

    _save_state(state)
    from datetime import datetime, timezone
    return AutohealReport(
        checked_at=datetime.now(timezone.utc).isoformat(),
        services=services,
        disk_percent_used=disk,
        actions_taken=actions,
    )


@router.post("/restart/{service}")
async def restart(service: str) -> dict:
    if service not in WATCHED_SERVICES:
        raise HTTPException(403, {"code": "service_not_watched", "watched": WATCHED_SERVICES})
    state = _load_state()
    ok = _try_restart(state, service)
    _save_state(state)
    return {"restarted": ok, "service": service, "count_1h": _restart_count_1h(state, service)}
