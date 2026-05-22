"""CONTEXT ACTIONS — apri un file → GAVIO propone azioni intelligenti.

Single responsibility: SOLO mappare path/MIME a una lista di azioni
candidate. Niente esecuzione (l'utente sceglie + conferma).

Esempio: l'utente apre `report.pdf` → SOLEM chiede:
  [a] Riassumi
  [b] Estrai testo (OCR)
  [c] Traduci in inglese
  [d] Estrai tabelle
  [e] Firma digitalmente

Sorgenti azioni:
  1. Static rules (deterministic per MIME) — la maggioranza
  2. AI-suggested via GAVIO (per file ambigui o estensioni rare)

Endpoint:
  POST /actions/suggest   — path → list[Action]
  POST /actions/execute   — esegue un'azione (delegando al layer giusto)
"""
from __future__ import annotations

import mimetypes
import os
from pathlib import Path

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/actions", tags=["context-actions"])

SOLEM_URL = os.environ.get("SOLEM_INTERNAL_URL", "http://127.0.0.1:8001")


class SuggestRequest(BaseModel):
    path: str
    use_ai_for_ambiguous: bool = True


class Action(BaseModel):
    id: str = Field(..., description="es. 'summarize', 'ocr', 'translate-en'")
    name: str
    description: str
    endpoint: str = Field(..., description="POST endpoint per eseguire")
    payload_template: dict = Field(default_factory=dict)
    source: str = Field("static", description="static | ai-suggested")


class ExecuteRequest(BaseModel):
    action_id: str
    path: str
    overrides: dict = Field(default_factory=dict)


# ─── Static rules per MIME ────────────────────────────────────────────


def _actions_for_pdf(path: str) -> list[Action]:
    return [
        Action(id="summarize", name="Riassumi",
               description="GAVIO legge e ti dà un riassunto in italiano",
               endpoint="/solem/summarize/file",
               payload_template={"style": "paragraph", "language": "it"}),
        Action(id="extract-text", name="Estrai testo",
               description="Tutto il testo del PDF in un blocco",
               endpoint="/solem/docparse/extract",
               payload_template={}),
        Action(id="translate-en", name="Traduci in inglese",
               description="Estrai testo + traduci en",
               endpoint="/solem/translate",
               payload_template={"target": "en"}),
        Action(id="rag-ingest", name="Aggiungi a knowledge base",
               description="Indicizza nei vector store per ricerca futura",
               endpoint="/solem/rag/ingest/file",
               payload_template={"collection": "default"}),
    ]


def _actions_for_image(path: str, mime: str) -> list[Action]:
    return [
        Action(id="describe", name="Descrivi cosa vedo",
               description="GAVIO ti spiega cosa c'è nell'immagine",
               endpoint="/solem/vision/describe",
               payload_template={"detail_level": "detailed"}),
        Action(id="ocr", name="Estrai testo (OCR)",
               description="Legge testo dall'immagine",
               endpoint="/solem/vision/ocr",
               payload_template={}),
        Action(id="detect-objects", name="Elenca oggetti",
               description="Tutti gli oggetti distinti",
               endpoint="/solem/vision/objects",
               payload_template={}),
        Action(id="auto-tag", name="Auto-tag per Immich",
               description="Genera tag descrittivi da indicizzare",
               endpoint="/solem/vision/describe",
               payload_template={"detail_level": "brief"}),
    ]


def _actions_for_audio(path: str) -> list[Action]:
    return [
        Action(id="transcribe", name="Trascrivi",
               description="Audio → testo via whisper locale",
               endpoint="/solem/voice/transcribe",
               payload_template={}),
        Action(id="meeting-notes", name="Riassunto meeting + action items",
               description="Whisper + GAVIO estrae todo",
               endpoint="/solem/meeting/process",
               payload_template={"save_audio": False}),
    ]


def _actions_for_text(path: str) -> list[Action]:
    return [
        Action(id="summarize", name="Riassumi",
               description="GAVIO sintetizza in paragrafo",
               endpoint="/solem/summarize/file",
               payload_template={"style": "paragraph", "language": "it"}),
        Action(id="bullets", name="In bullet points",
               description="Sintesi a punti",
               endpoint="/solem/summarize/file",
               payload_template={"style": "bullets", "language": "it"}),
        Action(id="translate", name="Traduci",
               description="Traduci in un'altra lingua",
               endpoint="/solem/translate",
               payload_template={"target": "en"}),
        Action(id="rag-ingest", name="Aggiungi a knowledge base",
               description="Indicizza per ricerca semantica futura",
               endpoint="/solem/rag/ingest/file",
               payload_template={"collection": "default"}),
    ]


def _actions_for_archive(path: str) -> list[Action]:
    return [
        Action(id="extract", name="Estrai contenuto",
               description="Decomprimi l'archive in ~/Downloads",
               endpoint="/solem/system/extract-archive",
               payload_template={"dest": "~/Downloads"}),
        Action(id="inspect", name="Vedi cosa c'è dentro",
               description="Lista file senza estrarre",
               endpoint="/solem/system/list-archive",
               payload_template={}),
    ]


