"""AI AGENTS REGISTRY — multi-AI architecture

Sistema per registrare e invocare AI multiple dentro SOLEM. Step 0: solo GAVIO
come primary. Step 3+: AI specialiste (legale, medica, finanziaria, ecc.)
registrate qui. Step 4+: extension marketplace permette terze parti.

Modello mentale (da spec founder):
       UTENTE
         │
         ▼
       GAVIO          ← AI primary (sempre presente)
      ╱ │ ╲
     ▼  ▼  ▼
   AI  AI  AI         ← specialiste invocate da GAVIO
   leg med fin

Ogni agente:
  - id            es. "gavio", "legal-it"
  - role          primary | specialist | background
  - domain        general | legal | medical | mechanical | financial | …
  - llm_provider  claude | groq | gemini | ollama | local
  - model         "claude-opus-4-7", "llama3.2:3b", ecc.
  - endpoint      URL invocazione (es. http://127.0.0.1:8000 per GAVIO)
  - capabilities  lista cap_id (riferimento al registry L4)
  - can_invoke    lista altri agenti che può chiamare
  - active        true/false (toggle senza disinstallare)

Endpoint:
  GET    /agents                — lista
  GET    /agents/{id}           — dettaglio
  POST   /agents                — registra (owner only)
  PUT    /agents/{id}           — update
  DELETE /agents/{id}           — disattiva (soft delete)
  POST   /agents/{id}/invoke    — proxy invocazione (con event bus audit)
"""
from __future__ import annotations

import json
import time
from typing import Any, Literal

import httpx
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from .db import get_conn, tx
from .users import User, get_current_user

router = APIRouter(prefix="/agents", tags=["agents"])

DEFAULT_OWNER_ID = "00000000-0000-0000-0000-000000000001"


# ─── Schema ───────────────────────────────────────────────────────────


class Agent(BaseModel):
    id: str = Field(..., pattern=r"^[a-z][a-z0-9-]{1,32}$")
    name: str
    role: Literal["primary", "specialist", "background"]
    domain: str = Field(..., description="general | legal | medical | mechanical | financial | research | ...")
    llm_provider: Literal["claude", "groq", "gemini", "ollama", "local", "openai", "mistral", "cerebras"] = "ollama"
    model: str = "llama3.2:3b"
    endpoint: str = Field(..., description="URL HTTP base dell'agente")
    capabilities: list[str] = Field(default_factory=list)
    can_invoke: list[str] = Field(default_factory=list)
    system_prompt: str | None = None
    active: bool = True
    metadata: dict[str, Any] = Field(default_factory=dict)


class AgentCreate(Agent):
    pass


class AgentUpdate(BaseModel):
    name: str | None = None
    role: Literal["primary", "specialist", "background"] | None = None
    domain: str | None = None
    endpoint: str | None = None
    model: str | None = None
    capabilities: list[str] | None = None
    can_invoke: list[str] | None = None
    system_prompt: str | None = None
    active: bool | None = None


class InvokeRequest(BaseModel):
    task: str = Field(..., min_length=1, description="prompt o task da delegare")
    context: dict[str, Any] = Field(default_factory=dict, description="contesto aggiuntivo (identity, ecc.)")
    relevant_memory: list[dict[str, Any]] = Field(default_factory=list)
    timeout_seconds: int = Field(30, ge=1, le=300)


class InvokeResponse(BaseModel):
    agent_id: str
    status: Literal["ok", "timeout", "error"]
    response: dict[str, Any] | str | None = None
    error: str | None = None
    elapsed_ms: int


# ─── Schema DB extension ──────────────────────────────────────────────


