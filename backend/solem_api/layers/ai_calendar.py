"""AI CALENDAR — NL → evento ICS (CalDAV via Radicale).

Single responsibility: SOLO parsing NL ("domani alle 15 dentista") in
RFC 5545 VEVENT. Niente delivery (delegato a Radicale via PUT iCal).

Endpoint:
  POST /ai-calendar/parse    — NL → VEVENT JSON
  POST /ai-calendar/create   — parse + PUT su Radicale
  GET  /ai-calendar/events   — lista eventi dal calendario default
"""
from __future__ import annotations

import json
import os
import re
import uuid
from datetime import datetime, timedelta, timezone

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/ai-calendar", tags=["ai-calendar"])

SOLEM_URL = os.environ.get("SOLEM_INTERNAL_URL", "http://127.0.0.1:8001")
RADICALE_URL = os.environ.get("RADICALE_URL", "http://127.0.0.1:5232")
DEFAULT_CAL = os.environ.get("SOLEM_DEFAULT_CALENDAR", "default/main")


class ParseRequest(BaseModel):
    text: str = Field(..., min_length=3)
    timezone: str = Field("Europe/Rome")
    now_override: str | None = Field(None, description="ISO datetime per testing")


class ParsedEvent(BaseModel):
    title: str
    start: str  # ISO 8601
    end: str
    location: str | None = None
    description: str | None = None
    rrule: str | None = None


class CreateRequest(BaseModel):
    text: str
    calendar: str = DEFAULT_CAL
    timezone: str = "Europe/Rome"


# ─── Helpers ──────────────────────────────────────────────────────────


def _now(tz: str, override: str | None) -> datetime:
    if override:
        return datetime.fromisoformat(override)
    return datetime.now(timezone.utc).astimezone()


async def _ai_parse(text: str, ref_dt: datetime) -> dict:
    """Chiede al LLM di estrarre evento → JSON."""
    schema_example = {
        "title": "Dentista",
        "start": "2026-05-21T15:00:00+02:00",
        "end": "2026-05-21T16:00:00+02:00",
        "location": "",
        "description": "",
        "rrule": "",
    }
    prompt = (
        f"Current datetime: {ref_dt.isoformat()}\n"
        f"User request: {text}\n\n"
        "Extract a calendar event from the request. Output ONLY valid JSON with this schema:\n"
        f"{json.dumps(schema_example, indent=2)}\n\n"
        "Rules:\n"
        "- start/end in ISO 8601 with timezone offset.\n"
        "- If duration not specified, default 1 hour.\n"
        "- location/description/rrule can be empty strings.\n"
        "- rrule is RFC 5545 RRULE (e.g., 'FREQ=WEEKLY;BYDAY=MO') or empty.\n"
        "- Reply ONLY with the JSON object, no markdown fences."
    )

    async with httpx.AsyncClient(timeout=30.0) as c:
        r = await c.post(
            f"{SOLEM_URL}/solem/ai/route",
            json={
                "messages": [{"role": "user", "content": prompt}],
                "hint": "code",
                "max_tokens": 400,
                "temperature": 0.1,
            },
        )
        if r.status_code != 200:
            raise HTTPException(503, {"code": "ai_router_unavailable"})
        raw = r.json().get("content", "")

    raw = re.sub(r"^```(?:json)?", "", raw.strip()).rstrip("`").strip()
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        m = re.search(r"\{.*\}", raw, re.DOTALL)
        if not m:
            raise HTTPException(500, {"code": "parse_failed", "raw": raw[:500]})
        try:
            return json.loads(m.group(0))
        except json.JSONDecodeError as e:
            raise HTTPException(500, {"code": "json_decode_failed", "error": str(e), "raw": raw[:500]})


def _to_ical(ev: dict) -> str:
    """Costruisce VEVENT iCal RFC 5545."""
    uid = uuid.uuid4().hex + "@solem.local"
    dtstamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    def fmt(iso: str) -> str:
        dt = datetime.fromisoformat(iso)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//SOLEM//ai-calendar//IT",
        "BEGIN:VEVENT",
        f"UID:{uid}",
        f"DTSTAMP:{dtstamp}",
        f"DTSTART:{fmt(ev['start'])}",
        f"DTEND:{fmt(ev['end'])}",
        f"SUMMARY:{ev.get('title', 'Evento')}",
    ]
    if ev.get("location"):
        lines.append(f"LOCATION:{ev['location']}")
    if ev.get("description"):
        lines.append(f"DESCRIPTION:{ev['description']}")
    if ev.get("rrule"):
        lines.append(f"RRULE:{ev['rrule']}")
    lines.extend(["END:VEVENT", "END:VCALENDAR"])
    return "\r\n".join(lines) + "\r\n"


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/health", response_model=dict)
async def cal_health() -> dict:
    try:
        async with httpx.AsyncClient(timeout=2.0) as c:
            r = await c.get(f"{RADICALE_URL}/")
            radicale_up = r.status_code in (200, 401, 405)
    except httpx.HTTPError:
        radicale_up = False
    return {
        "radicale_url": RADICALE_URL,
        "radicale_up": radicale_up,
        "default_calendar": DEFAULT_CAL,
    }


@router.post("/parse", response_model=ParsedEvent)
async def parse(req: ParseRequest) -> ParsedEvent:
    ref = _now(req.timezone, req.now_override)
    parsed = await _ai_parse(req.text, ref)

    # Default 1h se end mancante
    if not parsed.get("end"):
        start_dt = datetime.fromisoformat(parsed["start"])
        parsed["end"] = (start_dt + timedelta(hours=1)).isoformat()

    return ParsedEvent(**{k: parsed.get(k) or None for k in ParsedEvent.model_fields})


@router.post("/create", response_model=dict)
async def create(req: CreateRequest) -> dict:
    ref = _now(req.timezone, None)
    parsed = await _ai_parse(req.text, ref)
    ical = _to_ical(parsed)

    event_uid = re.search(r"UID:([^\r\n]+)", ical).group(1)
    url = f"{RADICALE_URL}/{req.calendar}/{event_uid}.ics"

    try:
        async with httpx.AsyncClient(timeout=10.0) as c:
            r = await c.put(url, content=ical, headers={"Content-Type": "text/calendar"})
            if r.status_code not in (200, 201, 204):
                raise HTTPException(r.status_code, {"code": "caldav_put_failed", "body": r.text[:500]})
    except httpx.HTTPError as e:
        raise HTTPException(502, {"code": "radicale_unreachable", "error": str(e)})

    return {
        "created": True,
        "uid": event_uid,
        "url": url,
        "parsed": parsed,
    }
