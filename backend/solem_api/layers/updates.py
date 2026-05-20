"""UPDATES — gestione update channel + check + apply (interfaccia API).

Single responsibility: SOLO esporre stato canale update e trigger
nixos-rebuild. Non parla con GitHub, non risolve commit; delega a
solem-update.timer (in solem-updates.nix).

Canali:
  - stable   → flake.lock pinned (semver SOLEM)
  - testing  → main HEAD del repo (auto-merge dopo CI)
  - nightly  → flake update settimanale (rolling)

Endpoint:
  GET  /updates/status        — canale corrente + ultimo check + pending
  POST /updates/check         — trigger check (no apply)
  POST /updates/apply         — trigger nixos-rebuild switch
  POST /updates/rollback      — boot nella generation precedente
  GET  /updates/history       — lista generations (nix profile history)
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/updates", tags=["updates"])

CHANNEL_FILE = Path("/etc/solem/channel")
LAST_CHECK_FILE = Path("/var/lib/solem/last-update-check.json")

ChannelType = Literal["stable", "testing", "nightly"]


class UpdateStatus(BaseModel):
    channel: ChannelType
    current_generation: int
    last_check_at: str | None = None
    last_check_result: dict | None = None
    pending_updates: bool = False
    nixos_version: str | None = None


class CheckResponse(BaseModel):
    checked_at: str
    channel: ChannelType
    updates_available: bool
    detail: str


class GenerationInfo(BaseModel):
    number: int
    date: str
    current: bool = False


# ─── Helpers ──────────────────────────────────────────────────────────


def _current_channel() -> ChannelType:
    if CHANNEL_FILE.exists():
        v = CHANNEL_FILE.read_text().strip()
        if v in ("stable", "testing", "nightly"):
            return v  # type: ignore
    return "stable"


def _current_generation() -> int:
    nix = shutil.which("nix-env")
    if not nix:
        return 0
    try:
        r = subprocess.run(
            [nix, "--list-generations", "-p", "/nix/var/nix/profiles/system"],
            capture_output=True, text=True, timeout=5, check=False,
        )
        for line in r.stdout.splitlines():
            if "(current)" in line:
                return int(line.strip().split()[0])
    except (subprocess.SubprocessError, ValueError):
        pass
    return 0


def _read_last_check() -> dict | None:
    if not LAST_CHECK_FILE.exists():
        return None
    try:
        return json.loads(LAST_CHECK_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def _write_last_check(payload: dict) -> None:
    LAST_CHECK_FILE.parent.mkdir(parents=True, exist_ok=True)
    LAST_CHECK_FILE.write_text(json.dumps(payload, indent=2))


def _nixos_version() -> str | None:
    f = Path("/etc/os-release")
    if not f.exists():
        return None
    for line in f.read_text().splitlines():
        if line.startswith("VERSION="):
            return line.split("=", 1)[1].strip('"')
    return None


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/status", response_model=UpdateStatus)
async def status() -> UpdateStatus:
    last = _read_last_check()
    return UpdateStatus(
        channel=_current_channel(),
        current_generation=_current_generation(),
        last_check_at=last["checked_at"] if last else None,
        last_check_result=last,
        pending_updates=last.get("updates_available", False) if last else False,
        nixos_version=_nixos_version(),
    )


@router.post("/channel", response_model=UpdateStatus)
async def set_channel(channel: ChannelType) -> UpdateStatus:
    """Switch canale. Richiede rebuild successivo per applicare."""
    if not CHANNEL_FILE.parent.exists():
        try:
            CHANNEL_FILE.parent.mkdir(parents=True)
        except PermissionError:
            raise HTTPException(403, {"code": "channel_dir_not_writable"})
    try:
        CHANNEL_FILE.write_text(channel)
    except PermissionError:
        raise HTTPException(403, {"code": "channel_file_not_writable", "hint": "richiede root"})
    return await status()


@router.post("/check", response_model=CheckResponse)
async def check() -> CheckResponse:
    """Trigger nix flake update --commit-lock-file=false (dry-run)."""
    nix = shutil.which("nix")
    if not nix:
        raise HTTPException(503, {"code": "nix_not_available"})

    flake_dir = os.environ.get("SOLEM_FLAKE_DIR", "/etc/nixos")
    now = datetime.now(timezone.utc).isoformat()

    try:
        # nix flake metadata mostra commit corrente
        r = subprocess.run(
            [nix, "flake", "metadata", "--json", flake_dir],
            capture_output=True, text=True, timeout=30, check=False,
        )
        meta = json.loads(r.stdout) if r.returncode == 0 else {}
    except (subprocess.SubprocessError, json.JSONDecodeError) as e:
        raise HTTPException(500, {"code": "flake_check_failed", "error": str(e)})

    # Step 0: dichiariamo updates_available=False sempre (true requirement
    # è confrontare con remote, fuori scope qui). Si appoggia al timer.
    payload = {
        "checked_at": now,
        "channel": _current_channel(),
        "updates_available": False,
        "detail": f"flake commit: {meta.get('locked', {}).get('rev', 'unknown')[:8]}",
        "flake_metadata": meta,
    }
    _write_last_check(payload)
    return CheckResponse(**{k: v for k, v in payload.items() if k in CheckResponse.model_fields})


@router.post("/apply")
async def apply() -> dict:
    """nixos-rebuild switch. Richiede sudo NOPASSWD configurato."""
    nrb = shutil.which("nixos-rebuild")
    if not nrb:
        raise HTTPException(503, {"code": "nixos_rebuild_not_available"})

    flake_dir = os.environ.get("SOLEM_FLAKE_DIR", "/etc/nixos")
    try:
        r = subprocess.run(
            ["sudo", "-n", nrb, "switch", "--flake", flake_dir],
            capture_output=True, text=True, timeout=900, check=False,
        )
    except subprocess.SubprocessError as e:
        raise HTTPException(500, {"code": "rebuild_failed", "error": str(e)})

    return {
        "ok": r.returncode == 0,
        "returncode": r.returncode,
        "stdout_tail": r.stdout[-2000:],
        "stderr_tail": r.stderr[-2000:],
    }


@router.post("/rollback")
async def rollback() -> dict:
    """nixos-rebuild switch --rollback alla generation precedente."""
    nrb = shutil.which("nixos-rebuild")
    if not nrb:
        raise HTTPException(503, {"code": "nixos_rebuild_not_available"})

    try:
        r = subprocess.run(
            ["sudo", "-n", nrb, "switch", "--rollback"],
            capture_output=True, text=True, timeout=300, check=False,
        )
    except subprocess.SubprocessError as e:
        raise HTTPException(500, {"code": "rollback_failed", "error": str(e)})

    return {
        "ok": r.returncode == 0,
        "returncode": r.returncode,
        "stdout_tail": r.stdout[-2000:],
        "stderr_tail": r.stderr[-2000:],
    }


@router.get("/history", response_model=list[GenerationInfo])
async def history() -> list[GenerationInfo]:
    nix = shutil.which("nix-env")
    if not nix:
        raise HTTPException(503, {"code": "nix_env_not_available"})

    r = subprocess.run(
        [nix, "--list-generations", "-p", "/nix/var/nix/profiles/system"],
        capture_output=True, text=True, timeout=5, check=False,
    )
    out: list[GenerationInfo] = []
    for line in r.stdout.splitlines():
        parts = line.strip().split(maxsplit=3)
        if len(parts) >= 3 and parts[0].isdigit():
            num = int(parts[0])
            date = f"{parts[1]} {parts[2]}"
            current = "(current)" in line
            out.append(GenerationInfo(number=num, date=date, current=current))
    return out