def _actions_for_video(path: str) -> list[Action]:
    return [
        Action(id="extract-frames", name="Estrai frame chiave",
               description="ffmpeg keyframes per analisi visiva",
               endpoint="/solem/vision/extract-frames",
               payload_template={"interval_sec": 10}),
        Action(id="transcribe-audio", name="Trascrivi audio video",
               description="Traccia audio → testo whisper",
               endpoint="/solem/voice/transcribe-video",
               payload_template={}),
        Action(id="summarize", name="Riassunto cosa succede",
               description="Frame + audio → riassunto GAVIO",
               endpoint="/solem/meeting/process",
               payload_template={"save_audio": False}),
    ]


# ─── Dispatch by MIME ─────────────────────────────────────────────────


def _detect_actions(path: str) -> tuple[list[Action], str]:
    p = Path(path).expanduser().resolve()
    if not p.exists():
        raise HTTPException(404, {"code": "path_not_found", "path": str(p)})

    mime, _ = mimetypes.guess_type(str(p))
    mime = mime or "application/octet-stream"

    if mime == "application/pdf":
        return _actions_for_pdf(str(p)), mime
    if mime.startswith("image/"):
        return _actions_for_image(str(p), mime), mime
    if mime.startswith("audio/"):
        return _actions_for_audio(str(p)), mime
    if mime.startswith("video/"):
        return _actions_for_video(str(p)), mime
    if mime.startswith("text/") or mime in {"application/json", "application/yaml", "application/xml"}:
        return _actions_for_text(str(p)), mime
    if mime in {"application/zip", "application/x-tar", "application/gzip",
                "application/x-7z-compressed", "application/x-rar"}:
        return _actions_for_archive(str(p)), mime

    return [], mime


async def _ai_suggested_actions(path: str, mime: str) -> list[Action]:
    """Per MIME ambigui chiede a GAVIO 2-3 azioni tipiche."""
    prompt = (
        f"File: {Path(path).name}\nMIME: {mime}\n\n"
        f"Suggerisci 3 azioni che un utente vorrebbe fare con questo file. "
        f"Output JSON array di oggetti {{id, name, description, endpoint}}. "
        f"endpoint deve essere un path /solem/... esistente o /solem/generic/handle. "
        f"Reply ONLY the JSON array."
    )
    try:
        async with httpx.AsyncClient(timeout=20.0) as c:
            r = await c.post(
                f"{SOLEM_URL}/solem/ai/route",
                json={"messages": [{"role": "user", "content": prompt}],
                      "hint": "auto", "max_tokens": 400},
            )
            if r.status_code != 200:
                return []
            content = r.json().get("content", "").strip()
    except httpx.HTTPError:
        return []

    import json as _j
    import re as _re
    m = _re.search(r"\[.*\]", content, _re.DOTALL)
    if not m:
        return []
    try:
        parsed = _j.loads(m.group(0))
        out: list[Action] = []
        for item in parsed[:5]:
            if isinstance(item, dict) and "id" in item and "name" in item:
                out.append(Action(
                    id=item["id"],
                    name=item["name"],
                    description=item.get("description", ""),
                    endpoint=item.get("endpoint", "/solem/generic/handle"),
                    source="ai-suggested",
                ))
        return out
    except (_j.JSONDecodeError, ValueError):
        return []


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/health", response_model=dict)
async def actions_health() -> dict:
    return {
        "static_mime_categories": ["pdf", "image/*", "audio/*", "video/*",
                                    "text/*", "archives"],
        "ai_fallback_enabled": True,
    }


@router.post("/suggest", response_model=list[Action])
async def suggest(req: SuggestRequest) -> list[Action]:
    actions, mime = _detect_actions(req.path)
    if actions:
        return actions
    if req.use_ai_for_ambiguous:
        ai_actions = await _ai_suggested_actions(req.path, mime)
        if ai_actions:
            return ai_actions
    return []


@router.post("/execute", response_model=dict)
async def execute(req: ExecuteRequest) -> dict:
    """Trova action per (path, action_id), prepara payload, redirige al layer giusto."""
    actions, _ = _detect_actions(req.path)
    action = next((a for a in actions if a.id == req.action_id), None)
    if not action:
        raise HTTPException(404, {
            "code": "action_not_found_for_path",
            "available": [a.id for a in actions],
        })

    return {
        "redirect_to": action.endpoint,
        "method": "POST",
        "suggested_payload": {**action.payload_template, **req.overrides},
        "note": (
            "context_actions.py NON esegue direttamente: l'utente (UI/CLI/GAVIO) "
            "deve fare la chiamata a `redirect_to` con il payload, allegando il file."
        ),
    }
