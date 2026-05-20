"""SUMMARIZER — riassunto documenti offline via Ollama.

Single responsibility: SOLO trasformare testo lungo in riassunto. Niente
parsing PDF/Word (delega a moduli esterni, qui solo testo già estratto).

Strategia: chunking + map-reduce per testi grandi (> 8k tokens):
  1. split in chunks da ~3000 token con overlap 200
  2. summary parziale per chunk (map step)
  3. summary finale combinando parziali (reduce step)

Endpoint:
  POST /summarize/text          — riassunto testo puro
  POST /summarize/file          — riassunto file caricato (txt/md)
  POST /summarize/url           — fetch URL + riassunto (no JS rendering)
"""
from __future__ import annotations

import os
import re

import httpx
from fastapi import APIRouter, File, HTTPException, UploadFile
from pydantic import BaseModel, Field

router = APIRouter(prefix="/summarize", tags=["summarizer"])

OLLAMA_URL = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434")
DEFAULT_MODEL = os.environ.get("SOLEM_SUMMARY_MODEL", "llama3.1:8b")
MAX_INPUT_CHARS = 200_000
CHUNK_CHARS = 12_000
CHUNK_OVERLAP = 800


class SummarizeRequest(BaseModel):
    text: str = Field(..., min_length=10)
    style: str = Field("paragraph", description="paragraph|bullets|tweet|tldr")
    language: str = Field("it", description="it|en|...")
    model: str | None = None


class URLRequest(BaseModel):
    url: str
    style: str = "paragraph"
    language: str = "it"


class SummaryResponse(BaseModel):
    summary: str
    model: str
    input_chars: int
    chunks_processed: int


# ─── Helpers ──────────────────────────────────────────────────────────


def _chunk_text(text: str) -> list[str]:
    if len(text) <= CHUNK_CHARS:
        return [text]
    chunks: list[str] = []
    i = 0
    while i < len(text):
        chunks.append(text[i:i + CHUNK_CHARS])
        i += CHUNK_CHARS - CHUNK_OVERLAP
    return chunks


def _style_prompt(style: str, lang: str) -> str:
    lang_clause = "Reply in Italian." if lang == "it" else f"Reply in {lang}."
    styles = {
        "paragraph": f"Summarize the following text in a clear paragraph. {lang_clause}",
        "bullets":   f"Summarize the following as bullet points (max 7). {lang_clause}",
        "tweet":     f"Summarize the following in 1 sentence under 280 chars. {lang_clause}",
        "tldr":      f"Write a TL;DR (max 3 sentences) of the following. {lang_clause}",
    }
    return styles.get(style, styles["paragraph"])


async def _call_ollama(prompt: str, model: str) -> str:
    async with httpx.AsyncClient(timeout=120.0) as c:
        r = await c.post(
            f"{OLLAMA_URL}/api/generate",
            json={
                "model": model,
                "prompt": prompt,
                "stream": False,
                "options": {"temperature": 0.3, "num_predict": 800},
            },
        )
        if r.status_code == 404:
            raise HTTPException(404, {"code": "model_not_pulled", "hint": f"ollama pull {model}"})
        r.raise_for_status()
        return r.json().get("response", "").strip()


async def _summarize_chunks(chunks: list[str], style: str, lang: str, model: str) -> str:
    style_prompt = _style_prompt(style, lang)
    if len(chunks) == 1:
        return await _call_ollama(f"{style_prompt}\n\nTEXT:\n{chunks[0]}", model)

    # Map step: summary parziale per chunk
    partials: list[str] = []
    for chunk in chunks:
        p = await _call_ollama(
            f"Briefly summarize the following passage:\n\n{chunk}",
            model,
        )
        partials.append(p)

    # Reduce step: combina
    combined = "\n\n---\n\n".join(partials)
    return await _call_ollama(
        f"{style_prompt}\n\nThese are partial summaries of a longer document. "
        f"Combine them into a coherent final summary:\n\n{combined}",
        model,
    )


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/health", response_model=dict)
async def summary_health() -> dict:
    return {
        "ollama_url": OLLAMA_URL,
        "default_model": DEFAULT_MODEL,
        "max_input_chars": MAX_INPUT_CHARS,
        "chunk_chars": CHUNK_CHARS,
    }


@router.post("/text", response_model=SummaryResponse)
async def summarize_text(req: SummarizeRequest) -> SummaryResponse:
    text = req.text[:MAX_INPUT_CHARS]
    chunks = _chunk_text(text)
    use_model = req.model or DEFAULT_MODEL
    summary = await _summarize_chunks(chunks, req.style, req.language, use_model)
    return SummaryResponse(
        summary=summary,
        model=use_model,
        input_chars=len(text),
        chunks_processed=len(chunks),
    )


@router.post("/file", response_model=SummaryResponse)
async def summarize_file(
    file: UploadFile = File(...),
    style: str = "paragraph",
    language: str = "it",
    model: str | None = None,
) -> SummaryResponse:
    if file.size and file.size > MAX_INPUT_CHARS * 4:  # safety
        raise HTTPException(413, {"code": "file_too_large"})
    content = await file.read()
    try:
        text = content.decode("utf-8", errors="replace")
    except UnicodeDecodeError:
        raise HTTPException(400, {"code": "not_utf8_text"})

    chunks = _chunk_text(text[:MAX_INPUT_CHARS])
    use_model = model or DEFAULT_MODEL
    summary = await _summarize_chunks(chunks, style, language, use_model)
    return SummaryResponse(
        summary=summary,
        model=use_model,
        input_chars=len(text),
        chunks_processed=len(chunks),
    )


@router.post("/url", response_model=SummaryResponse)
async def summarize_url(req: URLRequest) -> SummaryResponse:
    """Fetch URL HTML, strip tags, riassumi. No JS rendering."""
    try:
        async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as c:
            r = await c.get(req.url, headers={"User-Agent": "Mozilla/5.0 SOLEM Summarizer"})
            r.raise_for_status()
            html = r.text
    except httpx.HTTPError as e:
        raise HTTPException(502, {"code": "fetch_failed", "error": str(e)})

    # Strip basic HTML
    text = re.sub(r"<script[^>]*>.*?</script>", " ", html, flags=re.DOTALL | re.IGNORECASE)
    text = re.sub(r"<style[^>]*>.*?</style>", " ", text, flags=re.DOTALL | re.IGNORECASE)
    text = re.sub(r"<[^>]+>", " ", text)
    text = re.sub(r"\s+", " ", text).strip()

    text = text[:MAX_INPUT_CHARS]
    chunks = _chunk_text(text)
    summary = await _summarize_chunks(chunks, req.style, req.language, DEFAULT_MODEL)
    return SummaryResponse(
        summary=summary,
        model=DEFAULT_MODEL,
        input_chars=len(text),
        chunks_processed=len(chunks),
    )
