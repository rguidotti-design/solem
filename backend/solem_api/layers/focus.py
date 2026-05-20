"""FOCUS — focus mode: blocca distrazioni + pomodoro timer.

Single responsibility: SOLO orchestrare sessione focus. Lo blocco DNS
delega a /etc/hosts override temporaneo (richiede root, sudo NOPASSWD).

Workflow:
  1. POST /focus/start {duration_min, blocklist, allow}
     → append /etc/hosts.solem-focus entries 0.0.0.0 social.com ...
     → reload nss
     → schedula auto-stop a +duration_min
  2. POST /focus/stop
     → restore /etc/hosts
     → notify "focus terminato"

Endpoint:
  POST /focus/start
  POST /focus/stop
  GET  /focus/status
  GET  /focus/blocklists  — preset (social, news, gaming, all)
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/focus", tags=["focus-mode"])

STATE_FILE = Path("/var/lib/solem/focus.json")
HOSTS_FOCUS = Path("/etc/hosts.solem-focus")

PRESET_BLOCKLISTS = {
    "social": [
        "facebook.com", "www.facebook.com", "instagram.com", "www.instagram.com",
        "twitter.com", "x.com", "tiktok.com", "www.tiktok.com",
        "reddit.com", "www.reddit.com",
    ],
    "news": [
        "repubblica.it", "corriere.it", "ansa.it", "ilfattoquotidiano.it",
        "cnn.com", "bbc.com", "news.ycombinator.com",
    ],
    "gaming": [
        "twitch.tv", "www.twitch.tv", "youtube.com", "www.youtube.com",
        "steamcommunity.com", "steam.com",
    ],
    "shopping": [
        "amazon.com", "amazon.it", "ebay.it", "ebay.com",
    ],
}


class FocusStart(BaseModel):
    duration_minutes: int = Field(25, ge=5, le=480)
    presets: list[str] = Field(default_factory=lambda: ["social"])
    custom_domains: list[str] = Field(default_factory=list)
    allow_override: bool = Field(False, description="Permetti POST /stop prima della scadenza")


class FocusStatus(BaseModel):
    active: bool
    started_at: str | None = None
    ends_at: str | None = None
    remaining_seconds: int = 0
    blocked_domains: list[str] = Field(default_factory=list)
    presets: list[str] = Field(default_factory=list)


def _load_state() -> dict:
    if not STATE_FILE.exists():
        return {"active": False}
    try:
        return json.loads(STATE_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        return {"active": False}


def _save_state(s: dict) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(s, indent=2))


def _write_hosts(domains: list[str]) -> None:
    lines = ["# SOLEM focus mode — auto-generated, ripristinato a fine sessione"]
    for d in domains:
        lines.append(f"0.0.0.0 {d}")
        lines.append(f"::      {d}")
    sudo = shutil.which("sudo")
    if not sudo:
        raise HTTPException(503, {"code": "sudo_unavailable"})
    content = "\n".join(lines) + "\n"
    # Scrive in /etc/hosts.solem-focus + sudo cat per merge in /etc/hosts
    HOSTS_FOCUS.write_text(content, encoding="utf-8")
    # Append a /etc/hosts (idempotente: rimuove blocco precedente)
    try:
        original = Path("/etc/hosts").read_text(encoding="utf-8")
        # Rimuovi vecchio blocco
        stripped = "\n".join(
            line for line in original.splitlines()
            if not line.startswith("# SOLEM-FOCUS")
        ) + "\n"
        merged = stripped + "# SOLEM-FOCUS-BEGIN\n" + content + "# SOLEM-FOCUS-END\n"
        # Richiede sudo write
        subprocess.run([sudo, "-n", "tee", "/etc/hosts"], input=merged, text=True,
                       capture_output=True, timeout=5, check=False)
    except OSError as e:
        raise HTTPException(500, {"code": "hosts_write_failed", "error": str(e)})


def _clear_hosts() -> None:
    sudo = shutil.which("sudo")
    if not sudo:
        return
    try:
        original = Path("/etc/hosts").read_text(encoding="utf-8")
        in_block = False
        kept: list[str] = []
        for line in original.splitlines():
            if line == "# SOLEM-FOCUS-BEGIN":
                in_block = True
                continue
            if line == "# SOLEM-FOCUS-END":
                in_block = False
                continue
            if not in_block:
                kept.append(line)
        subprocess.run([sudo, "-n", "tee", "/etc/hosts"],
                       input="\n".join(kept) + "\n", text=True,
                       capture_output=True, timeout=5, check=False)
    except OSError:
        pass


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/health", response_model=dict)
async def focus_health() -> dict:
    s = _load_state()
    return {
        "active": s.get("active", False),
        "available_presets": list(PRESET_BLOCKLISTS.keys()),
    }


@router.get("/blocklists", response_model=dict)
async def list_presets() -> dict:
    return PRESET_BLOCKLISTS


@router.post("/start", response_model=FocusStatus)
async def start(req: FocusStart) -> FocusStatus:
    s = _load_state()
    if s.get("active"):
        raise HTTPException(409, {"code": "focus_already_active", "since": s.get("started_at")})

    domains: list[str] = []
    for p in req.presets:
        domains.extend(PRESET_BLOCKLISTS.get(p, []))
    domains.extend(req.custom_domains)
    domains = sorted(set(domains))

    _write_hosts(domains)

    started_ts = time.time()
    ends_ts = started_ts + req.duration_minutes * 60
    new_state = {
        "active": True,
        "started_at_ts": started_ts,
        "ends_at_ts": ends_ts,
        "blocked_domains": domains,
        "presets": req.presets,
        "allow_override": req.allow_override,
    }
    _save_state(new_state)

    return FocusStatus(
        active=True,
        started_at=datetime.fromtimestamp(started_ts, tz=timezone.utc).isoformat(),
        ends_at=datetime.fromtimestamp(ends_ts, tz=timezone.utc).isoformat(),
        remaining_seconds=int(ends_ts - started_ts),
        blocked_domains=domains,
        presets=req.presets,
    )


@router.post("/stop", response_model=FocusStatus)
async def stop() -> FocusStatus:
    s = _load_state()
    if not s.get("active"):
        return FocusStatus(active=False)
    if not s.get("allow_override"):
        remaining = int(s.get("ends_at_ts", 0) - time.time())
        if remaining > 0:
            raise HTTPException(403, {
                "code": "focus_locked_until_end",
                "remaining_seconds": remaining,
                "hint": "Sessione locked. Riavvia il pc per emergenza.",
            })
    _clear_hosts()
    _save_state({"active": False})
    return FocusStatus(active=False)


@router.get("/status", response_model=FocusStatus)
async def status() -> FocusStatus:
    s = _load_state()
    if not s.get("active"):
        return FocusStatus(active=False)
    now = time.time()
    ends = s.get("ends_at_ts", 0)
    if now >= ends:
        # Auto-stop
        _clear_hosts()
        _save_state({"active": False})
        return FocusStatus(active=False)
    return FocusStatus(
        active=True,
        started_at=datetime.fromtimestamp(s["started_at_ts"], tz=timezone.utc).isoformat(),
        ends_at=datetime.fromtimestamp(ends, tz=timezone.utc).isoformat(),
        remaining_seconds=int(ends - now),
        blocked_domains=s.get("blocked_domains", []),
        presets=s.get("presets", []),
    )
