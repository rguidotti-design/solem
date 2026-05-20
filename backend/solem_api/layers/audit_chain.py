"""AUDIT CHAIN — append-only log con checksum chain (tamper-evident).

Single responsibility: SOLO scrivere eventi audit in modo append-only +
catena di hash. Ogni record contiene `prev_hash` del record precedente.
Modificare un record nel mezzo rompe la catena → tampering rilevato.

Storage: /var/log/solem/audit.jsonl (UNA riga per evento).
Verifica: ricalcola la catena, confronta hash. /audit/verify lo fa.

Niente cloud forwarding (privacy). Niente firma asimmetrica per ora
(solo SHA256 chain). Per firma vera → integra con `auth_keys.py`
(ed25519) in passi futuri.

Endpoint:
  POST /audit/log           — appendi evento
  GET  /audit/recent        — ultimi N record
  GET  /audit/verify        — verifica integrità chain
  GET  /audit/by-actor/{u}  — eventi di un utente
"""
from __future__ import annotations

import hashlib
import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/audit", tags=["audit-chain"])

LOG_FILE = Path(os.environ.get("SOLEM_AUDIT_LOG", "/var/log/solem/audit.jsonl"))
GENESIS_HASH = "0" * 64  # primo record


class AuditEvent(BaseModel):
    actor: str = Field(..., description="username SOLEM o 'system'/'gavio'")
    action: str = Field(..., description="es. 'secret.read', 'cluster.dispatch', 'login.success'")
    target: str = Field("", description="es. 'secret:api_key', 'device:laptop'")
    details: dict = Field(default_factory=dict)
    severity: str = Field("info", description="info|warning|critical")


class AuditRecord(BaseModel):
    seq: int
    ts: float
    iso_time: str
    actor: str
    action: str
    target: str
    details: dict
    severity: str
    prev_hash: str
    this_hash: str


def _hash_record(seq: int, ts: float, ev: AuditEvent, prev_hash: str) -> str:
    payload = json.dumps({
        "seq": seq, "ts": ts,
        "actor": ev.actor, "action": ev.action,
        "target": ev.target, "details": ev.details,
        "severity": ev.severity,
        "prev_hash": prev_hash,
    }, sort_keys=True).encode()
    return hashlib.sha256(payload).hexdigest()


def _last_record() -> tuple[int, str]:
    """Ritorna (last_seq, last_hash)."""
    if not LOG_FILE.exists():
        return 0, GENESIS_HASH
    last_line = None
    with LOG_FILE.open("rb") as f:
        # Read last line efficient
        try:
            f.seek(-2, os.SEEK_END)
            while f.read(1) != b"\n":
                f.seek(-2, os.SEEK_CUR)
        except OSError:
            f.seek(0)
        last_line = f.readline().decode("utf-8", errors="replace").strip()
    if not last_line:
        return 0, GENESIS_HASH
    try:
        rec = json.loads(last_line)
        return rec.get("seq", 0), rec.get("this_hash", GENESIS_HASH)
    except json.JSONDecodeError:
        return 0, GENESIS_HASH


def _append(record: AuditRecord) -> None:
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    with LOG_FILE.open("a", encoding="utf-8") as f:
        f.write(record.model_dump_json() + "\n")


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/health", response_model=dict)
async def audit_health() -> dict:
    last_seq, last_hash = _last_record()
    return {
        "log_file": str(LOG_FILE),
        "total_records": last_seq,
        "last_hash_preview": last_hash[:16] + "..." if last_hash != GENESIS_HASH else "(genesis)",
        "tamper_evident": True,
    }


@router.post("/log", response_model=AuditRecord)
async def log(ev: AuditEvent) -> AuditRecord:
    last_seq, last_hash = _last_record()
    seq = last_seq + 1
    ts = time.time()
    this_hash = _hash_record(seq, ts, ev, last_hash)
    record = AuditRecord(
        seq=seq, ts=ts,
        iso_time=datetime.fromtimestamp(ts, tz=timezone.utc).isoformat(),
        actor=ev.actor, action=ev.action, target=ev.target,
        details=ev.details, severity=ev.severity,
        prev_hash=last_hash, this_hash=this_hash,
    )
    _append(record)
    return record


@router.get("/recent", response_model=list[AuditRecord])
async def recent(limit: int = 100) -> list[AuditRecord]:
    if not LOG_FILE.exists():
        return []
    lines = LOG_FILE.read_text(encoding="utf-8", errors="replace").splitlines()
    out: list[AuditRecord] = []
    for line in lines[-limit:]:
        try:
            out.append(AuditRecord(**json.loads(line)))
        except (json.JSONDecodeError, ValueError):
            continue
    return out


@router.get("/by-actor/{actor}", response_model=list[AuditRecord])
async def by_actor(actor: str, limit: int = 50) -> list[AuditRecord]:
    if not LOG_FILE.exists():
        return []
    out: list[AuditRecord] = []
    for line in LOG_FILE.read_text(encoding="utf-8", errors="replace").splitlines():
        try:
            rec = json.loads(line)
            if rec.get("actor") == actor:
                out.append(AuditRecord(**rec))
        except (json.JSONDecodeError, ValueError):
            continue
    return out[-limit:]


@router.get("/verify", response_model=dict)
async def verify() -> dict:
    """Verifica integrità della chain. O(N)."""
    if not LOG_FILE.exists():
        return {"valid": True, "records": 0, "note": "log vuoto"}

    prev_hash = GENESIS_HASH
    expected_seq = 1
    bad: list[dict] = []
    total = 0

    for line in LOG_FILE.read_text(encoding="utf-8", errors="replace").splitlines():
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            bad.append({"line": total, "reason": "json_decode_error"})
            total += 1
            continue
        total += 1

        # Check seq monotonico
        if rec.get("seq") != expected_seq:
            bad.append({
                "seq": rec.get("seq"), "expected": expected_seq, "reason": "seq_mismatch",
            })

        # Ricalcola hash atteso
        ev = AuditEvent(
            actor=rec.get("actor", ""), action=rec.get("action", ""),
            target=rec.get("target", ""), details=rec.get("details", {}),
            severity=rec.get("severity", "info"),
        )
        expected_hash = _hash_record(rec.get("seq", 0), rec.get("ts", 0), ev, prev_hash)
        if rec.get("this_hash") != expected_hash:
            bad.append({
                "seq": rec.get("seq"), "reason": "hash_mismatch",
                "actual": rec.get("this_hash", "")[:16],
                "expected": expected_hash[:16],
            })

        # Check prev_hash matches
        if rec.get("prev_hash") != prev_hash:
            bad.append({
                "seq": rec.get("seq"), "reason": "broken_chain",
            })

        prev_hash = rec.get("this_hash", GENESIS_HASH)
        expected_seq += 1

    return {
        "valid": len(bad) == 0,
        "records": total,
        "tampering_detected": bad[:20],
        "total_anomalies": len(bad),
    }
