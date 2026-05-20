"""TRANSLATE — traduzione offline + AI fallback.

Single responsibility: SOLO trasformare testo da lingua A → B. Niente
parsing context, niente storage cronologia.

Backend:
  1. argos-translate (offline, modelli locali ~100MB/coppia)
  2. AI fallback (Ollama) se coppia non disponibile

Endpoint:
  POST /translate            — text + src + tgt → translated
  GET  /translate/pairs      — coppie di lingue disponibili offline
  POST /translate/install/{src}-{tgt} — scarica modello argos
"""
from __future__ import annotations

import os
import shutil
import subprocess

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/translate", tags=["translate"])

SOLEM_URL = os.environ.get("SOLEM_INTERNAL_URL", "http://127.0.0.1:8001")


class TranslateRequest(BaseModel):
    text: str = Field(..., min_length=1)
    source: str = Field("auto", description="lingua sorgente ISO (auto, it, en, ...)")
    target: str = Field("it", description="lingua destinazione ISO")
    force_ai: bool = False


class TranslateResponse(BaseModel):
    text: str
    source: str
    target: str
    backend: str  # argos|ai|cached


class LanguagePair(BaseModel):
    source: str
    target: str
    installed: bool


def _argos_available() -> bool:
    return shutil.which("argos-translate-cli") is not None or shutil.which("argospm") is not None


def _argos_translate(text: str, src: str, tgt: str) -> str | None:
    """Chiama argos-translate-cli se disponibile."""
    cli = shutil.which("argos-translate-cli")
    if not cli:
        return None
    try:
        r = subprocess.run(
            [cli, "--from-lang", src, "--to-lang", tgt],
            input=text, capture_output=True, text=True, timeout=30, check=False,
        )
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip()
    except (subprocess.SubprocessError, OSError):
        return None
    return None


async def _ai_translate(text: str, src: str, tgt: str) -> str:
    lang_names = {
        "it": "Italian", "en": "English", "es": "Spanish", "fr": "French",
        "de": "German", "pt": "Portuguese", "ja": "Japanese", "zh": "Chinese",
        "ru": "Russian", "ar": "Arabic",
    }
    src_name = lang_names.get(src, src)
    tgt_name = lang_names.get(tgt, tgt)
    prompt = (
        f"Translate the following text from {src_name} to {tgt_name}. "
        f"Reply ONLY with the translation, no preamble.\n\n"
        f"TEXT: {text}"
    )
    async with httpx.AsyncClient(timeout=60.0) as c:
        r = await c.post(
            f"{SOLEM_URL}/solem/ai/route",
            json={
                "messages": [{"role": "user", "content": prompt}],
                "hint": "auto",
                "max_tokens": 1200,
                "temperature": 0.1,
            },
        )
        if r.status_code != 200:
            raise HTTPException(503, {"code": "ai_router_unavailable"})
        return r.json().get("content", "").strip()


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/health", response_model=dict)
async def trans_health() -> dict:
    return {
        "argos_available": _argos_available(),
        "ai_fallback": True,
    }


@router.post("", response_model=TranslateResponse)
async def translate(req: TranslateRequest) -> TranslateResponse:
    # Auto-detect: stub, assumiamo en se non specificato
    src = "en" if req.source == "auto" else req.source

    if not req.force_ai and _argos_available():
        result = _argos_translate(req.text, src, req.target)
        if result:
            return TranslateResponse(text=result, source=src, target=req.target, backend="argos")

    # Fallback AI
    translated = await _ai_translate(req.text, src, req.target)
    return TranslateResponse(text=translated, source=src, target=req.target, backend="ai")


@router.get("/pairs", response_model=list[LanguagePair])
async def list_pairs() -> list[LanguagePair]:
    argospm = shutil.which("argospm")
    if not argospm:
        return []
    try:
        r = subprocess.run([argospm, "list"], capture_output=True, text=True, timeout=5, check=False)
    except subprocess.SubprocessError:
        return []

    pairs: list[LanguagePair] = []
    for line in r.stdout.splitlines():
        if "->" in line or "→" in line:
            parts = line.replace("→", "->").split("->")
            if len(parts) == 2:
                pairs.append(LanguagePair(
                    source=parts[0].strip(),
                    target=parts[1].strip(),
                    installed=True,
                ))
    return pairs