def _ensure_agents_table() -> None:
    """Lazy init tabella agents — chiamata al primo accesso."""
    c = get_conn()
    c.execute("""
    CREATE TABLE IF NOT EXISTS agents (
        id            TEXT PRIMARY KEY,
        name          TEXT NOT NULL,
        role          TEXT NOT NULL CHECK(role IN ('primary','specialist','background')),
        domain        TEXT NOT NULL,
        llm_provider  TEXT NOT NULL,
        model         TEXT NOT NULL,
        endpoint      TEXT NOT NULL,
        capabilities  TEXT NOT NULL DEFAULT '[]',
        can_invoke    TEXT NOT NULL DEFAULT '[]',
        system_prompt TEXT,
        active        INTEGER NOT NULL DEFAULT 1,
        metadata      TEXT NOT NULL DEFAULT '{}',
        created_at    TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at    TEXT NOT NULL DEFAULT (datetime('now'))
    );
    """)


DEFAULT_AGENTS = [
    {
        "id": "gavio",
        "name": "GAVIO — AI primaria",
        "role": "primary",
        "domain": "general",
        "llm_provider": "groq",
        "model": "llama-3.3-70b-versatile",
        "endpoint": "http://127.0.0.1:8000",
        "system_prompt": "Sei GAVIO, AI personale di Ruben Guidotti. Diretto, onesto, mai servile. Coordinatore di altre AI specialiste.",
        "can_invoke": ["coder", "researcher", "writer"],
    },
    {
        "id": "coder",
        "name": "Coder — specialista programmazione",
        "role": "specialist",
        "domain": "coding",
        "llm_provider": "ollama",
        "model": "qwen2.5-coder:7b",
        "endpoint": "http://127.0.0.1:11434",
        "system_prompt": "Sei una AI specialista in programmazione. Rispondi con codice corretto, idiomatico, ben commentato. Spiega le scelte tecniche. Linguaggi principali: Python, Rust, TypeScript, Go, Nix.",
    },
    {
        "id": "researcher",
        "name": "Researcher — specialista analisi e ragionamento",
        "role": "specialist",
        "domain": "research",
        "llm_provider": "ollama",
        "model": "phi3:medium",
        "endpoint": "http://127.0.0.1:11434",
        "system_prompt": "Sei una AI specialista in analisi e ragionamento strutturato. Scomponi problemi complessi, valuta evidenze, citi fonti quando possibile, segnala incertezze.",
    },
    {
        "id": "writer",
        "name": "Writer — specialista scrittura creativa",
        "role": "specialist",
        "domain": "creative-writing",
        "llm_provider": "ollama",
        "model": "llama3.2:3b",
        "endpoint": "http://127.0.0.1:11434",
        "system_prompt": "Sei una AI specialista in scrittura creativa in italiano. Tono adattivo (formale/casuale), attenta a ritmo e immagini. Mai retorica vuota.",
    },
]


