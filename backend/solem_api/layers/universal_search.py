"""UNIVERSAL SEARCH — meta-search aggregato: apps + file + capabilities.

Single responsibility: SOLO aggregare risultati da sorgenti diverse e
restituire risultati ordinati. Non implementa nessuna search backend
nativa: federa fs_semantic, capabilities, app list, recents.

Sorgenti:
  - apps           → .desktop files in /run/current-system/sw/share/applications
  - files          → POST /solem/fs/search (lexical FTS5)
  - capabilities   → /solem/capabilities (registry)
  - history        → ultimi N comandi/azioni (state file)
  - settings       → meta entries (es. "wifi", "bluetooth")

Endpoint:
  POST /search           — query unica → ranked results
  GET  /search/sources   — lista sorgenti attive
"""
from __future__ import annotations

import asyncio
import json
import os
from pathlib import Path

import httpx
from fastapi import APIRouter
from pydantic import BaseModel, Field

router = APIRouter(prefix="/search", tags=["universal-search"])

SOLEM_URL = os.environ.get("SOLEM_INTERNAL_URL", "http://127.0.0.1:8001")
APPS_DIR = Path("/run/current-system/sw/share/applications")


class SearchQuery(BaseModel):
    q: str = Field(..., min_length=1)
    limit_per_source: int = Field(5, ge=1, le=20)
    sources: list[str] | None = Field(None, description="Subset di sources; None = tutte")


class SearchResult(BaseModel):
    source: str
    kind: str
    title: str
    subtitle: str | None = None
    action: str
    score: float


# ─── Source: apps (.desktop files) ────────────────────────────────────


def _parse_desktop(path: Path) -> dict | None:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    info: dict = {"NoDisplay": False}
    in_desktop = False
    for line in text.splitlines():
        if line.startswith("["):
            in_desktop = line.strip() == "[Desktop Entry]"
            continue
        if not in_desktop or "=" not in line:
            continue
        k, v = line.split("=", 1)
        info[k.strip()] = v.strip()
    if info.get("NoDisplay") == "true" or info.get("Hidden") == "true":
        return None
    return info if info.get("Name") and info.get("Exec") else None


def _search_apps(q: str, limit: int) -> list[SearchResult]:
    if not APPS_DIR.exists():
        return []
    q_low = q.lower()
    hits: list[SearchResult] = []
    for f in APPS_DIR.glob("*.desktop"):
        info = _parse_desktop(f)
        if not info:
            continue
        name = info.get("Name", "")
        comment = info.get("Comment", "")
        haystack = f"{name} {comment} {info.get('Keywords', '')}".lower()
        if q_low not in haystack:
            continue
        # Score: nome esatto > nome match > comment match
        if name.lower() == q_low:
            score = 1.0
        elif name.lower().startswith(q_low):
            score = 0.9
        elif q_low in name.lower():
            score = 0.7
        else:
            score = 0.4
        hits.append(SearchResult(
            source="apps", kind="application",
            title=name, subtitle=comment or None,
            action=f"exec:{info['Exec']}",
            score=score,
        ))
    hits.sort(key=lambda r: -r.score)
    return hits[:limit]


# ─── Source: files (delega a fs_semantic) ─────────────────────────────


async def _search_files(q: str, limit: int) -> list[SearchResult]:
    try:
        async with httpx.AsyncClient(timeout=3.0) as c:
            r = await c.post(
                f"{SOLEM_URL}/solem/fs/search",
                json={"query": q, "limit": limit, "alpha": 0.5},
            )
            if r.status_code != 200:
                return []
            data = r.json()
    except httpx.HTTPError:
        return []

    return [
        SearchResult(
            source="files", kind="file",
            title=Path(h["path"]).name,
            subtitle=h["path"],
            action=f"open:{h['path']}",
            score=h["score"],
        )
        for h in data
    ]


# ─── Source: capabilities ─────────────────────────────────────────────


async def _search_capabilities(q: str, limit: int) -> list[SearchResult]:
    try:
        async with httpx.AsyncClient(timeout=2.0) as c:
            r = await c.get(f"{SOLEM_URL}/solem/capabilities")
            if r.status_code != 200:
                return []
            data = r.json()
    except httpx.HTTPError:
        return []

    q_low = q.lower()
    hits: list[SearchResult] = []
    for cap in data.get("capabilities", []):
        haystack = f"{cap.get('name', '')} {cap.get('description', '')} {cap.get('id', '')}".lower()
        if q_low not in haystack:
            continue
        score = 0.95 if q_low in cap.get("name", "").lower() else 0.5
        hits.append(SearchResult(
            source="capabilities", kind="capability",
            title=cap.get("name", "?"),
            subtitle=cap.get("description"),
            action=f"invoke:{cap.get('id', '')}",
            score=score,
        ))
    hits.sort(key=lambda r: -r.score)
    return hits[:limit]


# ─── Source: settings (static curated list) ───────────────────────────


_SETTINGS = [
    {"id": "wifi", "name": "Wi-Fi", "kw": "wireless network connessione"},
    {"id": "bluetooth", "name": "Bluetooth", "kw": "bt accoppia auricolari"},
    {"id": "display", "name": "Display", "kw": "schermo monitor risoluzione"},
    {"id": "audio", "name": "Audio", "kw": "volume microfono speaker"},
    {"id": "language", "name": "Lingua", "kw": "lingua locale tastiera"},
    {"id": "privacy", "name": "Privacy", "kw": "telemetria tracking firewall"},
    {"id": "users", "name": "Utenti", "kw": "account password permessi"},
    {"id": "updates", "name": "Aggiornamenti", "kw": "update versione canale"},
    {"id": "backup", "name": "Backup", "kw": "snapshot restic restore"},
]


def _search_settings(q: str, limit: int) -> list[SearchResult]:
    q_low = q.lower()
    hits: list[SearchResult] = []
    for s in _SETTINGS:
        hay = f"{s['name']} {s['kw']}".lower()
        if q_low not in hay:
            continue
        score = 1.0 if q_low == s["name"].lower() else (0.85 if q_low in s["name"].lower() else 0.5)
        hits.append(SearchResult(
            source="settings", kind="setting",
            title=s["name"], subtitle=None,
            action=f"settings:{s['id']}",
            score=score,
        ))
    hits.sort(key=lambda r: -r.score)
    return hits[:limit]


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/sources", response_model=list[str])
async def list_sources() -> list[str]:
    return ["apps", "files", "capabilities", "settings"]


@router.post("", response_model=list[SearchResult])
async def search(q: SearchQuery) -> list[SearchResult]:
    active = q.sources or ["apps", "files", "capabilities", "settings"]

    apps_task = asyncio.to_thread(_search_apps, q.q, q.limit_per_source) if "apps" in active else None
    files_task = _search_files(q.q, q.limit_per_source) if "files" in active else None
    caps_task = _search_capabilities(q.q, q.limit_per_source) if "capabilities" in active else None
    settings_task = asyncio.to_thread(_search_settings, q.q, q.limit_per_source) if "settings" in active else None

    results: list[SearchResult] = []
    if apps_task:
        results.extend(await apps_task)
    if files_task:
        results.extend(await files_task)
    if caps_task:
        results.extend(await caps_task)
    if settings_task:
        results.extend(await settings_task)

    # Global ranking
    results.sort(key=lambda r: -r.score)
    return results
