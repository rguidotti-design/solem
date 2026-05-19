"""VOICE — STT + TTS API locali.

Wrapper sopra whisper.cpp e piper installati da solem-voice.nix.
Tutto on-device, no cloud.

Endpoint:
  POST /voice/stt        — multipart audio → testo
  POST /voice/tts        — testo → wav audio
  GET  /voice/config     — config corrente (modelli, voci)
"""
from __future__ import annotations

import json
import os
import subprocess
import tempfile
from pathlib import Path

from fastapi import APIRouter, File, HTTPException, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

router = APIRouter(prefix="/voice", tags=["voice"])

CONFIG_FILE = Path("/etc/solem/voice-config.json")


class TTSRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=2000)


class STTResponse(BaseModel):
    text: str
    duration_seconds: float | None = None
    model: str


def _load_config() -> dict:
    if not CONFIG_FILE.exists():
        raise HTTPException(503, {
            "code": "voice_not_configured",
            "message": "solem.voice.enable=false in NixOS config. Abilita e rebuild.",
        })
    try:
        return json.loads(CONFIG_FILE.read_text())
    except json.JSONDecodeError as e:
        raise HTTPException(500, {"code": "voice_config_invalid", "error": str(e)})


@router.get("/config", response_model=dict)
async def get_config() -> dict:
    """Config voice corrente (modelli, voci, paths)."""
    return _load_config()


@router.post("/stt", response_model=STTResponse)
async def speech_to_text(audio: UploadFile = File(...)) -> STTResponse:
    """Audio → testo via whisper.cpp."""
    cfg = _load_config()
    stt = cfg.get("stt", {})
    if not Path(stt.get("model_path", "")).exists():
        raise HTTPException(503, {"code": "stt_model_missing", "path": stt.get("model_path")})

    # Salva audio temporaneo
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        f.write(await audio.read())
        audio_path = f.name

    try:
        out = subprocess.run(
            [
                stt["binary"],
                "-m", stt["model_path"],
                "-f", audio_path,
                "--no-prints",
                "--output-txt",
            ],
            capture_output=True, text=True, timeout=120, check=False,
        )
        if out.returncode != 0:
            raise HTTPException(500, {"code": "stt_failed", "stderr": out.stderr[-500:]})
        text = out.stdout.strip()
        return STTResponse(text=text, model=stt.get("model", "unknown"))
    finally:
        try:
            os.unlink(audio_path)
        except OSError:
            pass


@router.post("/tts")
async def text_to_speech(req: TTSRequest) -> FileResponse:
    """Testo → audio WAV via piper."""
    cfg = _load_config()
    tts = cfg.get("tts", {})
    if not Path(tts.get("voice_path", "")).exists():
        raise HTTPException(503, {"code": "tts_voice_missing", "path": tts.get("voice_path")})

    out_path = tempfile.NamedTemporaryFile(suffix=".wav", delete=False).name

    try:
        proc = subprocess.run(
            [tts["binary"], "--model", tts["voice_path"], "--output_file", out_path],
            input=req.text, capture_output=True, text=True, timeout=60, check=False,
        )
        if proc.returncode != 0 or not Path(out_path).exists():
            raise HTTPException(500, {"code": "tts_failed", "stderr": proc.stderr[-500:]})
        return FileResponse(out_path, media_type="audio/wav", filename="solem-tts.wav")
    except subprocess.SubprocessError as e:
        raise HTTPException(500, {"code": "tts_error", "error": str(e)})