def _bootstrap_default_agents() -> None:
    """Crea gli agenti di default al primo accesso (se non esistono).

    Tutti gli specialisti usano Ollama locale → zero costi cloud.
    """
    _ensure_agents_table()
    c = get_conn()
    for spec in DEFAULT_AGENTS:
        row = c.execute("SELECT id FROM agents WHERE id = ?", (spec["id"],)).fetchone()
        if row is None:
            with tx() as t:
                t.execute(
                    """INSERT INTO agents
                       (id, name, role, domain, llm_provider, model, endpoint,
                        system_prompt, can_invoke)
                       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                    (
                        spec["id"],
                        spec["name"],
                        spec["role"],
                        spec["domain"],
                        spec["llm_provider"],
                        spec["model"],
                        spec["endpoint"],
                        spec["system_prompt"],
                        json.dumps(spec.get("can_invoke", [])),
                    ),
                )


def _row_to_agent(r) -> Agent:
    return Agent(
        id=r["id"],
        name=r["name"],
        role=r["role"],
        domain=r["domain"],
        llm_provider=r["llm_provider"],
        model=r["model"],
        endpoint=r["endpoint"],
        capabilities=json.loads(r["capabilities"]),
        can_invoke=json.loads(r["can_invoke"]),
        system_prompt=r["system_prompt"],
        active=bool(r["active"]),
        metadata=json.loads(r["metadata"]),
    )


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("", response_model=list[Agent])
async def list_agents(active_only: bool = True) -> list[Agent]:
    _bootstrap_default_agents()
    c = get_conn()
    sql = "SELECT * FROM agents"
    if active_only:
        sql += " WHERE active = 1"
    sql += " ORDER BY role, id"
    rows = c.execute(sql).fetchall()
    return [_row_to_agent(r) for r in rows]


@router.get("/{agent_id}", response_model=Agent)
async def get_agent(agent_id: str) -> Agent:
    _bootstrap_default_agents()
    c = get_conn()
    row = c.execute("SELECT * FROM agents WHERE id = ?", (agent_id,)).fetchone()
    if row is None:
        raise HTTPException(404, {"code": "agent_not_found", "id": agent_id})
    return _row_to_agent(row)


@router.post("", response_model=Agent, status_code=201)
async def create_agent(agent: AgentCreate, user: User = Depends(get_current_user)) -> Agent:
    if user.role != "owner":
        raise HTTPException(403, {"code": "forbidden", "message": "Solo owner registra agenti"})
    _ensure_agents_table()
    with tx() as t:
        try:
            t.execute(
                """INSERT INTO agents
                   (id, name, role, domain, llm_provider, model, endpoint,
                    capabilities, can_invoke, system_prompt, active, metadata)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (
                    agent.id, agent.name, agent.role, agent.domain,
                    agent.llm_provider, agent.model, agent.endpoint,
                    json.dumps(agent.capabilities),
                    json.dumps(agent.can_invoke),
                    agent.system_prompt,
                    int(agent.active),
                    json.dumps(agent.metadata),
                ),
            )
        except Exception as e:
            raise HTTPException(409, {"code": "agent_exists", "message": str(e)})
    return await get_agent(agent.id)


@router.put("/{agent_id}", response_model=Agent)
async def update_agent(agent_id: str, body: AgentUpdate, user: User = Depends(get_current_user)) -> Agent:
    if user.role != "owner":
        raise HTTPException(403, {"code": "forbidden"})
    _ensure_agents_table()
    updates = body.model_dump(exclude_unset=True)
    if not updates:
        return await get_agent(agent_id)

    # JSON-serialize list fields
    for k in ("capabilities", "can_invoke", "metadata"):
        if k in updates and updates[k] is not None:
            updates[k] = json.dumps(updates[k])
    if "active" in updates:
        updates["active"] = int(updates["active"])

    set_clause = ", ".join(f"{k} = ?" for k in updates)
    values = list(updates.values()) + [agent_id]
    with tx() as t:
        cur = t.execute(
            f"UPDATE agents SET {set_clause}, updated_at = datetime('now') WHERE id = ?",
            values,
        )
        if cur.rowcount == 0:
            raise HTTPException(404, {"code": "agent_not_found", "id": agent_id})
    return await get_agent(agent_id)


@router.delete("/{agent_id}")
async def deactivate_agent(agent_id: str, user: User = Depends(get_current_user)) -> dict:
    if user.role != "owner":
        raise HTTPException(403, {"code": "forbidden"})
    if agent_id == "gavio":
        raise HTTPException(400, {"code": "cannot_remove_primary", "message": "GAVIO è AI primary, non si elimina"})
    _ensure_agents_table()
    with tx() as t:
        cur = t.execute("UPDATE agents SET active = 0, updated_at = datetime('now') WHERE id = ?", (agent_id,))
        if cur.rowcount == 0:
            raise HTTPException(404, {"code": "agent_not_found", "id": agent_id})
    return {"deactivated": True, "id": agent_id}


