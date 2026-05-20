"""PRIVACY DASH — chi sta usando microfono/camera/location adesso?

Single responsibility: SOLO inventory in tempo reale degli accessi sensori.
Niente blocco runtime (delega all'utente via kill PID).

Source di verità (Linux):
  - /proc/*/fd/* + sys/class/video4linux per camera/V4L2
  - PipeWire/PulseAudio per microfono (pactl list source-outputs)
  - Geoclue D-Bus per location

Endpoint:
  GET  /privacy/sensors            — chi accede a cosa
  POST /privacy/kill/{pid}         — termina processo
  GET  /privacy/history            — log accessi (file rotato)
"""
from __future__ import annotations

import json
import os
import shutil
import signal
import subprocess
import time
from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/privacy", tags=["privacy-dash"])

HISTORY_FILE = Path("/var/lib/solem/privacy-history.jsonl")


class SensorAccess(BaseModel):
    sensor: str = Field(..., description="microphone|camera|location|screen|clipboard")
    pid: int
    process_name: str
    started_at: float | None = None
    detail: str | None = None


class PrivacyState(BaseModel):
    checked_at: float
    microphone: list[SensorAccess]
    camera: list[SensorAccess]
    location: list[SensorAccess]


# ─── Detection helpers ────────────────────────────────────────────────


def _detect_microphone() -> list[SensorAccess]:
    """pactl list source-outputs short → PID dei processi che usano mic."""
    pactl = shutil.which("pactl")
    if not pactl:
        return []
    try:
        r = subprocess.run(
            [pactl, "list", "source-outputs"],
            capture_output=True, text=True, timeout=3, check=False,
        )
    except subprocess.SubprocessError:
        return []

    accesses: list[SensorAccess] = []
    current_pid: int | None = None
    current_name = "?"
    for line in r.stdout.splitlines():
        line = line.strip()
        if line.startswith("application.process.id"):
            try:
                current_pid = int(line.split("=")[-1].strip().strip('"'))
            except (ValueError, IndexError):
                pass
        elif line.startswith("application.process.binary"):
            current_name = line.split("=")[-1].strip().strip('"')
        elif line.startswith("Source Output #") and current_pid:
            accesses.append(SensorAccess(
                sensor="microphone", pid=current_pid, process_name=current_name,
                started_at=time.time(),
            ))
            current_pid = None
            current_name = "?"

    if current_pid:
        accesses.append(SensorAccess(
            sensor="microphone", pid=current_pid, process_name=current_name,
        ))
    return accesses


def _detect_camera() -> list[SensorAccess]:
    """fuser /dev/video* per trovare i PID che hanno aperto camera."""
    accesses: list[SensorAccess] = []
    for vid in Path("/dev").glob("video*"):
        fuser = shutil.which("fuser")
        if not fuser:
            return []
        try:
            r = subprocess.run([fuser, "-v", str(vid)], capture_output=True, text=True, timeout=2, check=False)
        except subprocess.SubprocessError:
            continue
        for line in r.stderr.splitlines():  # fuser scrive su stderr
            parts = line.split()
            for p in parts:
                if p.isdigit():
                    pid = int(p)
                    try:
                        comm = Path(f"/proc/{pid}/comm").read_text().strip()
                    except OSError:
                        comm = "?"
                    accesses.append(SensorAccess(
                        sensor="camera", pid=pid, process_name=comm,
                        detail=str(vid),
                    ))
    return accesses


def _detect_location() -> list[SensorAccess]:
    """Geoclue: lista client attivi via busctl."""
    busctl = shutil.which("busctl")
    if not busctl:
        return []
    try:
        r = subprocess.run(
            [busctl, "tree", "org.freedesktop.GeoClue2"],
            capture_output=True, text=True, timeout=2, check=False,
        )
    except subprocess.SubprocessError:
        return []
    accesses: list[SensorAccess] = []
    # parsing semplice: client paths /org/freedesktop/GeoClue2/Client/N
    for line in r.stdout.splitlines():
        if "/Client/" in line:
            accesses.append(SensorAccess(
                sensor="location", pid=0, process_name="(geoclue client)", detail=line.strip(),
            ))
    return accesses


def _append_history(state: PrivacyState) -> None:
    HISTORY_FILE.parent.mkdir(parents=True, exist_ok=True)
    with HISTORY_FILE.open("a", encoding="utf-8") as f:
        f.write(state.model_dump_json() + "\n")
    # Cap a 10k linee
    lines = HISTORY_FILE.read_text(encoding="utf-8").splitlines()
    if len(lines) > 10000:
        HISTORY_FILE.write_text("\n".join(lines[-10000:]) + "\n", encoding="utf-8")


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/health", response_model=dict)
async def priv_health() -> dict:
    return {
        "pactl_available": shutil.which("pactl") is not None,
        "fuser_available": shutil.which("fuser") is not None,
        "busctl_available": shutil.which("busctl") is not None,
        "history_file": str(HISTORY_FILE),
    }


@router.get("/sensors", response_model=PrivacyState)
async def sensors() -> PrivacyState:
    state = PrivacyState(
        checked_at=time.time(),
        microphone=_detect_microphone(),
        camera=_detect_camera(),
        location=_detect_location(),
    )
    _append_history(state)
    return state


@router.post("/kill/{pid}")
async def kill(pid: int, signum: int = 15) -> dict:
    if pid <= 1 or pid == os.getpid():
        raise HTTPException(403, {"code": "pid_not_allowed"})
    try:
        os.kill(pid, signum)
        return {"killed": pid, "signal": signum}
    except ProcessLookupError:
        raise HTTPException(404, {"code": "pid_not_found", "pid": pid})
    except PermissionError:
        raise HTTPException(403, {"code": "permission_denied"})


@router.get("/history", response_model=list[dict])
async def history(limit: int = 200) -> list[dict]:
    if not HISTORY_FILE.exists():
        return []
    lines = HISTORY_FILE.read_text(encoding="utf-8").splitlines()
    out: list[dict] = []
    for line in lines[-limit:]:
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return out
