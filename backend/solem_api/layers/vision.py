"""VISION — capability immagine→testo, delega a GAVIO.

Single responsibility: SOLO ricevere immagine, passarla a GAVIO con
prompt strutturato e ritornare la risposta. Niente Llava direct, niente
selezione modello: GAVIO decide.

Endpoint:
  POST /vision/describe  — upload → describe
  POST /vision/ocr       — upload → text only
  POST /vision/objects   — upload → list objects
"""
from __future__ import annotations

import base64
import os
import time
from typing import Literal

import httpx
from fastapi import APIRouter, File, HTTPException, UploadFile
from pydantic import BaseModel

router = APIRouter(prefix="/vision", tags=["vision"])

SOLEM_URL = os.environ.get("SOLEM_INTERNAL_URL", "http://127.0.0.1:8001")
GAVIO_API = os.environ.get("GAVIO_API_URL", "http://127.0.0.1:8000")
MAX_IMAGE_BYTES = int(os.environ.get("SOLEM_VISION_MAX_BYTES", str(10 * 1024 * 1024)))


class DescribeResponse(BaseModel):
    description: str
    duration_ms: float
    via: str = "gavio"


class OCRResponse(BaseModel):
    text: str
    duration_ms: float
    via: str = "gavio"


class ObjectsResponse(BaseModel):
    objects: list[str]
    raw: str
    via: str = "gavio"


async def _read_image(file: UploadFile) -> str:
    content = await file.read()
    if len(content) > MAX_IMAGE_BYTES:
        raise HTTPException(413, {"code": "image_too_large", "max_bytes": MAX_IMAGE_BYTES})
    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(400, {"code": "not_an_image"})
    return base64.b64encode(content).decode()


async def _ask_gavio_vision(prompt: str, image_b64: str) -> tuple[str, float]:
    """Invia immagine + prompt a GAVIO; usa endpoint vision se disponibile,
    altrimenti fallback /api/chat con image inline."""
    t0 = time.perf_counter()
    payload = {
        "messages": [{"role": "user", "content": prompt}],
        "images": [image_b64],
        "task_hint": "vision",
    }
    async with httpx.AsyncClient(timeout=180.0) as c:
        try:
            r = await c.post(f"{GAVIO_API}/api/vision", json=payload)
            if r.status_code == 404:
                r = await c.post(f"{GAVIO_API}/api/chat", json=payload)
        except httpx.HTTPError as e:
            raise HTTPException(503, {"code": "gavio_unreachable", "error": str(e)})
        if r.status_code >= 400:
            raise HTTPException(r.status_code, {"code": "gavio_error", "body": r.text[:500]})
        data = r.json()
    content = data.get("content") or data.get("response") or data.get("message", {}).get("content") or ""
    return content.strip(), (time.perf_counter() - t0) * 1000


@router.get("/health", response_model=dict)
async def vision_health() -> dict:
    return {
        "ai_backend": "gavio (/api/vision o /api/chat)",
        "gavio_url": GAVIO_API,
        "max_image_bytes": MAX_IMAGE_BYTES,
    }


@router.post("/describe", response_model=DescribeResponse)
async def describe(
    file: UploadFile = File(...),
    detail_level: Literal["brief", "detailed"] = "detailed",
) -> DescribeResponse:
    b64 = await _read_image(file)
    prompt = (
        "Descrivi questa immagine in dettaglio: oggetti, persone, colori, ambientazione, "
        "eventuale testo. Rispondi in italiano."
        if detail_level == "detailed"
        else "Descrivi questa immagine in una frase. Italiano."
    )
    text, ms = await _ask_gavio_vision(prompt, b64)
    return DescribeResponse(description=text, duration_ms=round(ms, 2))


@router.post("/ocr", response_model=OCRResponse)
async def ocr(file: UploadFile = File(...)) -> OCRResponse:
    b64 = await _read_image(file)
    prompt = "Estrai TUTTO il testo visibile in questa immagine. Output solo il testo, mantieni le righe. Niente commenti."
    text, ms = await _ask_gavio_vision(prompt, b64)
    return OCRResponse(text=text, duration_ms=round(ms, 2))


@router.post("/objects", response_model=ObjectsResponse)
async def detect_objects(file: UploadFile = File(...)) -> ObjectsResponse:
    b64 = await _read_image(file)
    prompt = (
        "Elenca TUTTI gli oggetti distinti nell'immagine come lista separata da virgole. "
        "Output solo la lista. Esempio: 'gatto, tavolo, lampada, libro'"
    )
    raw, _ = await _ask_gavio_vision(prompt, b64)
    objs = [o.strip() for o in raw.split(",") if o.strip()]
    return ObjectsResponse(objects=objs[:50], raw=raw)
