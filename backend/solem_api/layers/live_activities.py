"""LIVE ACTIVITIES — stato runtime aggregato per waybar/PWA.

Single responsibility: SOLO aggregare in un payload unico TUTTO ciò che
serve a una status bar "viva" stile iOS Live Activities:
  - timer focus attivo (con countdown)
  - GAVIO in uso (sta inferendo? quale device del cluster?)
  - backup in corso
  - update disponibile
  - sensori privacy (mic/camera attivi?)
  - cluster load medio

Refresh: chiamato ogni 2-5s da waybar custom module o PWA.

Endpoint:
  GET  /live    — payload aggregato
  GET  /live/svg — render SVG inline per waybar (utile per gtk-launch)
"""
from __future__ import annotations

import json
import time
from pathlib import Path

import httpx
from fastapi import APIRouter

router = APIRouter(prefix="/live", tags=["live-activities"])

STATE_FOCUS = Path("/var/lib/solem/focus.json")
STATE_CLUSTER = Path("/var/lib/solem/cluster.json")
STATE_WAKE = Path("/var/lib/solem/voice-wake.json")


def _json_load(p: Path) -> dict:
    if not p.exists():
        return {}
    try:
        return json.loads(p.read_text())
    except (OSError, json.JSONDecodeError):
        return {}


def _focus_state() -> dict:
    s = _json_load(STATE_FOCUS)
    if not s.get("active"):
        return {"active": False}
    end = s.get("ends_at_ts", 0)
    remaining = max(0, int(end - time.time()))
    return {
        "active": remaining > 0,
        "remaining_sec": remaining,
        "remaining_label": f"{remaining // 60:02d}:{remaining % 60:02d}",
        "presets": s.get("presets", []),
    }


def _cluster_summary() -> dict:
    s = _json_load(STATE_CLUSTER)
    devices = s.get("devices", {})
    hbs = s.get("heartbeats", {})
    now = time.time()
    online = 0
    loads = []
    gpu_in_use = False
    for d_id in devices:
        hb = hbs.get(d_id, {})
        if (now - hb.get("ts", 0)) < 90:
            online += 1
            loads.append(hb.get("load_pct", 0))
            if hb.get("gpu_used_pct", 0) > 5:
                gpu_in_use = True
    avg_load = round(sum(loads) / len(loads), 1) if loads else 0
    return {"online": online, "avg_load_pct": avg_load, "gpu_in_use": gpu_in_use}


async def _backup_running() -> bool:
    # Heuristic: systemctl is-active solem-backup-restic
    import subprocess
    import shutil
    sc = shutil.which("systemctl")
    if not sc:
        return False
    try:
        r = subprocess.run([sc, "is-active", "solem-backup-restic.service"],
                           capture_output=True, text=True, timeout=2)
        return r.stdout.strip() == "active"
    except subprocess.SubprocessError:
        return False


async def _update_available() -> bool:
    last = _json_load(Path("/var/lib/solem/last-update-check.json"))
    return bool(last.get("updates_available"))


async def _wake_active() -> bool:
    s = _json_load(STATE_WAKE)
    return bool(s.get("enabled") or s.get("active_words"))


@router.get("", response_model=dict)
@router.get("/", response_model=dict)
async def live() -> dict:
    return {
        "ts": time.time(),
        "focus": _focus_state(),
        "cluster": _cluster_summary(),
        "backup_running": await _backup_running(),
        "update_available": await _update_available(),
        "voice_wake_active": await _wake_active(),
    }


@router.get("/badge", response_model=dict)
async def badge() -> dict:
    """Stringa compatta per waybar (1-3 char + colore)."""
    state = await live()
    if state["focus"]["active"]:
        return {"label": state["focus"]["remaining_label"], "color": "#c9a961", "blink": True}
    if state["backup_running"]:
        return {"label": "⛁", "color": "#4ab37e", "blink": True}
    if state["update_available"]:
        return {"label": "↻", "color": "#d4a04e", "blink": False}
    if state["cluster"]["gpu_in_use"]:
        return {"label": "◢", "color": "#c9a961", "blink": True}
    return {"label": "SOLEM", "color": "#c9a961", "blink": False}
