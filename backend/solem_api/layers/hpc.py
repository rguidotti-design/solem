"""HPC — High Performance Computing orchestration (Slurm/PBS abstraction).

Single responsibility: SOLO API per submit/list/cancel job batch su un
backend HPC. Niente esecuzione (delega a `sbatch`, `qsub` o equivalente).
Niente scheduling (lo fa il backend HPC).

Backend supportati (provider abstraction):
  - slurm   → `sbatch`, `squeue`, `scancel`, `sinfo`  (default)
  - pbs     → `qsub`, `qstat`, `qdel`
  - mock    → no-op (per test/dev senza HPC reale)

Step 0: scaffold. In produzione richiede:
  - solem-hpc.nix per pacchetti Slurm/munge
  - utente "gavio" con SLURM_USER set
  - mesh visibility verso lo scheduler (porta 6817-6819 Slurm)

ADR-021 → HPC come "capability" di SOLEM. GAVIO può chiedere a SOLEM di
sottomettere un job (training fine-tuning, simulazione, batch inference).
"""
from __future__ import annotations

import os
import shutil
import subprocess
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/hpc", tags=["hpc"])

BACKEND = os.environ.get("SOLEM_HPC_BACKEND", "slurm")  # slurm|pbs|mock
JOBS_LOG = Path("/var/lib/solem/hpc_jobs.log")


class JobSpec(BaseModel):
    name: str = Field(..., min_length=1, max_length=64)
    command: str = Field(..., min_length=1, description="Comando shell da eseguire")
    partition: str = Field("default", description="Slurm partition / PBS queue")
    nodes: int = Field(1, ge=1, le=1024)
    cpus_per_task: int = Field(1, ge=1, le=256)
    mem_gb: int = Field(4, ge=1, le=2048)
    gpus: int = Field(0, ge=0, le=16)
    time_limit_min: int = Field(60, ge=1, le=43200)
    env: dict[str, str] = Field(default_factory=dict)


class Job(BaseModel):
    job_id: str
    name: str
    state: Literal["pending", "running", "completed", "failed", "cancelled", "unknown"]
    backend: str
    submitted_at: str
    partition: str | None = None
    nodes: int = 1


class ClusterPartition(BaseModel):
    name: str
    nodes: int
    state: str
    available: bool


# ─── Backend abstraction ──────────────────────────────────────────────


def _slurm_available() -> bool:
    return shutil.which("sbatch") is not None and shutil.which("squeue") is not None


def _pbs_available() -> bool:
    return shutil.which("qsub") is not None


def _pick_backend() -> str:
    if BACKEND == "mock":
        return "mock"
    if BACKEND == "slurm" and _slurm_available():
        return "slurm"
    if BACKEND == "pbs" and _pbs_available():
        return "pbs"
    return "mock"  # fallback se backend non installato


def _slurm_submit(spec: JobSpec) -> str:
    """Genera batch script + sbatch."""
    sbatch = shutil.which("sbatch")
    if not sbatch:
        raise HTTPException(503, {"code": "slurm_not_available"})
    script_lines = [
        "#!/usr/bin/env bash",
        f"#SBATCH --job-name={spec.name}",
        f"#SBATCH --partition={spec.partition}",
        f"#SBATCH --nodes={spec.nodes}",
        f"#SBATCH --cpus-per-task={spec.cpus_per_task}",
        f"#SBATCH --mem={spec.mem_gb}G",
        f"#SBATCH --time={spec.time_limit_min}",
    ]
    if spec.gpus > 0:
        script_lines.append(f"#SBATCH --gres=gpu:{spec.gpus}")
    for k, v in spec.env.items():
        script_lines.append(f"export {k}={v}")
    script_lines.append(spec.command)
    script = "\n".join(script_lines) + "\n"

    try:
        r = subprocess.run([sbatch, "--parsable"], input=script, capture_output=True,
                           text=True, timeout=10, check=False)
        if r.returncode != 0:
            raise HTTPException(500, {"code": "sbatch_failed", "stderr": r.stderr[:400]})
        return r.stdout.strip().split(";")[0]  # job id
    except subprocess.SubprocessError as e:
        raise HTTPException(500, {"code": "sbatch_exception", "error": str(e)})


