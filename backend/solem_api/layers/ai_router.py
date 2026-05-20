"""AI ROUTER — smart router LLM: locale (Ollama) vs cloud free (Groq).

Single responsibility: SOLO scegliere il backend ottimale per una request
e proxy-arla. Niente caching, niente conversazioni (sta in GAVIO).

Politica di routing (priorità):
  1. Preferenza utente esplicita (header X-AI-Backend: ollama|groq|auto)
  2. Privacy mode globale → SOLO ollama (no cloud per nessun motivo)
  3. Task type: code/long → modello grande (groq se disponibile)
  4. Task simple/short → ollama local (latency)
  5. Ollama down → fallback groq
  6. Groq quota exceeded → fallback ollama

ADR-018 → "local-first ma intelligente": Ollama default, escalation a Groq
solo quando vale la pena (modello più grande disponibile e privacy ok).

NB: zero cloud paid. Groq è free-tier; quando finisce, si degrada a
Ollama locale automaticamente.
"""
from __future__ import annotations

import os
import time
from typing import Literal

import httpx
from fastapi import APIRouter, HTTPException, Header
from pydantic import BaseModel, Field

router = APIRouter(prefix="/ai", tags=["ai-router"])

OLLAMA_URL = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434")
GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
GROQ_API_KEY = os.environ.get("GROQ_API_KEY", "")
PRIVACY_MODE = os.environ.get("SOLEM_PRIVACY_MODE", "0") == "1"

DEFAULT_LOCAL_MODEL = os.environ.get("SOLEM_LOCAL_MODEL", "llama3.1:8b")
DEFAULT_CLOUD_MODEL = os.environ.get("SOLEM_CLOUD_MODEL", "llama-3.3-70b-versatile")

# Soglia in tokens approssimati per task "complesso"
COMPLEX_TASK_TOKENS = 1500


class ChatMessage(BaseModel):
    role: Literal["system", "user", "assistant"]
    content: str


class RouteRequest(BaseModel):
    messages: list[ChatMessage] = Field(..., min_length=1)
    hint: Literal["code", "chat", "summarize", "creative", "auto"] = "auto"
    max_tokens: int = Field(1024, ge=1, le=8192)
    temperature: float = Field(0.7, ge=0.0, le=2.0)


class RouteResponse(BaseModel):
    backend: Literal["ollama", "groq"]
    model: str
    content: str
    latency_ms: float
    reason: str


# ─── State (in-memory health tracking) ─────────────────────────────────


_ollama_down_until = 0.0
_groq_down_until = 0.0
_DOWN_TTL = 60.0  # 1 minuto di cool-down per backend fallito


def _is_down(backend: Literal["ollama", "groq"]) -> bool:
    global _ollama_down_until, _groq_down_until
    now = time.monotonic()
    if backend == "ollama":
        return now < _ollama_down_until
    return now < _groq_down_until


def _mark_down(backend: Literal["ollama", "groq"]) -> None:
    global _ollama_down_until, _groq_down_until
    until = time.monotonic() + _DOWN_TTL
    if backend == "ollama":
        _ollama_down_until = until
    else:
        _groq_down_until = until


# ─── Routing policy ────────────────────────────────────────────────────


def _estimate_tokens(messages: list[ChatMessage]) -> int:
    """Stima rapida: 1 token ~= 4 char (no tokenizer reale)."""
    return sum(len(m.content) for m in messages) // 4


def _decide(req: RouteRequest, prefer: str | None) -> tuple[str, str]:
    """Ritorna (backend, reason)."""
    if prefer in {"ollama", "groq"}:
        return prefer, f"user-prefer:{prefer}"

    if PRIVACY_MODE:
        return "ollama", "privacy-mode-forced-local"

    if not GROQ_API_KEY:
        return "ollama", "no-groq-key-available"

    tokens = _estimate_tokens(req.messages)
    is_complex = tokens > COMPLEX_TASK_TOKENS or req.hint in {"code", "summarize"}

    if is_complex and not _is_down("groq"):
        return "groq", f"complex-task-tokens-{tokens}"

    if not _is_down("ollama"):
        return "ollama", "local-first-simple-task"

    if not _is_down("groq"):
        return "groq", "ollama-down-fallback"

    return "ollama", "both-down-retry-local"


# ─── Backend calls ─────────────────────────────────────────────────────


async def _call_ollama(req: RouteRequest) -> str:
    async with httpx.AsyncClient(timeout=60.0) as c:
        r = await c.post(
            f"{OLLAMA_URL}/api/chat",
            json={
                "model": DEFAULT_LOCAL_MODEL,
                "messages": [m.model_dump() for m in req.messages],
                "options": {"temperature": req.temperature, "num_predict": req.max_tokens},
                "stream": False,
            },
        )
        r.raise_for_status()
        return r.json().get("message", {}).get("content", "")


async def _call_groq(req: RouteRequest) -> str:
    async with httpx.AsyncClient(timeout=60.0) as c:
        r = await c.post(
            GROQ_URL,
            headers={"Authorization": f"Bearer {GROQ_API_KEY}"},
            json={
                "model": DEFAULT_CLOUD_MODEL,
                "messages": [m.model_dump() for m in req.messages],
                "temperature": req.temperature,
                "max_tokens": req.max_tokens,
            },
        )
        r.raise_for_status()
        data = r.json()
        return data["choices"][0]["message"]["content"]


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/status", response_model=dict)
async def ai_status() -> dict:
    return {
        "privacy_mode": PRIVACY_MODE,
        "groq_available": bool(GROQ_API_KEY),
        "ollama_url": OLLAMA_URL,
        "local_model": DEFAULT_LOCAL_MODEL,
        "cloud_model": DEFAULT_CLOUD_MODEL,
        "ollama_down": _is_down("ollama"),
        "groq_down": _is_down("groq"),
        "complex_task_threshold_tokens": COMPLEX_TASK_TOKENS,
    }


@router.post("/route", response_model=RouteResponse)
async def route(
    req: RouteRequest,
    x_ai_backend: str | None = Header(None, alias="X-AI-Backend"),
) -> RouteResponse:
    backend, reason = _decide(req, x_ai_backend)
    t0 = time.perf_counter()

    try:
        if backend == "ollama":
            content = await _call_ollama(req)
            model = DEFAULT_LOCAL_MODEL
        else:
            content = await _call_groq(req)
            model = DEFAULT_CLOUD_MODEL
    except httpx.HTTPError as e:
        _mark_down(backend)
        # Auto-fallback all'altro backend, se disponibile e non in privacy
        if backend == "groq" and not _is_down("ollama"):
            try:
                content = await _call_ollama(req)
                return RouteResponse(
                    backend="ollama", model=DEFAULT_LOCAL_MODEL, content=content,
                    latency_ms=round((time.perf_counter() - t0) * 1000, 2),
                    reason=f"fallback-after-groq-fail:{reason}",
                )
            except httpx.HTTPError:
                pass
        if backend == "ollama" and not PRIVACY_MODE and GROQ_API_KEY and not _is_down("groq"):
            try:
                content = await _call_groq(req)
                return RouteResponse(
                    backend="groq", model=DEFAULT_CLOUD_MODEL, content=content,
                    latency_ms=round((time.perf_counter() - t0) * 1000, 2),
                    reason=f"fallback-after-ollama-fail:{reason}",
                )
            except httpx.HTTPError:
                pass
        raise HTTPException(503, {"code": "all_backends_down", "last_error": str(e)})

    return RouteResponse(
        backend=backend,
        model=model,
        content=content,
        latency_ms=round((time.perf_counter() - t0) * 1000, 2),
        reason=reason,
    )
