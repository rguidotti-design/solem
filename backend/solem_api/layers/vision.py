"""VISION — multimodal AI locale: image → text via Llava/Ollama.

Single responsibility: SOLO routing immagine→modello visione. Niente
camera capture (sta in pc_actions o webcam.py), niente storage permanente
delle immagini (privacy).

Modelli supportati (via Ollama):
  - llava:7b         (default, ~4 GB)
  - llava:13b        (qualità maggiore, ~8 GB)
  - bakllava:7b      (alternativo)
  - moondream:1.8b   (leggero ~1 GB)

Endpoint:
  POST /vision/describe  — descrivi immagine (upload o url)
  POST /vision/ocr       — estrai testo (richiede tesseract o llava prompt)
  POST /vision/objects   — list objects (llava structured prompt)
  GET  /vision/models    — modelli vision installati in ollama
"""
from __future__ import annotations

import base64
import os
from typing import Literal

import httpx
from fastapi import APIRouter, File, HTTPException, UploadFile
from pydantic import BaseModel, Field

router = APIRouter(prefix="/vision", tags=["vision"])

OLLAMA_URL = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434")
DEFAULT_MODEL = os.environ.get("SOLEM_VISION_MODEL", "llava:7b")
MAX_IMAGE_BYTES = int(os.environ.get("SOLEM_VISION_MAX_BYTES", str(10 * 1024 * 1024)))


class DescribeResponse(BaseModel):
    model: str
    description: str
    duration_ms: float


class OCRResponse(BaseModel):
    model: str
    text: str
    duration_ms: float


class ObjectsResponse(BaseModel):
    model: str
    objects: list[str]
    raw: str


class VisionModel(BaseModel):
    name: str
    size_gb: float
    family: str = "llava"


# ─── Helpers ──────────────────────────────────────────────────────────


async def _call_ollama_vision(prompt: str, image_b64: str, model: str) -> tuple[str, float]:
    import time
    t0 = time.perf_counter()
    async with httpx.AsyncClient(timeout=120.0) as c:
        r = await c.post(
            f"{OLLAMA_URL}/api/generate",
            json={
                "model": model,
                "prompt": prompt,
                "images": [image_b64],
                "stream": False,
                "options": {"temperature": 0.2},
            },
        )
        if r.status_code == 404:
            raise HTTPException(404, {
                "code": "model_not_pulled",
                "hint": f"ollama pull {model}",
            })
        r.raise_for_status()
        data = r.json()
        return data.get("response", ""), (time.perf_counter() - t0) * 1000


async def _read_image(file: UploadFile) -> bytes:
    content = await file.read()
    if len(content) > MAX_IMAGE_BYTES:
        raise HTTPException(413, {
            "code": "image_too_large",
            "max_bytes": MAX_IMAGE_BYTES,
            "got": len(content),
        })
    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(400, {"code": "not_an_image", "content_type": file.content_type})
    return content


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/health", response_model=dict)
async def vision_health() -> dict:
    try:
        async with httpx.AsyncClient(timeout=2.0) as c:
            r = await c.get(f"{OLLAMA_URL}/api/tags")
            ollama_up = r.status_code == 200
            models = r.json().get("models", []) if ollama_up else []
    except httpx.HTTPError:
        ollama_up = False
        models = []
    vision_models = [m["name"] for m in models if any(v in m.get("name", "") for v in ("llava", "bakllava", "moondream", "llama3.2-vision"))]
    return {
        "ollama_up": ollama_up,
        "default_model": DEFAULT_MODEL,
        "vision_models_installed": vision_models,
        "max_image_bytes": MAX_IMAGE_BYTES,
    }


@router.post("/describe", response_model=DescribeResponse)
async def describe(
    file: UploadFile = File(...),
    model: str | None = None,
    detail_level: Literal["brief", "detailed"] = "detailed",
) -> DescribeResponse:
    content = await _read_image(file)
    b64 = base64.b64encode(content).decode()

    use_model = model or DEFAULT_MODEL
    prompt = (
        "Describe this image in detail, including objects, people, colors, "
        "setting, and any text visible. Reply in Italian."
        if detail_level == "detailed"
        else "Describe this image in one sentence. Reply in Italian."
    )

    desc, ms = await _call_ollama_vision(prompt, b64, use_model)
    return DescribeResponse(model=use_model, description=desc, duration_ms=round(ms, 2))


@router.post("/ocr", response_model=OCRResponse)
async def ocr(file: UploadFile = File(...), model: str | None = None) -> OCRResponse:
    content = await _read_image(file)
    b64 = base64.b64encode(content).decode()
    use_model = model or DEFAULT_MODEL
    prompt = "Extract ALL text visible in this image. Output ONLY the text, preserving line breaks. No explanation."
    text, ms = await _call_ollama_vision(prompt, b64, use_model)
    return OCRResponse(model=use_model, text=text.strip(), duration_ms=round(ms, 2))


@router.post("/objects", response_model=ObjectsResponse)
async def detect_objects(file: UploadFile = File(...), model: str | None = None) -> ObjectsResponse:
    content = await _read_image(file)
    b64 = base64.b64encode(content).decode()
    use_model = model or DEFAULT_MODEL
    prompt = (
        "List ALL distinct objects in this image as a comma-separated list. "
        "Output only the list, no other text. Example: 'cat, table, lamp, book'"
    )
    raw, _ = await _call_ollama_vision(prompt, b64, use_model)
    objs = [o.strip() for o in raw.split(",") if o.strip()]
    return ObjectsResponse(model=use_model, objects=objs[:50], raw=raw)


@router.get("/models", response_model=list[VisionModel])
async def list_models() -> list[VisionModel]:
    try:
        async with httpx.AsyncClient(timeout=2.0) as c:
            r = await c.get(f"{OLLAMA_URL}/api/tags")
            r.raise_for_status()
            data = r.json()
    except httpx.HTTPError as e:
        raise HTTPException(503, {"code": "ollama_unavailable", "error": str(e)})

    vision_families = ("llava", "bakllava", "moondream", "llama3.2-vision")
    out: list[VisionModel] = []
    for m in data.get("models", []):
        name = m.get("name", "")
        if any(v in name for v in vision_families):
            family = next(v for v in vision_families if v in name)
            out.append(VisionModel(
                name=name,
                size_gb=round(m.get("size", 0) / (1024**3), 2),
                family=family,
            ))
    return out
