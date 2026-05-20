"""GAVIO PROXY — thin proxy verso GAVIO API.

Single responsibility: SOLO forward request all'unica AI di SOLEM, che è
GAVIO. Niente smart routing tra modelli, niente prompt engineering.

GAVIO decide internamente quale LLM usare (Ollama locale, Groq, Antropic
se l'utente lo ha configurato in GAVIO). SOLEM **non sceglie modelli**.

Endpoint:
  GET  /ai/status   — verifica connettività GAVIO
  POST /ai/route    — proxy a GAVIO chat endpoint (compat shape)
"""
from __future__ import annotations

import os
import time
from typing import Literal

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/ai", tags=["gavio-proxy"])

GAVIO_API = os.environ.get("GAVIO_API_URL", "http://127.0.0.1:8000")
GAVIO_CHAT_ENDPOINT = os.environ.get("GAVIO_CHAT_ENDPOINT", "/api/chat")


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


@router.get("/status", response_model=dict)
async def ai_status() -> dict:
    try:
        async with httpx.AsyncClient(timeout=2.0) as c:
            r = await c.get(f"{GAVIO_API}/health")
            return {
                "gavio_url": GAVIO_API,
                "gavio_up": r.status_code == 200,
                "note": "SOLEM unica AI = GAVIO. Niente router custom.",
            }
    except httpx.HTTPError as e:
        return {"gavio_url": GAVIO_API, "gavio_up": False, "error": str(e)}


@router.post("/route", response_model=RouteResponse)
async def route(req: RouteRequest) -> RouteResponse:
    """Forward a GAVIO. SOLEM non sceglie il modello, GAVIO sì."""
    t0 = time.perf_counter()
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
                raise HTTPException(503, {"code": "gavio_unavailable", "status": r.status_code})
            if r.status_code >= 400:
                raise HTTPException(r.status_code, {"code": "gavio_error", "body": r.text[:500]})
            data = r.json()
    except httpx.HTTPError as e:
        raise HTTPException(503, {"code": "gavio_unreachable", "error": str(e)})

    content = data.get("content") or data.get("response") or data.get("message", {}).get("content") or ""
    return RouteResponse(
        content=content,
        latency_ms=round((time.perf_counter() - t0) * 1000, 2),
        gavio_model=data.get("model"),
    )
