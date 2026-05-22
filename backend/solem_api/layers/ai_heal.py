"""AI HEAL — diagnostica un servizio fallito + chiede a GAVIO un fix.

Single responsibility: SOLO raccogliere logs + stato del servizio + chiamare
GAVIO per un'analisi. Niente esecuzione fix (l'utente conferma).

Estende `autoheal.py`: l'autoheal fa restart automatico (idempotente),
ai_heal fa diagnosi PROFONDA per problemi che restart non risolve.

Flow:
  1. /ai-heal/diagnose/{service} → raccoglie last 80 righe journal +
     systemctl status + dipendenze fallite
  2. POST a /solem/ai/route con prompt strutturato (italiano + step
     specifici per servizio NixOS/systemd)
  3. Ritorna fix proposto (comando shell + spiegazione)
  4. /ai-heal/apply richiede conferma esplicita e esegue solo allowlist
     (systemctl restart, journalctl, nix-collect-garbage, nessun rm).
"""
from __future__ import annotations

import re
import shutil
import subprocess

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/ai-heal", tags=["ai-heal"])

import os
SOLEM_URL = os.environ.get("SOLEM_INTERNAL_URL", "http://127.0.0.1:8001")

# Comandi consentiti per apply automatico (anti-disastro)
ALLOWED_CMD_RE = re.compile(
    r"^(systemctl\s+(restart|reload|status)\s+[a-zA-Z0-9._-]+(\.service)?$"
    r"|journalctl\s+-u\s+[a-zA-Z0-9._-]+(\s+--since\s+'?[^']+'?)?$"
    r"|nix-collect-garbage(\s+-d)?$"
    r"|nixos-rebuild\s+switch(\s+--rollback)?$"
    r")\s*$"
)


class Diagnosis(BaseModel):
    service: str
    active_state: str
    sub_state: str
    n_restarts_recent: int = 0
    journal_excerpt: str = ""
    failed_dependencies: list[str] = Field(default_factory=list)
    detected_at: str


class HealProposal(BaseModel):
    service: str
    diagnosis: Diagnosis
    suggested_command: str
    explanation: str
    confidence: float = Field(..., ge=0.0, le=1.0)
    safe_to_apply: bool


class ApplyRequest(BaseModel):
    service: str
    command: str = Field(..., description="Comando proposto da /diagnose")
    confirm_token: str = Field(..., description="Token preso dalla risposta /diagnose")


# ─── Diagnostica ────────────────────────────────────────────────────────


def _systemctl_show(service: str, prop: str) -> str:
    sc = shutil.which("systemctl")
    if not sc:
        return ""
    try:
        r = subprocess.run([sc, "show", "-p", prop, "--value", service],
                           capture_output=True, text=True, timeout=2, check=False)
        return r.stdout.strip()
    except subprocess.SubprocessError:
        return ""


def _journal_excerpt(service: str, lines: int = 80) -> str:
    jc = shutil.which("journalctl")
    if not jc:
        return "(journalctl non disponibile)"
    try:
        r = subprocess.run([jc, "-u", service, "--no-pager", "-n", str(lines), "--reverse"],
                           capture_output=True, text=True, timeout=5, check=False)
        return r.stdout[:8000]  # cap a 8KB
    except subprocess.SubprocessError:
        return "(errore lettura journal)"


def _failed_deps(service: str) -> list[str]:
    out = _systemctl_show(service, "RequiredBy")
    failed = []
    sc = shutil.which("systemctl")
    if not sc:
        return []
    for dep in out.split():
        try:
            r = subprocess.run([sc, "is-failed", dep], capture_output=True,
                               text=True, timeout=2, check=False)
            if r.stdout.strip() == "failed":
                failed.append(dep)
        except subprocess.SubprocessError:
            continue
    return failed


def _diagnose(service: str) -> Diagnosis:
    from datetime import datetime, timezone
    return Diagnosis(
        service=service,
        active_state=_systemctl_show(service, "ActiveState") or "unknown",
        sub_state=_systemctl_show(service, "SubState") or "unknown",
        n_restarts_recent=int(_systemctl_show(service, "NRestarts") or "0"),
        journal_excerpt=_journal_excerpt(service),
        failed_dependencies=_failed_deps(service),
        detected_at=datetime.now(timezone.utc).isoformat(),
    )


# ─── GAVIO call ───────────────────────────────────────────────────────


