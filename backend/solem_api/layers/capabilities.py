"""L4 — CAPABILITIES POOL (registry dichiarativo + invocazione AI-friendly)

Sostituisce il vecchio auto-discovery via GAVIO OpenAPI (in main.py) con un
sistema reale: ogni capability è dichiarata da un manifest YAML/JSON con
schema esplicito, permessi richiesti, esempi di invocazione.

Modello capability:
  - id            es. "system.info"
  - source        solem | gavio | extension
  - name          "System info"
  - description   testo lungo per AI
  - manifest      schema input/output (JSON Schema)
  - permissions   roles richiesti
  - invoke_url    endpoint relativo per invocazione (es. "/solem/system/info")
  - method        GET/POST/PUT/DELETE
  - tags          [meta, identity, mesh, ai, ...]

Endpoint:
  GET  /capabilities                — lista (filtri: source, tag, q)
  GET  /capabilities/{id}           — manifest dettagliato
  POST /capabilities/{id}/invoke    — proxy invocazione (con auth + audit)

NB: SOSTITUISCE l'endpoint /solem/capabilities che era in main.py (vecchio
stub). Più ricco, AI-first, machine-readable.
"""
from __future__ import annotations

import asyncio
import json
from typing import Any, Literal

import httpx
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field

router = APIRouter(prefix="/capabilities", tags=["capabilities"])


# ─── Schema ───────────────────────────────────────────────────────────


class CapabilityManifest(BaseModel):
    id: str = Field(..., description="ID univoco, formato 'domain.action'")
    source: Literal["solem", "gavio", "extension"]
    name: str
    description: str
    method: Literal["GET", "POST", "PUT", "DELETE", "PATCH"] = "GET"
    invoke_url: str = Field(..., description="Path relativo per invocazione")
    permissions: list[str] = Field(default_factory=lambda: ["user"])
    tags: list[str] = Field(default_factory=list)
    input_schema: dict[str, Any] | None = Field(None, description="JSON Schema input")
    output_schema: dict[str, Any] | None = Field(None, description="JSON Schema output")
    example_input: dict[str, Any] | None = None
    example_output: dict[str, Any] | None = None


class CapabilitiesList(BaseModel):
    total: int
    sources: dict[str, int]   # quante per source
    tags: dict[str, int]      # quante per tag
    capabilities: list[CapabilityManifest]


class InvokeResponse(BaseModel):
    capability_id: str
    status_code: int
    elapsed_ms: int
    output: dict[str, Any] | list[Any] | str | None = None
    error: str | None = None


# ─── Registry: native SOLEM (dichiarativo, in-code) ──────────────────


