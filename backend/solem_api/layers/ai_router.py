"""GAVIO PROXY — thin proxy verso GAVIO API + graceful degradation.

Single responsibility: SOLO forward request a GAVIO. Niente smart routing
tra modelli, niente prompt engineering.

Graceful degradation: se GAVIO è down, prova nell'ordine:
  1. Cache recente (stessa query negli ultimi 5 min → ritorna risposta passata)
  2. Pattern matching deterministico per comandi noti
     ("blocca social N min", "fai backup", "stato sistema", "spegni")
  3. 503 con messaggio chiaro + suggerimenti

Endpoint:
  GET  /ai/status   — verifica connettività GAVIO
  POST /ai/route    — proxy a GAVIO chat endpoint (con fallback)
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import time
from pathlib import Path
from typing import Literal

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/ai", tags=["gavio-proxy"])

GAVIO_API = os.environ.get("GAVIO_API_URL", "http://127.0.0.1:8000")
GAVIO_CHAT_ENDPOINT = os.environ.get("GAVIO_CHAT_ENDPOINT", "/api/chat")
CACHE_FILE = Path("/var/lib/solem/ai-cache.json")
CACHE_TTL_SEC = 300  # 5 min


class ChatMessage(BaseModel):
    role: Literal["system", "user", "assistant"]
    content: str


class RouteRequest(BaseModel):
    messages: list[ChatMessage] = Field(..., min_length=1)
    hint: str = Field("auto", description="passato a GAVIO come 'task_hint'")
    max_tokens: int = Field(1024, ge=1, le=8192)
    temperature: float = Field(0.7, ge=0.0, le=2.0)


class RouteResponse(BaseModel):
    content: str
    backend: str = "gavio"
    latency_ms: float
    gavio_model: str | None = None
    degraded: bool = False
    degraded_source: str | None = None  # cache|pattern|none


# ─── Cache + pattern fallback ─────────────────────────────────────────


def _cache_key(messages: list[ChatMessage]) -> str:
    blob = json.dumps([m.model_dump() for m in messages], sort_keys=True)
    return hashlib.sha256(blob.encode()).hexdigest()[:16]


def _cache_load() -> dict:
    if not CACHE_FILE.exists():
        return {}
    try:
        return json.loads(CACHE_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        return {}


def _cache_save(cache: dict) -> None:
    CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
    now = time.time()
    cache = {k: v for k, v in cache.items() if v.get("ts", 0) + CACHE_TTL_SEC > now}
    CACHE_FILE.write_text(json.dumps(cache, indent=2))


def _cache_get(key: str) -> str | None:
    cache = _cache_load()
    entry = cache.get(key)
    if not entry:
        return None
    if entry.get("ts", 0) + CACHE_TTL_SEC < time.time():
        return None
    return entry.get("content")


def _cache_put(key: str, content: str) -> None:
    cache = _cache_load()
    cache[key] = {"ts": time.time(), "content": content}
    _cache_save(cache)


# Pattern deterministici: comandi che capiamo senza LLM
_PATTERNS = [
    (re.compile(r"\b(stato|status|come\s+stai|sistema)\b", re.I),
     "Sistema OK. GAVIO è offline; SOLEM sta usando il modo locale. "
     "Comandi disponibili in offline: focus, backup, lock, status, cluster."),
    (re.compile(r"\bblocca\s+social\b.*?(\d+)?", re.I),
     "Per attivare focus mode: POST /solem/focus/start "
     "{\"duration_minutes\":25,\"presets\":[\"social\"]}"),
    (re.compile(r"\bfai\s+backup\b|\bbackup\s+ora\b", re.I),
     "Trigger backup: `sudo systemctl start solem-backup-restic.service`"),
    (re.compile(r"\bspegni\b|\bshutdown\b", re.I),
     "Conferma shutdown: `sudo systemctl poweroff`"),
    (re.compile(r"\bcluster\b.*\b(stato|status|topology)\b", re.I),
     "Topologia cluster: GET /solem/cluster/topology"),
    (re.compile(r"\block\b|\bblocca\s+schermo\b", re.I),
     "Lock schermo: `loginctl lock-session` oppure SUPER+L"),
]


def _pattern_match(text: str) -> str | None:
    for rx, reply in _PATTERNS:
        if rx.search(text):
            return reply
    return None


@router.get("/status", response_model=dict)
async def ai_status() -> dict:
    """Verifica se GAVIO è raggiungibile. Mai solleva, sempre ritorna JSON.

    Tollera qualsiasi errore (HTTPError, AttributeError, OSError) per
    graceful degradation: SOLEM resta usabile anche se l'AI è offline.
    """
    try:
        async with httpx.AsyncClient(timeout=2.0) as c:
            r = await c.get(f"{GAVIO_API}/health")
            return {
                "gavio_url": GAVIO_API,
                "gavio_up": r.status_code == 200,
                "note": "SOLEM (OS) → AI esterna pre-integrata (GAVIO).",
            }
    except (httpx.HTTPError, AttributeError, OSError) as e:
        return {"gavio_url": GAVIO_API, "gavio_up": False, "error": str(e)}


@router.post("/route", response_model=RouteResponse)
async def route(req: RouteRequest) -> RouteResponse:
    """Forward a GAVIO. Se GAVIO è down: cache → pattern → 503."""
    t0 = time.perf_counter()
    cache_key = _cache_key(req.messages)

    payload = {
        "messages": [m.model_dump() for m in req.messages],
        "task_hint": req.hint,
        "max_tokens": req.max_tokens,
        "temperature": req.temperature,
    }
    try:
        async with httpx.AsyncClient(timeout=120.0) as c:
            r = await c.post(f"{GAVIO_API}{GAVIO_CHAT_ENDPOINT}", json=payload)
            if r.status_code >= 500:
                raise httpx.HTTPError(f"gavio 5xx: {r.status_code}")
            if r.status_code >= 400:
                raise HTTPException(r.status_code, {"code": "gavio_error", "body": r.text[:500]})
            data = r.json()
        content = data.get("content") or data.get("response") or data.get("message", {}).get("content") or ""
        _cache_put(cache_key, content)
        return RouteResponse(
            content=content,
            latency_ms=round((time.perf_counter() - t0) * 1000, 2),
            gavio_model=data.get("model"),
        )
    except (httpx.HTTPError, HTTPException):
        # Fallback 1: cache recente
        cached = _cache_get(cache_key)
        if cached:
            return RouteResponse(
                content=cached,
                latency_ms=round((time.perf_counter() - t0) * 1000, 2),
                degraded=True,
                degraded_source="cache",
            )
        # Fallback 2: pattern matching deterministico
        user_text = " ".join(m.content for m in req.messages if m.role == "user")
        pattern = _pattern_match(user_text)
        if pattern:
            return RouteResponse(
                content=pattern,
                latency_ms=round((time.perf_counter() - t0) * 1000, 2),
                degraded=True,
                degraded_source="pattern",
            )
        # Fallback 3: errore esplicito ma con suggerimenti
        raise HTTPException(503, {
            "code": "gavio_offline_no_fallback",
            "message": "GAVIO offline e nessun match in cache/pattern.",
            "hint": "Prova comandi semplici: 'stato sistema', 'blocca social 25 min', 'fai backup'.",
        })