async def _ask_gavio(diag: Diagnosis) -> tuple[str, str, float]:
    """Chiede a GAVIO un fix. Ritorna (command, explanation, confidence)."""
    prompt = (
        f"Sei un esperto di NixOS + systemd. Diagnostica questo servizio fallito e "
        f"proponi UN comando per ripararlo. Output STRETTAMENTE in formato:\n"
        f"COMMAND: <comando shell, una linea>\n"
        f"EXPLANATION: <spiegazione in italiano, max 3 frasi>\n"
        f"CONFIDENCE: <0.0-1.0>\n\n"
        f"--- DIAGNOSI ---\n"
        f"service: {diag.service}\n"
        f"active_state: {diag.active_state} ({diag.sub_state})\n"
        f"n_restarts: {diag.n_restarts_recent}\n"
        f"failed_deps: {', '.join(diag.failed_dependencies) or 'none'}\n"
        f"--- JOURNAL ---\n{diag.journal_excerpt[:3000]}\n"
        f"--- VINCOLI ---\n"
        f"- Solo comandi: systemctl restart/reload/status, journalctl, "
        f"nix-collect-garbage, nixos-rebuild switch [--rollback]\n"
        f"- Nessun rm, dd, mkfs, niente.\n"
    )

    async with httpx.AsyncClient(timeout=60.0) as c:
        r = await c.post(
            f"{SOLEM_URL}/solem/ai/route",
            json={
                "messages": [{"role": "user", "content": prompt}],
                "hint": "code",
                "max_tokens": 400,
                "temperature": 0.1,
            },
        )
        if r.status_code != 200:
            return ("systemctl restart " + diag.service,
                    "GAVIO non disponibile: fallback su restart standard.", 0.3)
        raw = r.json().get("content", "")

    cmd_m = re.search(r"COMMAND:\s*(.+?)(?=\nEXPLANATION:|$)", raw, re.DOTALL)
    exp_m = re.search(r"EXPLANATION:\s*(.+?)(?=\nCONFIDENCE:|$)", raw, re.DOTALL)
    conf_m = re.search(r"CONFIDENCE:\s*([0-9.]+)", raw)
    cmd = cmd_m.group(1).strip() if cmd_m else f"systemctl restart {diag.service}"
    exp = exp_m.group(1).strip() if exp_m else "(nessuna spiegazione)"
    conf = float(conf_m.group(1)) if conf_m else 0.5
    return cmd, exp, min(1.0, max(0.0, conf))


# ─── Token confirmation ───────────────────────────────────────────────


def _token(service: str, command: str) -> str:
    import hashlib
    return hashlib.sha256(f"{service}|{command}".encode()).hexdigest()[:16]


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/health", response_model=dict)
async def heal_health() -> dict:
    return {
        "systemctl_available": shutil.which("systemctl") is not None,
        "journalctl_available": shutil.which("journalctl") is not None,
        "allowed_command_pattern": ALLOWED_CMD_RE.pattern,
        "policy": "GAVIO propone, l'utente conferma. Mai rm/dd/mkfs.",
    }


@router.get("/diagnose/{service}", response_model=HealProposal)
async def diagnose(service: str) -> HealProposal:
    # Sanitize service name
    if not re.match(r"^[a-zA-Z0-9._-]+$", service):
        raise HTTPException(400, {"code": "invalid_service_name"})

    diag = _diagnose(service)
    if diag.active_state == "active" and not diag.failed_dependencies:
        return HealProposal(
            service=service, diagnosis=diag,
            suggested_command=f"# servizio già OK",
            explanation=f"{service} è già attivo e nessuna dipendenza è fallita. Nessun fix necessario.",
            confidence=1.0,
            safe_to_apply=False,
        )

    cmd, exp, conf = await _ask_gavio(diag)
    safe = bool(ALLOWED_CMD_RE.match(cmd.strip().lstrip("$").strip()))

    return HealProposal(
        service=service,
        diagnosis=diag,
        suggested_command=cmd,
        explanation=exp,
        confidence=conf,
        safe_to_apply=safe,
    )


@router.post("/apply", response_model=dict)
async def apply(req: ApplyRequest) -> dict:
    # Verifica token (lega comando e service)
    expected = _token(req.service, req.command)
    if not req.confirm_token or req.confirm_token != expected:
        raise HTTPException(403, {
            "code": "invalid_confirm_token",
            "hint": "Calcola sha256(service|command)[:16] e ripassa.",
        })

    cmd = req.command.strip().lstrip("$").strip()
    if not ALLOWED_CMD_RE.match(cmd):
        raise HTTPException(403, {
            "code": "command_not_in_allowlist",
            "command": cmd,
            "allowed_pattern": ALLOWED_CMD_RE.pattern,
        })

    sudo = shutil.which("sudo")
    if not sudo:
        raise HTTPException(503, {"code": "sudo_not_available"})

    parts = cmd.split()
    try:
        r = subprocess.run([sudo, "-n"] + parts, capture_output=True,
                           text=True, timeout=30, check=False)
        return {
            "executed": True,
            "command": cmd,
            "rc": r.returncode,
            "stdout": r.stdout[:2000],
            "stderr": r.stderr[:2000],
        }
    except subprocess.SubprocessError as e:
        raise HTTPException(500, {"code": "execution_failed", "error": str(e)})