SOLEM_NATIVE: list[CapabilityManifest] = [
    CapabilityManifest(
        id="system.info",
        source="solem",
        name="Stato sistema",
        description="Info hardware + kernel + profilo + uptime + versione NixOS",
        method="GET",
        invoke_url="/solem/system/info",
        permissions=["user"],
        tags=["meta", "system"],
        example_output={"hostname": "solem", "kernel": "6.6.94", "profile": "creator"},
    ),
    CapabilityManifest(
        id="system.generations",
        source="solem",
        name="Generazioni NixOS",
        description="Lista generazioni di sistema disponibili per rollback",
        method="GET",
        invoke_url="/solem/system/generations",
        permissions=["user"],
        tags=["meta", "system", "rollback"],
    ),
    CapabilityManifest(
        id="system.rebuild",
        source="solem",
        name="Rebuild NixOS",
        description="Trigger nixos-rebuild switch (riconfigura il sistema da flake)",
        method="POST",
        invoke_url="/solem/system/rebuild",
        permissions=["owner"],
        tags=["system", "destructive"],
    ),
    CapabilityManifest(
        id="system.rollback",
        source="solem",
        name="Rollback NixOS",
        description="Torna alla generation precedente",
        method="POST",
        invoke_url="/solem/system/rollback",
        permissions=["owner"],
        tags=["system", "destructive"],
    ),
    CapabilityManifest(
        id="identity.me",
        source="solem",
        name="Identità utente",
        description="Identità dell'utente corrente: anagrafica + 5 sezioni standard (roles/values/goals/routine/persone) + custom",
        method="GET",
        invoke_url="/solem/identity/me",
        permissions=["user"],
        tags=["identity", "l1"],
    ),
    CapabilityManifest(
        id="identity.section.upsert",
        source="solem",
        name="Aggiorna sezione identità",
        description="Crea/aggiorna una sezione (es. roles, goals, custom_X) con versioning automatico",
        method="PUT",
        invoke_url="/solem/identity/sections/{key}",
        permissions=["user"],
        tags=["identity", "l1", "write"],
        input_schema={"type": "object", "properties": {"content": {"type": ["array", "object"]}}, "required": ["content"]},
        example_input={"content": ["founder", "operator", "owner"]},
    ),
    CapabilityManifest(
        id="context.now",
        source="solem",
        name="Contesto attuale",
        description="Snapshot ultimo + delta tempo (where/when/active_role/current_task)",
        method="GET",
        invoke_url="/solem/context/now",
        permissions=["user"],
        tags=["context", "l2"],
    ),
    CapabilityManifest(
        id="context.snapshot",
        source="solem",
        name="Push snapshot contesto",
        description="Aggiunge uno snapshot di contesto. Usato da device client + timer 5min systemd",
        method="POST",
        invoke_url="/solem/context/snapshot",
        permissions=["user"],
        tags=["context", "l2", "write"],
    ),
    CapabilityManifest(
        id="events.publish",
        source="solem",
        name="Pubblica evento",
        description="Publish evento sul bus interno (topic-based pub/sub)",
        method="POST",
        invoke_url="/solem/events/publish",
        permissions=["user"],
        tags=["events", "l3", "write"],
        example_input={"source": "gavio", "topic": "user.intent", "payload": {"intent": "open_browser"}},
    ),
    CapabilityManifest(
        id="events.stream",
        source="solem",
        name="Stream eventi SSE",
        description="Sottoscrizione live agli eventi (Server-Sent Events). Filtro topic prefix.",
        method="GET",
        invoke_url="/solem/events/stream",
        permissions=["user"],
        tags=["events", "l3", "streaming"],
    ),
    CapabilityManifest(
        id="memory.store",
        source="solem",
        name="Salva memoria",
        description="Persiste un nuovo record in solem_memory (interazioni AI). Embedding calcolato Step 3+",
        method="POST",
        invoke_url="/solem/memory/store",
        permissions=["user"],
        tags=["memory", "l5", "write"],
    ),
    CapabilityManifest(
        id="memory.search",
        source="solem",
        name="Ricerca memoria",
        description="Ricerca testuale sui record di memoria. Step 0: LIKE; Step 3+: cosine vector",
        method="POST",
        invoke_url="/solem/memory/search",
        permissions=["user"],
        tags=["memory", "l5", "search"],
    ),
    CapabilityManifest(
        id="memory.universe.store",
        source="solem",
        name="Ingest universo esterno",
        description="Salva record dal mondo dell'utente (email/calendar/file/photo). Con privacy_level: public/work/personal/sacred",
        method="POST",
        invoke_url="/solem/memory/universe/store",
        permissions=["user"],
        tags=["memory", "l5", "privacy"],
    ),
    CapabilityManifest(
        id="pairing.start",
        source="solem",
        name="Genera PIN pairing",
        description="Crea PIN BBM-style 8-hex per pairing nuovo device alla mesh WireGuard",
        method="POST",
        invoke_url="/solem/pairing/start",
        permissions=["owner"],
        tags=["mesh", "pairing", "security"],
    ),
    CapabilityManifest(
        id="pairing.confirm",
        source="solem",
        name="Completa pairing",
        description="Device esterno usa il PIN per ricevere config WireGuard + cert mTLS",
        method="POST",
        invoke_url="/solem/pairing/confirm",
        permissions=["public"],
        tags=["mesh", "pairing", "security"],
    ),
    CapabilityManifest(
        id="auth.login",
        source="solem",
        name="Login utente",
        description="Autentica con username + password. Ritorna token sessione (TTL 7gg).",
        method="POST",
        invoke_url="/solem/auth/login",
        permissions=["public"],
        tags=["auth", "users"],
    ),
    CapabilityManifest(
        id="users.me",
        source="solem",
        name="Utente corrente",
        description="Profilo dell'utente autenticato (o owner di default in Step 0)",
        method="GET",
        invoke_url="/solem/users/me",
        permissions=["user"],
        tags=["users"],
    ),
]


