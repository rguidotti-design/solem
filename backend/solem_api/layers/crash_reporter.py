"""CRASH REPORTER — raccolta locale crash systemd + ABRT-style.

Single responsibility: SOLO collect+list+annotate crash. Niente upload
remoto: i crash report restano in /var/lib/solem/crashes/ e l'utente li
condivide manualmente (privacy by default).

Sorgenti scansionate:
  - journalctl -p err     (errori systemd ultimi 7gg)
  - /var/lib/systemd/coredump   (coredump systemd-coredump)
  - solem-api errors      (lette dal proprio log strutturato)

Endpoint:
  GET  /crashes                  — lista report
  GET  /crashes/{id}             — dettaglio singolo
  POST /crashes/{id}/redact      — redact PII prima di shareare
  DELETE /crashes/{id}           — rimuove report
  POST /crashes/export           — bundle .tar.gz di tutti i report
"""
from __future__ import annotations

import json
import shutil
import subprocess
import tarfile
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel

router = APIRouter(prefix="/crashes", tags=["crash-reporter"])

CRASH_DIR = Path("/var/lib/solem/crashes")


class CrashReport(BaseModel):
    id: str
    detected_at: str
    source: str  # journald|coredump|api-log
    unit: str | None = None
    summary: str
    severity: str = "error"  # warning|error|critical
    redacted: bool = False
    size_bytes: int


class ExportInfo(BaseModel):
    path: str
    total_reports: int
    size_bytes: int


def _ensure_dir() -> None:
    CRASH_DIR.mkdir(parents=True, exist_ok=True)


def _id_from_meta(detected_at: str, source: str, summary: str) -> str:
    import hashlib
    h = hashlib.sha256(f"{detected_at}|{source}|{summary}".encode()).hexdigest()
    return h[:16]


def _scan_journald(hours: int = 168) -> list[CrashReport]:
    """journalctl -p err --since=NUM hours"""
    journalctl = shutil.which("journalctl")
    if not journalctl:
        return []
    try:
        r = subprocess.run(
            [journalctl, "-p", "err", "--since", f"{hours} hours ago", "-o", "json", "--no-pager"],
            capture_output=True, text=True, timeout=10, check=False,
        )
    except subprocess.SubprocessError:
        return []

    reports: list[CrashReport] = []
    for line in r.stdout.splitlines():
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        msg = entry.get("MESSAGE", "")
        unit = entry.get("_SYSTEMD_UNIT", "?")
        ts = entry.get("__REALTIME_TIMESTAMP", "")
        try:
            iso = datetime.fromtimestamp(int(ts) / 1_000_000, tz=timezone.utc).isoformat()
        except (ValueError, OverflowError):
            iso = datetime.now(timezone.utc).isoformat()

        cid = _id_from_meta(iso, "journald", msg[:120])
        reports.append(CrashReport(
            id=cid,
            detected_at=iso,
            source="journald",
            unit=unit,
            summary=msg[:240],
            size_bytes=len(msg),
        ))
    return reports[-100:]  # cap a 100 più recenti


def _scan_coredumps() -> list[CrashReport]:
    """coredumpctl list"""
    coredumpctl = shutil.which("coredumpctl")
    if not coredumpctl:
        return []
    try:
        r = subprocess.run(
            [coredumpctl, "list", "--no-pager", "--json=short"],
            capture_output=True, text=True, timeout=5, check=False,
        )
        data = json.loads(r.stdout) if r.stdout.strip() else []
    except (subprocess.SubprocessError, json.JSONDecodeError):
        return []

    reports: list[CrashReport] = []
    for c in data if isinstance(data, list) else []:
        ts = c.get("time", "")
        exe = c.get("exe", "?")
        summary = f"coredump: {exe} (sig={c.get('signal', '?')})"
        cid = _id_from_meta(str(ts), "coredump", summary)
        reports.append(CrashReport(
            id=cid,
            detected_at=str(ts),
            source="coredump",
            unit=exe,
            summary=summary,
            severity="critical",
            size_bytes=int(c.get("size", 0)),
        ))
    return reports


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/health", response_model=dict)
async def crash_health() -> dict:
    _ensure_dir()
    return {
        "crash_dir": str(CRASH_DIR),
        "saved_reports": len(list(CRASH_DIR.glob("*.json"))),
        "policy": "local-only, no telemetry, user-export only",
    }


@router.get("", response_model=list[CrashReport])
async def list_crashes(hours: int = 168) -> list[CrashReport]:
    _ensure_dir()
    out: list[CrashReport] = []
    out.extend(_scan_journald(hours))
    out.extend(_scan_coredumps())

    # Persist sintesi su disk per audit
    for r in out:
        f = CRASH_DIR / f"{r.id}.json"
        if not f.exists():
            f.write_text(r.model_dump_json(indent=2))

    return out


@router.get("/{crash_id}", response_model=CrashReport)
async def get_crash(crash_id: str) -> CrashReport:
    f = CRASH_DIR / f"{crash_id}.json"
    if not f.exists():
        raise HTTPException(404, {"code": "crash_not_found"})
    return CrashReport.model_validate_json(f.read_text())


@router.delete("/{crash_id}")
async def delete_crash(crash_id: str) -> dict:
    f = CRASH_DIR / f"{crash_id}.json"
    if not f.exists():
        raise HTTPException(404, {"code": "crash_not_found"})
    f.unlink()
    return {"deleted": True, "id": crash_id}


@router.post("/{crash_id}/redact", response_model=CrashReport)
async def redact_crash(crash_id: str) -> CrashReport:
    """Maschera PII (email, IP, path /home/*) prima dello share manuale."""
    import re
    f = CRASH_DIR / f"{crash_id}.json"
    if not f.exists():
        raise HTTPException(404, {"code": "crash_not_found"})
    rep = CrashReport.model_validate_json(f.read_text())

    s = rep.summary
    s = re.sub(r"[\w\.-]+@[\w\.-]+", "<email>", s)
    s = re.sub(r"\b\d{1,3}(?:\.\d{1,3}){3}\b", "<ip>", s)
    s = re.sub(r"/home/[^/\s]+", "/home/<user>", s)
    s = re.sub(r"/root/[^/\s]*", "/root/<redacted>", s)
    rep.summary = s
    rep.redacted = True

    f.write_text(rep.model_dump_json(indent=2))
    return rep


@router.post("/export")
async def export_all() -> FileResponse:
    _ensure_dir()
    out_path = CRASH_DIR.parent / f"crashes-export-{datetime.now().strftime('%Y%m%d-%H%M%S')}.tar.gz"
    with tarfile.open(out_path, "w:gz") as tar:
        for f in CRASH_DIR.glob("*.json"):
            tar.add(f, arcname=f.name)
    return FileResponse(out_path, media_type="application/gzip", filename=out_path.name)
