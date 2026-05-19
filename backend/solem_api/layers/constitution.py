"""CONSTITUTIONAL LAYER — regole inviolabili per AI (ADR-006).

Triple-defense:
  1. File dichiarativo Nix `/etc/gavio/constitution.json` (generato da modulo)
  2. SOLEM gateway: ogni azione AI passa per /solem/constitution/check
  3. GAVIO `safety.py` (Step 2) come enforcer interno fallback

Endpoint:
  GET  /constitution            — lista regole correnti
  POST /constitution/check      — valida un'azione (allow/deny/require_confirm)
  GET  /constitution/violations — storico violazioni audit
"""
from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from .db import get_conn, tx

router = APIRouter(prefix="/constitution", tags=["constitution"])

CONSTITUTION_FILE = Path("/etc/gavio/constitution.json")

# Default constitution se file mancante (safety net hardcoded)
DEFAULT_CONSTITUTION = {
    "version": 1,
    "forbidden_actions": [
        {"pattern": r"^rm\s+-rf\s+/(home|etc|nix|var)(/|$)", "reason": "Distruzione dati sistema/utente"},
        {"pattern": r"^dd\s+.*of=/dev/(sd|nvme|hd)", "reason": "Scrittura raw a device fisico"},
        {"pattern": r"^mkfs\.", "reason": "Format filesystem"},
        {"pattern": r":\(\)\{\s*:\|:&\s*\};:", "reason": "Fork bomb"},
    ],
    "require_two_factor": [
        "filesystem.delete_home",
        "filesystem.delete_etc",
        "network.outbound.new_domain",
        "system.shutdown",
        "system.reboot",
        "user.password_change",
        "agent.deactivate_primary",
    ],
    "require_user_confirm": [
        "send_message",
        "execute_subprocess",
        "filesystem.write_outside_workspace",
        "network.outbound.unknown_domain",
    ],
    "always_allowed": [
        "filesystem.read",
        "solem.identity.read",
        "solem.context.read",
        "solem.capabilities.discover",
        "solem.memory.read",
    ],
}


class CheckRequest(BaseModel):
    action: str = Field(..., description="ID azione, es. 'system.shutdown' o 'filesystem.delete'")
    target: str | None = Field(None, description="Target azione, es. '/home/user/file' o 'gavio'")
    command: str | None = Field(None, description="Comando shell se applicabile")
    agent_id: str = Field("gavio", description="Agente che richiede l'azione")
    context: dict[str, Any] = Field(default_factory=dict)


class CheckResponse(BaseModel):
    allowed: bool
    reason: str
    requires: Literal["none", "user_confirm", "two_factor"] = "none"
    matched_rule: str | None = None
    audit_id: int | None = None


class Violation(BaseModel):
    id: int
    ts: str
    agent_id: str
    action: str
    target: str | None = None
    command: str | None = None
    reason: str


# ─── DB ────────────────────────────────────────────────────────────


def _ensure_table() -> None:
    c = get_conn()
    c.execute("""
    CREATE TABLE IF NOT EXISTS constitution_audit (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        ts            TEXT NOT NULL DEFAULT (datetime('now')),
        agent_id      TEXT NOT NULL,
        action        TEXT NOT NULL,
        target        TEXT,
        command       TEXT,
        outcome       TEXT NOT NULL CHECK(outcome IN ('allowed','denied','confirm','two_factor')),
        reason        TEXT NOT NULL,
        matched_rule  TEXT
    );
    """)


# ─── Helpers ────────────────────────────────────────────────────────


def _load_constitution() -> dict:
    if CONSTITUTION_FILE.exists():
        try:
            return json.loads(CONSTITUTION_FILE.read_text())
        except json.JSONDecodeError:
            pass
    return DEFAULT_CONSTITUTION


def _audit(outcome: str, req: CheckRequest, reason: str, matched: str | None) -> int:
    _ensure_table()
    with tx() as t:
        cur = t.execute(
            """INSERT INTO constitution_audit
               (agent_id, action, target, command, outcome, reason, matched_rule)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (req.agent_id, req.action, req.target, req.command, outcome, reason, matched),
        )
        return cur.lastrowid or 0


# ─── Endpoints ───────────────────────────────────────────────────────


@router.get("", response_model=dict)
async def get_constitution() -> dict:
    return _load_constitution()


@router.post("/check", response_model=CheckResponse)
async def check_action(req: CheckRequest) -> CheckResponse:
    """Valida un'azione contro la constitution corrente.

    Ordine valutazione:
      1. Comando matcha pattern forbidden_actions → DENY immediato
      2. Action è in always_allowed → ALLOW
      3. Action è in require_two_factor → confirm con 2FA
      4. Action è in require_user_confirm → confirm
      5. Default: ALLOW (permissivo per Step 0; Step 2+ default deny + allowlist)
    """
    rules = _load_constitution()

    # 1. Forbidden pattern check (sul command shell)
    if req.command:
        for rule in rules.get("forbidden_actions", []):
            if re.search(rule["pattern"], req.command):
                audit_id = _audit("denied", req, rule["reason"], rule["pattern"])
                return CheckResponse(
                    allowed=False,
                    reason=rule["reason"],
                    matched_rule=rule["pattern"],
                    audit_id=audit_id,
                )

    # 2. Always allowed
    if req.action in rules.get("always_allowed", []):
        audit_id = _audit("allowed", req, "azione sempre consentita", req.action)
        return CheckResponse(allowed=True, reason="azione sempre consentita", audit_id=audit_id)

    # 3. Two-factor
    if req.action in rules.get("require_two_factor", []):
        audit_id = _audit("two_factor", req, "richiede 2FA", req.action)
        return CheckResponse(
            allowed=True,
            reason="azione consentita con 2FA",
            requires="two_factor",
            matched_rule=req.action,
            audit_id=audit_id,
        )

    # 4. User confirm
    if req.action in rules.get("require_user_confirm", []):
        audit_id = _audit("confirm", req, "richiede conferma utente", req.action)
        return CheckResponse(
            allowed=True,
            reason="azione consentita con conferma",
            requires="user_confirm",
            matched_rule=req.action,
            audit_id=audit_id,
        )

    # 5. Default Step 0: allow (Step 2+: default deny)
    audit_id = _audit("allowed", req, "default Step 0 permissivo", None)
    return CheckResponse(allowed=True, reason="default allow (Step 0)", audit_id=audit_id)


@router.get("/violations", response_model=list[Violation])
async def list_violations(limit: int = 50) -> list[Violation]:
    _ensure_table()
    c = get_conn()
    rows = c.execute(
        """SELECT id, ts, agent_id, action, target, command, reason
           FROM constitution_audit
           WHERE outcome = 'denied'
           ORDER BY ts DESC LIMIT ?""",
        (limit,),
    ).fetchall()
    return [
        Violation(
            id=r["id"], ts=r["ts"], agent_id=r["agent_id"],
            action=r["action"], target=r["target"],
            command=r["command"], reason=r["reason"],
        )
        for r in rows
    ]