# ─── GAVIO discovery (live via OpenAPI) ──────────────────────────────


async def _discover_gavio() -> list[CapabilityManifest]:
    try:
        async with httpx.AsyncClient(timeout=2.0) as client:
            r = await client.get("http://127.0.0.1:8000/openapi.json")
            if r.status_code != 200:
                return []
            spec = r.json()
    except (httpx.HTTPError, json.JSONDecodeError):
        return []

    caps: list[CapabilityManifest] = []
    for path, methods in spec.get("paths", {}).items():
        for method, op in methods.items():
            if method.upper() not in {"GET", "POST", "PUT", "DELETE", "PATCH"}:
                continue
            op_id = op.get("operationId") or f"{method}_{path.replace('/', '_').strip('_')}"
            tags = op.get("tags", []) or ["gavio"]
            caps.append(CapabilityManifest(
                id=f"gavio.{op_id.lower()}",
                source="gavio",
                name=op.get("summary") or op_id,
                description=op.get("description") or f"{method.upper()} {path}",
                method=method.upper(),
                invoke_url=f"http://127.0.0.1:8000{path}",
                permissions=["user"],
                tags=["gavio"] + tags,
            ))
    return caps


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("", response_model=CapabilitiesList)
async def list_capabilities(
    source: Literal["solem", "gavio", "extension"] | None = None,
    tag: str | None = None,
    q: str | None = Query(None, description="filtro testuale su id/name/description"),
) -> CapabilitiesList:
    gavio_caps = await _discover_gavio()
    all_caps = SOLEM_NATIVE + gavio_caps

    # Apply filters
    filtered = all_caps
    if source:
        filtered = [c for c in filtered if c.source == source]
    if tag:
        filtered = [c for c in filtered if tag in c.tags]
    if q:
        ql = q.lower()
        filtered = [c for c in filtered
                    if ql in c.id.lower() or ql in c.name.lower() or ql in c.description.lower()]

    # Aggregate counts
    sources: dict[str, int] = {}
    tags: dict[str, int] = {}
    for c in filtered:
        sources[c.source] = sources.get(c.source, 0) + 1
        for t in c.tags:
            tags[t] = tags.get(t, 0) + 1

    return CapabilitiesList(
        total=len(filtered),
        sources=sources,
        tags=dict(sorted(tags.items(), key=lambda x: -x[1])),
        capabilities=filtered,
    )


@router.get("/{capability_id}", response_model=CapabilityManifest)
async def get_capability(capability_id: str) -> CapabilityManifest:
    gavio_caps = await _discover_gavio()
    for c in SOLEM_NATIVE + gavio_caps:
        if c.id == capability_id:
            return c
    raise HTTPException(404, {"code": "capability_not_found", "id": capability_id})


@router.post("/{capability_id}/invoke", response_model=InvokeResponse)
async def invoke_capability(capability_id: str, body: dict[str, Any] | None = None) -> InvokeResponse:
    """Proxy invocazione capability. Audit log automatico.

    NB: Step 0 senza auth granulare — chiunque può invocare. Step 2+ controllerà
    permissions del manifest contro role utente loggato.
    """
    import time
    cap = await get_capability(capability_id)
    url = cap.invoke_url
    if not url.startswith("http"):
        url = f"http://127.0.0.1:8001{url}"

    start = time.monotonic()
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.request(cap.method, url, json=body if cap.method != "GET" else None)
        elapsed = int((time.monotonic() - start) * 1000)
        try:
            output = resp.json()
        except Exception:
            output = resp.text
        return InvokeResponse(
            capability_id=capability_id,
            status_code=resp.status_code,
            elapsed_ms=elapsed,
            output=output if resp.status_code < 400 else None,
            error=output if resp.status_code >= 400 else None,
        )
    except httpx.HTTPError as e:
        elapsed = int((time.monotonic() - start) * 1000)
        return InvokeResponse(
            capability_id=capability_id,
            status_code=0,
            elapsed_ms=elapsed,
            error=str(e),
        )
