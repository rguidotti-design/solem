"""QUANTUM — computer quantistici: submit circuit + result polling.

Single responsibility: SOLO API per sottomettere un circuito Qiskit/OpenQASM
a un backend quantistico (cloud o simulatore locale) e raccogliere il
risultato. Niente design circuit (lo fa GAVIO o l'utente).

Provider abstraction (Step 0 — scaffold):
  - ibm_quantum   → IBM Quantum (richiede token su file 600)
  - rigetti       → Rigetti Forest (Quil)
  - ionq          → IonQ Cloud API
  - simulator     → simulator locale (Qiskit Aer) — DEFAULT, no token, gratis
  - mock          → echo dei conteggi (test/dev)

ADR-022 → Quantum come "capability" SOLEM. GAVIO può proporre un
algoritmo (Grover, QAOA, Shor demo) → SOLEM lo submitta su simulator
(gratis) o, se l'utente fornisce un token IBM Quantum free-tier, su
hardware reale.

Tutto FOSS:
  - Qiskit (Apache 2.0)
  - Qiskit Aer simulator (Apache 2.0)
  - Token IBM Quantum: free-tier 7000 secondi/mese hardware reale
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/quantum", tags=["quantum"])

PROVIDER = os.environ.get("SOLEM_QUANTUM_PROVIDER", "simulator")
JOBS_FILE = Path("/var/lib/solem/quantum_jobs.json")
IBM_TOKEN_FILE = Path(os.environ.get("SOLEM_IBM_QUANTUM_TOKEN_FILE", "/var/lib/solem-secrets/ibm_quantum.token"))


class CircuitSubmit(BaseModel):
    name: str = Field(..., min_length=1, max_length=64)
    openqasm: str = Field(..., description="OpenQASM 2.0/3.0 source")
    shots: int = Field(1024, ge=1, le=100000)
    provider: Literal["ibm_quantum", "rigetti", "ionq", "simulator", "mock"] = "simulator"
    backend_name: str = Field("aer_simulator", description="Nome backend (Aer, ibmq_qasm_simulator, ionq_qpu, ...)")


class QuantumJob(BaseModel):
    job_id: str
    name: str
    state: Literal["queued", "running", "done", "error", "cancelled"]
    provider: str
    backend_name: str
    submitted_at: str
    shots: int
    qubits: int = 0
    queue_position: int | None = None


class JobResult(BaseModel):
    job_id: str
    state: str
    counts: dict[str, int] = Field(default_factory=dict, description="bitstring → count")
    expectation: float | None = None
    duration_ms: float | None = None
    raw: dict = Field(default_factory=dict)


# ─── Provider detection ───────────────────────────────────────────────


def _qiskit_available() -> bool:
    try:
        import qiskit  # noqa: F401
        return True
    except ImportError:
        return False


def _ibm_token() -> str | None:
    if not IBM_TOKEN_FILE.exists():
        return None
    try:
        return IBM_TOKEN_FILE.read_text().strip()
    except OSError:
        return None


def _load_jobs() -> dict:
    if not JOBS_FILE.exists():
        return {}
    try:
        return json.loads(JOBS_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        return {}


def _save_jobs(jobs: dict) -> None:
    JOBS_FILE.parent.mkdir(parents=True, exist_ok=True)
    JOBS_FILE.write_text(json.dumps(jobs, indent=2))


# ─── Simulator (locale, gratis, FOSS) ─────────────────────────────────


def _count_qubits(openqasm: str) -> int:
    """Stima numero qubit dal codice OpenQASM (parser minimale)."""
    import re
    m = re.search(r"qreg\s+\w+\s*\[\s*(\d+)\s*\]", openqasm)
    if m:
        return int(m.group(1))
    m2 = re.search(r"qubit\s*\[\s*(\d+)\s*\]", openqasm)
    if m2:
        return int(m2.group(1))
    return 0


def _simulator_run(circuit: CircuitSubmit) -> JobResult:
    """Esegue il circuito su Qiskit Aer simulator locale."""
    if not _qiskit_available():
        # Fallback mock: distribuzione uniforme tra 2 stati per dimostrare il path
        qubits = _count_qubits(circuit.openqasm)
        bitstrings = ["0" * max(1, qubits), "1" + "0" * max(0, qubits - 1)]
        half = circuit.shots // 2
        counts = {bitstrings[0]: half, bitstrings[1]: circuit.shots - half}
        return JobResult(
            job_id="", state="done", counts=counts,
            duration_ms=10.0,
            raw={"note": "qiskit non installato — risultato mock"},
        )

    import time as _t
    from qiskit import QuantumCircuit, transpile
    from qiskit_aer import AerSimulator

    t0 = _t.perf_counter()
    qc = QuantumCircuit.from_qasm_str(circuit.openqasm)
    sim = AerSimulator()
    tqc = transpile(qc, sim)
    res = sim.run(tqc, shots=circuit.shots).result()
    counts = dict(res.get_counts())
    return JobResult(
        job_id="", state="done", counts=counts,
        duration_ms=(_t.perf_counter() - t0) * 1000,
        raw={"backend": "AerSimulator"},
    )


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/health", response_model=dict)
async def quantum_health() -> dict:
    return {
        "provider_configured": PROVIDER,
        "qiskit_available": _qiskit_available(),
        "ibm_token_present": _ibm_token() is not None,
        "simulator_ready": True,  # mock fallback se Qiskit assente
        "step": "scaffold (Step 0) — installa solem-quantum.nix per Qiskit reale",
    }


@router.get("/providers", response_model=list[dict])
async def list_providers() -> list[dict]:
    return [
        {"id": "simulator", "name": "Qiskit Aer (locale)", "free": True,
         "available": True, "note": "Default. CPU-only. Fino a ~30 qubit."},
        {"id": "ibm_quantum", "name": "IBM Quantum", "free": True,
         "available": _ibm_token() is not None,
         "note": "Free-tier 7000s/mese su hardware reale. Token file: " + str(IBM_TOKEN_FILE)},
        {"id": "rigetti", "name": "Rigetti Forest", "free": False,
         "available": False, "note": "Richiede account a pagamento."},
        {"id": "ionq", "name": "IonQ Cloud", "free": False,
         "available": False, "note": "Richiede account a pagamento."},
        {"id": "mock", "name": "Mock (echo)", "free": True,
         "available": True, "note": "Per test e dev."},
    ]


@router.post("/submit", response_model=QuantumJob)
async def submit(req: CircuitSubmit) -> QuantumJob:
    job_id = uuid.uuid4().hex[:12]
    qubits = _count_qubits(req.openqasm)

    job = QuantumJob(
        job_id=job_id, name=req.name, state="queued",
        provider=req.provider, backend_name=req.backend_name,
        submitted_at=datetime.now(timezone.utc).isoformat(),
        shots=req.shots, qubits=qubits,
    )

    jobs = _load_jobs()
    jobs[job_id] = {"job": job.model_dump(), "circuit": req.model_dump(), "result": None}
    _save_jobs(jobs)

    # Esecuzione inline solo per simulator/mock (no async queue per ora)
    if req.provider in ("simulator", "mock"):
        result = _simulator_run(req)
        result.job_id = job_id
        jobs[job_id]["job"]["state"] = "done"
        jobs[job_id]["result"] = result.model_dump()
        _save_jobs(jobs)
        job.state = "done"

    return job


@router.get("/jobs", response_model=list[QuantumJob])
async def list_jobs() -> list[QuantumJob]:
    jobs = _load_jobs()
    return [QuantumJob(**v["job"]) for v in jobs.values()]


@router.get("/jobs/{job_id}/result", response_model=JobResult)
async def get_result(job_id: str) -> JobResult:
    jobs = _load_jobs()
    if job_id not in jobs:
        raise HTTPException(404, {"code": "job_not_found"})
    if not jobs[job_id].get("result"):
        raise HTTPException(202, {"code": "still_running", "state": jobs[job_id]["job"]["state"]})
    return JobResult(**jobs[job_id]["result"])


@router.delete("/jobs/{job_id}")
async def cancel(job_id: str) -> dict:
    jobs = _load_jobs()
    if job_id not in jobs:
        raise HTTPException(404, {"code": "job_not_found"})
    jobs[job_id]["job"]["state"] = "cancelled"
    _save_jobs(jobs)
    return {"cancelled": True, "job_id": job_id}
