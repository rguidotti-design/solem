"""HANDOFF — Continuity tra device della mesh.

Single responsibility: SOLO trasferire "task in corso" da un device a
un altro dello stesso account. Inizia su Beelink → finisci su iPhone
(o viceversa).

Task = (kind, payload, owner_username, current_device_id).
kind tipici: open_url, edit_doc, watch_video, chat_thread, file_action.

Flow:
  1. Device A pubblica un handoff:
       POST /handoff/push { kind, payload, target_device_id }
  2. Device B (target) fa polling:
       GET /handoff/pending?device_id=B
     oppure subscribe a /handoff/stream (SSE)
  3. Device B prende un task:
       POST /handoff/claim/{handoff_id}
     Il task scompare dalla coda.

Esempio:
  - Inizio a leggere un PDF sul laptop → handoff push con kind=open_url,
    payload={url: "file:///.../report.pdf", scroll: 0.43}
  - Apro smartphone → riceve l'handoff → apre PDF al 43%.

100% locale, mesh-only. FOSS, 0 €.
"""
from __future__ import annotations

import json
import secrets
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/handoff", tags=["handoff-continuity"])

HANDOFF_FILE = Path("/var/lib/solem/handoff.json")
HANDOFF_TTL_SEC = 600  # 10 min: i task vecchi scadono


HandoffKind = Literal[
    "open_url", "edit_doc", "watch_video", "chat_thread",
    "file_action", "copy_text", "shell_command", "generic",
]


class HandoffPush(BaseModel):
    kind: HandoffKind = "generic"
    payload: dict = Field(default_factory=dict, description="Stato del task (url, scroll, ...)")
    owner_username: str = Field(..., description="Account SOLEM (per filtrare device del proprietario)")
    source_device_id: str = Field(..., description="Da quale device parte")
    target_device_id: str | None = Field(None, description="None = qualunque device del owner")
    title: str = Field("Handoff", max_length=120)
    description: str = Field("", max_length=400)


class HandoffItem(BaseModel):
    id: str
    kind: HandoffKind
    payload: dict
    owner_username: str
    source_device_id: str
    target_device_id: str | None
    title: str
    description: str
    created_at: str
    expires_at: float
    claimed_at: str | None = None
    claimed_by: str | None = None


def _load() -> dict:
    if not HANDOFF_FILE.exists():
        return {"items": {}}
    try:
        return json.loads(HANDOFF_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        return {"items": {}}


def _save(state: dict) -> None:
    HANDOFF_FILE.parent.mkdir(parents=True, exist_ok=True)
    HANDOFF_FILE.write_text(json.dumps(state, indent=2))


def _gc(state: dict) -> dict:
    now = time.time()
    state["items"] = {
        k: v for k, v in state["items"].items()
        if v.get("expires_at", 0) > now and not v.get("claimed_at")
    }
    return state


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/health", response_model=dict)
async def hand_health() -> dict:
    state = _gc(_load())
    _save(state)
    return {
        "pending_items": len(state["items"]),
        "ttl_sec": HANDOFF_TTL_SEC,
        "policy": "mesh-only, no cloud, auto-expire 10 min",
    }


@router.post("/push", response_model=HandoffItem)
async def push(req: HandoffPush) -> HandoffItem:
    state = _gc(_load())
    hid = secrets.token_urlsafe(12)
    item = {
        "id": hid,
        "kind": req.kind,
        "payload": req.payload,
        "owner_username": req.owner_username,
        "source_device_id": req.source_device_id,
        "target_device_id": req.target_device_id,
        "title": req.title,
        "description": req.description,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "expires_at": time.time() + HANDOFF_TTL_SEC,
        "claimed_at": None,
        "claimed_by": None,
    }
    state["items"][hid] = item
    _save(state)
    return HandoffItem(**item)


@router.get("/pending", response_model=list[HandoffItem])
async def pending(device_id: str, owner_username: str | None = None) -> list[HandoffItem]:
    """Lista handoff disponibili per questo device.

    Filtra per owner (se passato) e accetta task con target = device_id
    o target = None (broadcast a tutti i device del proprietario).
    """
    state = _gc(_load())
    _save(state)
    out: list[HandoffItem] = []
    for v in state["items"].values():
        if v.get("claimed_at"):
            continue
        if owner_username and v["owner_username"] != owner_username:
            continue
        tgt = v.get("target_device_id")
        if tgt is None or tgt == device_id:
            # Non rimandare al device che l'ha pubblicato
            if v["source_device_id"] != device_id:
                out.append(HandoffItem(**v))
    return sorted(out, key=lambda h: h.created_at, reverse=True)


@router.post("/claim/{handoff_id}", response_model=HandoffItem)
async def claim(handoff_id: str, device_id: str) -> HandoffItem:
    state = _load()
    item = state["items"].get(handoff_id)
    if not item:
        raise HTTPException(404, {"code": "handoff_not_found"})
    if item.get("claimed_at"):
        raise HTTPException(409, {"code": "already_claimed", "by": item["claimed_by"]})
    item["claimed_at"] = datetime.now(timezone.utc).isoformat()
    item["claimed_by"] = device_id
    state["items"][handoff_id] = item
    _save(state)
    return HandoffItem(**item)


@router.delete("/{handoff_id}")
async def cancel(handoff_id: str) -> dict:
    state = _load()
    if handoff_id not in state["items"]:
        raise HTTPException(404, {"code": "handoff_not_found"})
    del state["items"][handoff_id]
    _save(state)
    return {"cancelled": True, "id": handoff_id}


@router.get("/all", response_model=list[HandoffItem])
async def list_all(owner_username: str | None = None) -> list[HandoffItem]:
    """Debug: lista tutti gli handoff (anche claimed). Filtrabile per owner."""
    state = _gc(_load())
    _save(state)
    items = [HandoffItem(**v) for v in state["items"].values()]
    if owner_username:
        items = [i for i in items if i.owner_username == owner_username]
    return sorted(items, key=lambda h: h.created_at, reverse=True)
