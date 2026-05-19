"""KILL SWITCH — emergenza stop (M2.5 anticipato).

Ferma tutti gli agenti AI + servizi pericolosi. Triggerabile da:
  - CLI: `solem panic`
  - API: POST /solem/panic
  - Hotkey desktop (Step 2+ con Hyprland binding Super+Shift+K)

Effetti:
  1. Disabilita tutti gli agenti (active=0)
  2. Revoca tutte le sessioni attive (utenti devono ri-loggarsi)
  3. Stop systemd gavio.service
  4. Publish evento bus L3 "system.panic_triggered"
  5. Audit log immutabile
"""
from __future__ import annotations

import subprocess
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter
from pydantic import BaseModel, Field

from .db import get_conn, tx

router = APIRouter(prefix="/panic", tags=["panic"])


class PanicRequest(BaseModel):
    reason: str = Field("manual_kill_switch", description="Motivo per audit log")
    stop_gavio: bool = True
    deactivate_agents: bool = True
    revoke_sessions: bool = True


class PanicResponse(BaseModel):
    triggered_at: str
    actions: list[str]
    success: bool


@router.post("", response_model=PanicResponse)
async def panic(req: PanicRequest | None = None) -> PanicResponse:
    if req is None:
        req = PanicRequest()

    actions: list[str] = []
    success = True
    c = get_conn()

    # 1. Deactivate agents
    if req.deactivate_agents:
        try:
            with tx() as t:
                cur = t.execute("UPDATE agents SET active = 0 WHERE id != 'gavio'")
                actions.append(f"agents_deactivated={cur.rowcount}")
        except Exception as e:
            actions.append(f"agents_error={e}")
            success = False

    # 2. Revoke sessions
    if req.revoke_sessions:
        try:
            with tx() as t:
                cur = t.execute(
                    "UPDATE sessions SET revoked_at = datetime('now') WHERE revoked_at IS NULL"
                )
                actions.append(f"sessions_revoked={cur.rowcount}")
        except Exception as e:
            actions.append(f"sessions_error={e}")
            success = False

    # 3. Stop gavio.service via systemctl (richiede sudo, gavio user ha NOPASSWD)
    if req.stop_gavio:
        try:
            out = subprocess.run(
                ["sudo", "-n", "systemctl", "stop", "gavio.service"],
                capture_output=True, text=True, timeout=10, check=False,
            )
            actions.append(f"gavio_stop={'ok' if out.returncode == 0 else 'fail:' + out.stderr.strip()[:80]}")
            if out.returncode != 0:
                success = False
        except subprocess.SubprocessError as e:
            actions.append(f"gavio_error={e}")
            success = False

    # 4. Publish event bus L3
    try:
        from . import events
        await events.publish(events.Event(
            source="solem.panic",
            topic="system.panic_triggered",
            payload={"reason": req.reason, "actions": actions},
        ))
        actions.append("event_published")
    except Exception:
        pass

    # 5. Audit immutable
    try:
        from . import constitution
        constitution._ensure_table()
        with tx() as t:
            t.execute(
                """INSERT INTO constitution_audit
                   (agent_id, action, target, command, outcome, reason, matched_rule)
                   VALUES ('system', 'system.panic', NULL, NULL, 'allowed', ?, 'kill_switch')""",
                (req.reason,),
            )
    except Exception:
        pass

    return PanicResponse(
        triggered_at=datetime.now(timezone.utc).isoformat(),
        actions=actions,
        success=success,
    )


@router.post("/recover", response_model=dict)
async def recover() -> dict:
    """Recover post-panic: riavvia gavio.service + reattiva agents."""
    actions = []
    try:
        out = subprocess.run(
            ["sudo", "-n", "systemctl", "start", "gavio.service"],
            capture_output=True, text=True, timeout=10, check=False,
        )
        actions.append(f"gavio_start={'ok' if out.returncode == 0 else 'fail'}")
    except subprocess.SubprocessError as e:
        actions.append(f"gavio_error={e}")

    with tx() as t:
        cur = t.execute("UPDATE agents SET active = 1 WHERE id != 'gavio' AND id IN ('coder','researcher','writer')")
        actions.append(f"agents_reactivated={cur.rowcount}")

    return {"recovered": True, "actions": actions}
