"""MEETING NOTES — audio meeting → transcript → summary + action items.

Single responsibility: SOLO orchestrare pipeline: upload audio → whisper
→ AI summarize+extract_actions. Niente record audio (delegato a
solem-record o app esterna).

Privacy: audio NON inviato fuori dal sistema. Trascrizione locale via
whisper-cli, summary via AI router (locale by default).

Endpoint:
  POST /meeting/process   — upload audio file → meeting record completo
  GET  /meeting/list      — meeting registrati
  GET  /meeting/{id}      — dettaglio
  DELETE /meeting/{id}    — rimuove (audio + transcript + summary)
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path

import httpx
from fastapi import APIRouter, File, HTTPException, UploadFile
from pydantic import BaseModel, Field

router = APIRouter(prefix="/meeting", tags=["meeting-notes"])

MEETING_DIR = Path("/var/lib/solem/meetings")
SOLEM_URL = os.environ.get("SOLEM_INTERNAL_URL", "http://127.0.0.1:8001")
WHISPER_MODEL = os.environ.get("WHISPER_MODEL_PATH", "/var/lib/solem-models/whisper/ggml-base.bin")


class ActionItem(BaseModel):
    owner: str | None = None
    text: str
    due: str | None = None


class MeetingRecord(BaseModel):
    id: str
    created_at: str
    duration_sec: int
    transcript: str
    summary: str
    action_items: list[ActionItem]
    audio_filename: str | None = None
    audio_size_bytes: int = 0


class MeetingSummary(BaseModel):
    id: str
    created_at: str
    summary_preview: str
    action_items_count: int


def _whisper_transcribe(audio_path: Path, language: str = "it") -> str:
    cli = shutil.which("whisper-cli")
    if not cli:
        raise HTTPException(503, {"code": "whisper_unavailable"})
    if not Path(WHISPER_MODEL).exists():
        raise HTTPException(503, {
            "code": "whisper_model_missing",
            "path": WHISPER_MODEL,
            "hint": "systemctl start solem-models-fetch",
        })
    r = subprocess.run(
        [cli, "-m", WHISPER_MODEL, "-l", language, "-nt", "-f", str(audio_path)],
        capture_output=True, text=True, timeout=1200, check=False,
    )
    if r.returncode != 0:
        raise HTTPException(500, {"code": "whisper_failed", "stderr": r.stderr[:500]})
    # whisper-cli output: timestamps + text. Strip timestamps
    import re
    text = re.sub(r"^\[[^\]]+\]\s*", "", r.stdout, flags=re.MULTILINE)
    return text.strip()


async def _ai_summarize_and_actions(transcript: str) -> tuple[str, list[ActionItem]]:
    """Chiama AI router per riassumere + estrarre action items."""
    prompt = (
        f"Dato il seguente transcript di un meeting, restituisci JSON con due chiavi:\n"
        f"1. 'summary': riassunto in 4-6 frasi in italiano\n"
        f"2. 'action_items': array di oggetti {{owner, text, due}} (owner nullable, due nullable)\n\n"
        f"Output SOLO il JSON, niente markdown fences.\n\n"
        f"TRANSCRIPT:\n{transcript[:30000]}"
    )
    async with httpx.AsyncClient(timeout=180.0) as c:
        r = await c.post(
            f"{SOLEM_URL}/solem/ai/route",
            json={
                "messages": [{"role": "user", "content": prompt}],
                "hint": "summarize",
                "max_tokens": 1500,
                "temperature": 0.2,
            },
        )
        if r.status_code != 200:
            raise HTTPException(503, {"code": "ai_router_unavailable"})
        raw = r.json().get("content", "").strip()

    import re
    raw = re.sub(r"^```(?:json)?", "", raw).rstrip("`").strip()
    m = re.search(r"\{.*\}", raw, re.DOTALL)
    if not m:
        return raw or "Riassunto non generato", []

    try:
        data = json.loads(m.group(0))
        summary = data.get("summary", "")
        actions = [ActionItem(**a) for a in data.get("action_items", []) if isinstance(a, dict)]
        return summary, actions
    except (json.JSONDecodeError, ValueError):
        return raw, []


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/health", response_model=dict)
async def meeting_health() -> dict:
    return {
        "meeting_dir": str(MEETING_DIR),
        "whisper_available": shutil.which("whisper-cli") is not None,
        "model_path": WHISPER_MODEL,
        "model_exists": Path(WHISPER_MODEL).exists(),
        "total_meetings": len(list(MEETING_DIR.glob("*.json"))) if MEETING_DIR.exists() else 0,
    }


@router.post("/process", response_model=MeetingRecord)
async def process_meeting(
    file: UploadFile = File(...),
    language: str = "it",
    save_audio: bool = False,
) -> MeetingRecord:
    MEETING_DIR.mkdir(parents=True, exist_ok=True)
    meeting_id = uuid.uuid4().hex[:12]

    content = await file.read()
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        tmp.write(content)
        audio_path = Path(tmp.name)

    try:
        transcript = _whisper_transcribe(audio_path, language)
        summary, actions = await _ai_summarize_and_actions(transcript)

        record = MeetingRecord(
            id=meeting_id,
            created_at=datetime.now(timezone.utc).isoformat(),
            duration_sec=0,  # TODO: ffprobe per durata reale
            transcript=transcript,
            summary=summary,
            action_items=actions,
            audio_filename=file.filename if save_audio else None,
            audio_size_bytes=len(content) if save_audio else 0,
        )

        (MEETING_DIR / f"{meeting_id}.json").write_text(record.model_dump_json(indent=2))

        if save_audio:
            audio_dest = MEETING_DIR / f"{meeting_id}.wav"
            audio_path.rename(audio_dest)
        else:
            audio_path.unlink(missing_ok=True)

        return record
    finally:
        audio_path.unlink(missing_ok=True)


@router.get("/list", response_model=list[MeetingSummary])
async def list_meetings() -> list[MeetingSummary]:
    MEETING_DIR.mkdir(parents=True, exist_ok=True)
    out: list[MeetingSummary] = []
    for f in sorted(MEETING_DIR.glob("*.json"), reverse=True):
        try:
            data = json.loads(f.read_text())
            out.append(MeetingSummary(
                id=data["id"],
                created_at=data["created_at"],
                summary_preview=data["summary"][:200],
                action_items_count=len(data.get("action_items", [])),
            ))
        except (json.JSONDecodeError, KeyError):
            continue
    return out


@router.get("/{meeting_id}", response_model=MeetingRecord)
async def get_meeting(meeting_id: str) -> MeetingRecord:
    f = MEETING_DIR / f"{meeting_id}.json"
    if not f.exists():
        raise HTTPException(404, {"code": "meeting_not_found"})
    return MeetingRecord.model_validate_json(f.read_text())


@router.delete("/{meeting_id}")
async def delete_meeting(meeting_id: str) -> dict:
    f = MEETING_DIR / f"{meeting_id}.json"
    if not f.exists():
        raise HTTPException(404, {"code": "meeting_not_found"})
    f.unlink()
    (MEETING_DIR / f"{meeting_id}.wav").unlink(missing_ok=True)
    return {"deleted": True, "id": meeting_id}