@router.post("/{agent_id}/invoke", response_model=InvokeResponse)
async def invoke_agent(agent_id: str, req: InvokeRequest) -> InvokeResponse:
    """Proxy invocazione agente. Audit automatico via event bus L3.

    Step 0: invio HTTP POST a {agent.endpoint}/invoke con payload standard.
    Step 3+: protocollo AI-to-AI strutturato (Pydantic schema, retry, fallback).
    """
    agent = await get_agent(agent_id)
    if not agent.active:
        raise HTTPException(409, {"code": "agent_inactive", "id": agent_id})

    start = time.monotonic()

    # Publish event "agent.invocation_start"
    await _publish_event("agent.invocation_start", {
        "agent_id": agent_id,
        "task_preview": req.task[:200],
        "by": DEFAULT_OWNER_ID,
    })

    # Costruisce URL + payload in base al provider
    url, payload = _build_invocation(agent, req)

    try:
        async with httpx.AsyncClient(timeout=float(req.timeout_seconds)) as client:
            r = await client.post(url, json=payload)
            elapsed = int((time.monotonic() - start) * 1000)
            try:
                response_data = r.json()
            except Exception:
                response_data = r.text

            # Estrae output testuale a seconda del provider
            response_data = _extract_output(agent, response_data)

            status = "ok" if r.status_code < 400 else "error"
            await _publish_event("agent.invocation_done", {
                "agent_id": agent_id,
                "status": status,
                "elapsed_ms": elapsed,
            })

            return InvokeResponse(
                agent_id=agent_id,
                status=status,
                response=response_data if status == "ok" else None,
                error=str(response_data) if status == "error" else None,
                elapsed_ms=elapsed,
            )
    except httpx.TimeoutException:
        elapsed = int((time.monotonic() - start) * 1000)
        await _publish_event("agent.invocation_timeout", {"agent_id": agent_id, "elapsed_ms": elapsed})
        return InvokeResponse(agent_id=agent_id, status="timeout", elapsed_ms=elapsed, error="timeout")
    except httpx.HTTPError as e:
        elapsed = int((time.monotonic() - start) * 1000)
        await _publish_event("agent.invocation_error", {"agent_id": agent_id, "error": str(e)})
        return InvokeResponse(agent_id=agent_id, status="error", elapsed_ms=elapsed, error=str(e))


def _build_invocation(agent: Agent, req: InvokeRequest) -> tuple[str, dict]:
    """Costruisce URL + payload per il provider specifico.

    Provider supportati nativamente:
      - ollama       → POST /api/generate (locale, gratis illimitato)
      - groq         → POST GAVIO che usa Groq free tier
      - local/openai → POST /invoke generico (per AI custom o extensions)
    """
    base = agent.endpoint.rstrip("/")

    if agent.llm_provider == "ollama":
        # Ollama native API
        full_prompt = req.task
        if req.context:
            ctx_str = "\n".join(f"{k}: {v}" for k, v in req.context.items())
            full_prompt = f"[Contesto]\n{ctx_str}\n\n[Task]\n{req.task}"
        return f"{base}/api/generate", {
            "model": agent.model,
            "prompt": full_prompt,
            "system": agent.system_prompt or "",
            "stream": False,
        }

    # Default: protocollo SOLEM /invoke generico (per GAVIO + extensions)
    return f"{base}/invoke", {
        "task": req.task,
        "context": req.context,
        "relevant_memory": req.relevant_memory,
        "system_prompt": agent.system_prompt,
        "model": agent.model,
    }


def _extract_output(agent: Agent, raw: Any) -> Any:
    """Estrae output testuale leggibile dalla risposta provider-specific."""
    if not isinstance(raw, dict):
        return raw

    if agent.llm_provider == "ollama":
        # Ollama /api/generate ritorna {response, done, ...}
        if "response" in raw:
            return {"text": raw["response"], "model": raw.get("model"), "done": raw.get("done")}

    return raw


async def _publish_event(topic: str, payload: dict) -> None:
    """Publish locale al bus L3 (best-effort, non blocca)."""
    try:
        from . import events
        await events.publish(events.Event(source="agents.registry", topic=topic, payload=payload))
    except Exception:
        pass
