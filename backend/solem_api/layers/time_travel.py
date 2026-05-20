"""TIME TRAVEL — UI back-end per "torna al sistema com'era ieri".

Single responsibility: SOLO listare gli snapshot ZFS/btrfs disponibili +
preview metadata (data, dimensione delta, file più cambiati) + trigger
rollback (richiede conferma esplicita).

Niente esecuzione automatica: solo proposte. L'utente conferma.

Endpoint:
  GET  /time-travel/snapshots                — lista snapshot disponibili
  GET  /time-travel/snapshot/{name}/preview  — diff sintetico con HEAD
  POST /time-travel/restore                  — rollback (conferma obbligatoria)
"""
from __future__ import annotations

import shutil
import subprocess
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field


router = APIRouter(prefix="/time-travel", tags=["time-travel"])


class Snapshot(BaseModel):
    name: str
    dataset: str
    created_at: str
    used_bytes: int = 0
    backend: str = "zfs"  # zfs|btrfs


class RestoreRequest(BaseModel):
    snapshot_name: str
    dataset: str
    confirm_token: str = Field(..., description="Deve essere uguale a snapshot_name")


def _list_zfs() -> list[Snapshot]:
    zfs = shutil.which("zfs")
    if not zfs:
        return []
    try:
        r = subprocess.run([zfs, "list", "-t", "snapshot", "-H",
                            "-o", "name,creation,used"],
                           capture_output=True, text=True, timeout=5, check=False)
    except subprocess.SubprocessError:
        return []
    out = []
    for line in r.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        full_name = parts[0]
        dataset, _, snap_name = full_name.rpartition("@")
        try:
            used_str = parts[2].replace("K", "").replace("M", "").replace("G", "")
            used_bytes = int(float(used_str)) * (
                1024**3 if "G" in parts[2] else (1024**2 if "M" in parts[2] else 1024)
            )
        except (ValueError, IndexError):
            used_bytes = 0
        out.append(Snapshot(
            name=snap_name, dataset=dataset, created_at=parts[1],
            used_bytes=used_bytes, backend="zfs",
        ))
    return out


def _list_btrfs() -> list[Snapshot]:
    btrfs = shutil.which("btrfs")
    if not btrfs:
        return []
    try:
        r = subprocess.run([btrfs, "subvolume", "list", "-s", "/"],
                           capture_output=True, text=True, timeout=5, check=False)
    except subprocess.SubprocessError:
        return []
    out = []
    for line in r.stdout.splitlines():
        # Output stile "ID 256 gen 12 cgen 12 top level 5 otime 2026-01-15 09:00:00 path snapshot-X"
        if "otime" not in line:
            continue
        try:
            otime = line.split("otime ", 1)[1].split(" path", 1)[0].strip()
            path = line.split("path ", 1)[1].strip()
            out.append(Snapshot(
                name=path.split("/")[-1], dataset="/", created_at=otime,
                used_bytes=0, backend="btrfs",
            ))
        except (IndexError, ValueError):
            continue
    return out


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/health", response_model=dict)
async def tt_health() -> dict:
    return {
        "zfs_available": shutil.which("zfs") is not None,
        "btrfs_available": shutil.which("btrfs") is not None,
        "policy": "list-only by default. Restore richiede confirm_token = snapshot_name.",
    }


@router.get("/snapshots", response_model=list[Snapshot])
async def list_snapshots() -> list[Snapshot]:
    snaps = _list_zfs() + _list_btrfs()
    return sorted(snaps, key=lambda s: s.created_at, reverse=True)


@router.get("/snapshot/{name}/preview", response_model=dict)
async def preview(name: str, dataset: str = "") -> dict:
    """Conta file cambiati tra snapshot e HEAD (approssimato)."""
    snaps = await list_snapshots()
    target = next((s for s in snaps if s.name == name and (not dataset or s.dataset == dataset)), None)
    if not target:
        raise HTTPException(404, {"code": "snapshot_not_found"})

    # Per ZFS: zfs diff dataset@snap
    if target.backend == "zfs":
        zfs = shutil.which("zfs")
        if not zfs:
            return {"snapshot": target.model_dump(), "diff_available": False}
        try:
            r = subprocess.run([zfs, "diff", f"{target.dataset}@{target.name}"],
                               capture_output=True, text=True, timeout=10, check=False)
            lines = r.stdout.splitlines()[:50]
            return {
                "snapshot": target.model_dump(),
                "files_changed_approx": len(r.stdout.splitlines()),
                "sample_paths": lines,
            }
        except subprocess.SubprocessError:
            pass

    return {"snapshot": target.model_dump(), "diff_available": False}


@router.post("/restore", response_model=dict)
async def restore(req: RestoreRequest) -> dict:
    """ATTENZIONE: rollback distruttivo. confirm_token = snapshot_name."""
    if req.confirm_token != req.snapshot_name:
        raise HTTPException(403, {
            "code": "missing_confirm_token",
            "hint": "Imposta confirm_token = snapshot_name come safety check.",
        })

    snaps = await list_snapshots()
    target = next((s for s in snaps if s.name == req.snapshot_name and s.dataset == req.dataset), None)
    if not target:
        raise HTTPException(404, {"code": "snapshot_not_found"})

    sudo = shutil.which("sudo")
    if target.backend == "zfs":
        zfs = shutil.which("zfs")
        if not zfs or not sudo:
            raise HTTPException(503, {"code": "zfs_unavailable"})
        try:
            r = subprocess.run([sudo, "-n", zfs, "rollback", "-r",
                                f"{req.dataset}@{req.snapshot_name}"],
                               capture_output=True, text=True, timeout=60, check=False)
            return {
                "restored": r.returncode == 0,
                "stderr_tail": r.stderr[-500:],
                "backend": "zfs",
                "snapshot": req.snapshot_name,
                "note": "Riavvio raccomandato per applicare lo stato precedente.",
            }
        except subprocess.SubprocessError as e:
            raise HTTPException(500, {"code": "rollback_failed", "error": str(e)})

    return {"restored": False, "reason": "btrfs restore non implementato in questa versione (Step 0)"}
