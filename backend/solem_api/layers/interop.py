"""L6 — INTEROP BRIDGE (email, calendar, IoT)

Bridge tra SOLEM e mondo esterno. Step 0: scaffold + endpoint stub.
Step 3+: implementazione reale di ogni bridge.

Filosofia spec: bridge sono OPZIONALI e per-utente. Privacy by design:
ogni record che entra in SOLEM passa per L5 Memory (Livello B = user_universe_memory)
con `privacy_level` esplicito.

Bridge previsti:
  - email IMAP/SMTP  → ingest email in user_universe_memory, source_type='email'
  - calendar CalDAV  → ingest eventi, source_type='calendar'
  - MQTT IoT broker  → publish/subscribe topic IoT, eventi sul bus L3
  - device targeting → Wake-on-LAN, ping, remote shutdown su mesh
  - webhooks         → notifiche outbound (Slack/Discord/Telegram)

Endpoint:
  GET    /interop/bridges                — lista bridge supportati + stato
  GET    /interop/bridges/{name}         — dettagli config
  POST   /interop/bridges/{name}/test    — test connettività (no ingest)
  POST   /interop/email/sync             — trigger sync IMAP
  POST   /interop/calendar/sync          — trigger sync CalDAV
  POST   /interop/iot/publish            — publish MQTT
  POST   /interop/device/wake/{mac}      — Wake-on-LAN
"""
from __future__ import annotations

import socket
import struct
from typing import Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/interop", tags=["interop"])


class Bridge(BaseModel):
    name: str
    type: Literal["email", "calendar", "iot", "device", "webhook"]
    status: Literal["available", "configured", "active", "error", "stub"]
    description: str
    config_required: list[str] = Field(default_factory=list, description="Env vars o file config richiesti")


BRIDGES: list[Bridge] = [
    Bridge(name="email-imap", type="email", status="stub",
           description="Ingest email IMAP → user_universe_memory (privacy: personal/work)",
           config_required=["SOLEM_IMAP_HOST", "SOLEM_IMAP_USER", "SOLEM_IMAP_PASS"]),
    Bridge(name="calendar-caldav", type="calendar", status="stub",
           description="Sync eventi CalDAV → user_universe_memory + context.active_role",
           config_required=["SOLEM_CALDAV_URL", "SOLEM_CALDAV_USER", "SOLEM_CALDAV_PASS"]),
    Bridge(name="mqtt-iot", type="iot", status="stub",
           description="Publish/subscribe MQTT broker per dispositivi IoT",
           config_required=["SOLEM_MQTT_BROKER", "SOLEM_MQTT_USER", "SOLEM_MQTT_PASS"]),
    Bridge(name="wake-on-lan", type="device", status="available",
           description="Risveglia device LAN via magic packet (no config richiesta se sulla mesh)"),
    Bridge(name="webhook-discord", type="webhook", status="stub",
           description="Notifiche outbound a webhook Discord/Slack",
           config_required=["SOLEM_DISCORD_WEBHOOK"]),
]


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/bridges", response_model=list[Bridge])
async def list_bridges() -> list[Bridge]:
    return BRIDGES


@router.get("/bridges/{name}", response_model=Bridge)
async def get_bridge(name: str) -> Bridge:
    for b in BRIDGES:
        if b.name == name:
            return b
    raise HTTPException(404, {"code": "bridge_not_found", "name": name})


@router.post("/bridges/{name}/test")
async def test_bridge(name: str) -> dict:
    """Test connettività (no ingest). Step 0: stub TODO per ogni bridge."""
    bridge = await get_bridge(name)
    return {
        "bridge": name,
        "tested": False,
        "reason": f"Bridge '{name}' è in stato {bridge.status}. Implementazione Step 3+.",
    }


@router.post("/email/sync")
async def email_sync() -> dict:
    return {"status": "stub", "todo": "Step 3+: IMAP sync via imaplib + ingest in user_universe_memory"}


@router.post("/calendar/sync")
async def calendar_sync() -> dict:
    return {"status": "stub", "todo": "Step 3+: CalDAV via caldav python lib"}


class IoTPublish(BaseModel):
    topic: str
    payload: str
    qos: int = Field(0, ge=0, le=2)


@router.post("/iot/publish")
async def iot_publish(req: IoTPublish) -> dict:
    return {"status": "stub", "todo": "Step 3+: paho-mqtt client to SOLEM_MQTT_BROKER", "received": req.model_dump()}


@router.post("/device/wake/{mac}")
async def wake_on_lan(mac: str) -> dict:
    """Wake-on-LAN — funziona già (no config esterna richiesta).

    MAC format: AA:BB:CC:DD:EE:FF oppure AA-BB-CC-DD-EE-FF oppure AABBCCDDEEFF
    """
    mac_clean = mac.replace(":", "").replace("-", "").upper()
    if len(mac_clean) != 12 or not all(c in "0123456789ABCDEF" for c in mac_clean):
        raise HTTPException(400, {"code": "invalid_mac", "mac": mac})

    try:
        # Magic packet: 6 bytes 0xFF + 16 ripetizioni MAC
        magic = b"\xff" * 6 + bytes.fromhex(mac_clean) * 16
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            s.sendto(magic, ("255.255.255.255", 9))
        return {"sent": True, "mac": mac, "magic_len": len(magic)}
    except OSError as e:
        raise HTTPException(500, {"code": "wol_failed", "error": str(e)})
