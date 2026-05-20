"""VOICE WAKE — wake-word detection locale + always-listening control.

Single responsibility: SOLO stato/config wake-word engine. Niente
detection runtime (gira in solem-voice-wake.service Python subprocess
con openWakeWord o vosk keyword).

ADR-020 → openWakeWord (Apache-2.0) come default: FOSS, offline, modelli
preallenati ("hey jarvis", "alexa", "computer") o custom training.

Endpoint:
  GET  /voice/wake/status        — stato engine + ultima detection
  POST /voice/wake/enable        — start service
  POST /voice/wake/disable       — stop
  GET  /voice/wake/words         — lista wake words attive
  POST /voice/wake/test          — trigger fake detection (per UI debug)
"""
from __future__ import annotations

import json
import shutil
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/voice/wake", tags=["voice-wake"])

STATE_FILE = Path("/var/lib/solem/voice-wake.json")
SERVICE_NAME = "solem-voice-wake.service"


class WakeStatus(BaseModel):
    enabled: bool
    engine: str = "openwakeword"
    active_words: list[str] = Field(default_factory=list)
    last_detection_at: str | None = None
    last_detection_word: str | None = None
    detection_count_24h: int = 0
    privacy_note: str = "Audio NON registrato. Solo trigger event."


class WakeWordConfig(BaseModel):
    words: list[str] = Field(default_factory=lambda: ["hey_jarvis"])
    confidence_threshold: float = Field(0.5, ge=0.0, le=1.0)


def _load_state() -> dict:
    if not STATE_FILE.exists():
        return {
            "enabled": False,
            "active_words": ["hey_jarvis"],
            "detections": [],
        }
    try:
        return json.loads(STATE_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        return {"enabled": False, "active_words": [], "detections": []}


def _save_state(s: dict) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(s, indent=2))


def _service_active() -> bool:
    sc = shutil.which("systemctl")
    if not sc:
        return False
    r = subprocess.run([sc, "is-active", SERVICE_NAME], capture_output=True, text=True, timeout=2)
    return r.stdout.strip() == "active"


@router.get("/status", response_model=WakeStatus)
async def status() -> WakeStatus:
    s = _load_state()
    detections = s.get("detections", [])
    cutoff = time.time() - 86400
    recent = [d for d in detections if d.get("ts", 0) > cutoff]
    last = detections[-1] if detections else None
    return WakeStatus(
        enabled=_service_active(),
        active_words=s.get("active_words", []),
        last_detection_at=datetime.fromtimestamp(last["ts"], tz=timezone.utc).isoformat() if last else None,
        last_detection_word=last["word"] if last else None,
        detection_count_24h=len(recent),
    )


@router.post("/enable")
async def enable() -> dict:
    sc = shutil.which("sudo")
    if not sc:
        raise HTTPException(503, {"code": "sudo_unavailable"})
    r = subprocess.run([sc, "-n", "systemctl", "start", SERVICE_NAME], capture_output=True, text=True, timeout=5)
    s = _load_state()
    s["enabled"] = r.returncode == 0
    _save_state(s)
    return {"ok": r.returncode == 0, "stderr": r.stderr}


@router.post("/disable")
async def disable() -> dict:
    sc = shutil.which("sudo")
    if not sc:
        raise HTTPException(503, {"code": "sudo_unavailable"})
    r = subprocess.run([sc, "-n", "systemctl", "stop", SERVICE_NAME], capture_output=True, text=True, timeout=5)
    s = _load_state()
    s["enabled"] = False
    _save_state(s)
    return {"ok": r.returncode == 0, "stderr": r.stderr}


@router.post("/words", response_model=WakeStatus)
async def set_words(cfg: WakeWordConfig) -> WakeStatus:
    s = _load_state()
    s["active_words"] = cfg.words
    s["confidence_threshold"] = cfg.confidence_threshold
    _save_state(s)
    return await status()


@router.post("/test")
async def test_trigger(word: str = "test") -> dict:
    """Trigger fake detection (per testare wire-up UI)."""
    s = _load_state()
    s.setdefault("detections", []).append({"ts": time.time(), "word": word, "confidence": 0.99, "test": True})
    s["detections"] = s["detections"][-100:]  # cap
    _save_state(s)
    return {"triggered": True, "word": word}