def _slurm_list() -> list[Job]:
    squeue = shutil.which("squeue")
    if not squeue:
        return []
    try:
        r = subprocess.run([squeue, "-h", "-o", "%i|%j|%T|%P|%D|%V"],
                           capture_output=True, text=True, timeout=5, check=False)
    except subprocess.SubprocessError:
        return []
    out = []
    state_map = {
        "PENDING": "pending", "RUNNING": "running",
        "COMPLETED": "completed", "FAILED": "failed",
        "CANCELLED": "cancelled",
    }
    for line in r.stdout.strip().splitlines():
        parts = line.split("|")
        if len(parts) < 6:
            continue
        out.append(Job(
            job_id=parts[0], name=parts[1],
            state=state_map.get(parts[2], "unknown"),
            backend="slurm", submitted_at=parts[5],
            partition=parts[3], nodes=int(parts[4]) if parts[4].isdigit() else 1,
        ))
    return out


def _slurm_cancel(job_id: str) -> bool:
    scancel = shutil.which("scancel")
    if not scancel:
        return False
    try:
        r = subprocess.run([scancel, job_id], capture_output=True, text=True, timeout=5, check=False)
        return r.returncode == 0
    except subprocess.SubprocessError:
        return False


def _slurm_partitions() -> list[ClusterPartition]:
    sinfo = shutil.which("sinfo")
    if not sinfo:
        return []
    try:
        r = subprocess.run([sinfo, "-h", "-o", "%R|%D|%T"],
                           capture_output=True, text=True, timeout=5, check=False)
    except subprocess.SubprocessError:
        return []
    out = []
    for line in r.stdout.strip().splitlines():
        parts = line.split("|")
        if len(parts) < 3:
            continue
        nodes = int(parts[1]) if parts[1].isdigit() else 0
        state = parts[2]
        out.append(ClusterPartition(
            name=parts[0], nodes=nodes, state=state,
            available=state in {"idle", "mixed", "alloc"},
        ))
    return out


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/health", response_model=dict)
async def hpc_health() -> dict:
    return {
        "backend_configured": BACKEND,
        "backend_active": _pick_backend(),
        "slurm_available": _slurm_available(),
        "pbs_available": _pbs_available(),
        "step": "scaffold (Step 0) — installa solem-hpc.nix per Slurm reale",
    }


@router.post("/submit", response_model=Job)
async def submit(spec: JobSpec) -> Job:
    backend = _pick_backend()
    if backend == "mock":
        # Job ID fake per dev
        jid = f"mock-{uuid.uuid4().hex[:8]}"
        job = Job(
            job_id=jid, name=spec.name, state="pending", backend="mock",
            submitted_at=datetime.now(timezone.utc).isoformat(),
            partition=spec.partition, nodes=spec.nodes,
        )
        JOBS_LOG.parent.mkdir(parents=True, exist_ok=True)
        with JOBS_LOG.open("a") as f:
            f.write(job.model_dump_json() + "\n")
        return job

    if backend == "slurm":
        jid = _slurm_submit(spec)
        return Job(
            job_id=jid, name=spec.name, state="pending", backend="slurm",
            submitted_at=datetime.now(timezone.utc).isoformat(),
            partition=spec.partition, nodes=spec.nodes,
        )

    raise HTTPException(503, {"code": "no_backend_active"})


@router.get("/jobs", response_model=list[Job])
async def list_jobs() -> list[Job]:
    backend = _pick_backend()
    if backend == "slurm":
        return _slurm_list()
    if backend == "mock":
        # Leggi dal log
        if not JOBS_LOG.exists():
            return []
        out = []
        for line in JOBS_LOG.read_text(encoding="utf-8").splitlines():
            try:
                import json as _j
                out.append(Job(**_j.loads(line)))
            except Exception:
                continue
        return out
    return []


@router.delete("/jobs/{job_id}", response_model=dict)
async def cancel(job_id: str) -> dict:
    backend = _pick_backend()
    if backend == "slurm":
        ok = _slurm_cancel(job_id)
        return {"cancelled": ok, "backend": "slurm", "job_id": job_id}
    return {"cancelled": True, "backend": backend, "job_id": job_id, "note": "mock backend"}


@router.get("/partitions", response_model=list[ClusterPartition])
async def partitions() -> list[ClusterPartition]:
    if _pick_backend() == "slurm":
        return _slurm_partitions()
    return []
