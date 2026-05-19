"""MCP — Model Context Protocol registry SOLEM (M2.4 anticipato).

GAVIO ha già `api/mcp.py` che espone un MCP server con tool. SOLEM agisce
da gateway: discovery + proxy + sandboxing per future extensions L7.

Standard MCP: https://spec.modelcontextprotocol.io
Protocollo: JSON-RPC 2.0 over HTTP/WebSocket

Endpoint SOLEM:
  GET  /mcp/tools                 — lista tool disponibili (proxy a GAVIO + native)
  POST /mcp/invoke/{tool_name}    — esegui tool con args (sandboxed)
  GET  /mcp/servers               — server MCP registrati
"""
from __future__ import annotations

import json
from typing import Any

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/mcp", tags=["mcp"])

# Server MCP registrati di default
DEFAULT_MCP_SERVERS = [
    {
        "id": "gavio",
        "name": "GAVIO MCP server",
        "url": "http://127.0.0.1:8000/mcp",
        "description": "MCP server interno di GAVIO (api/mcp.py)",
    },
]

# Tool nativi SOLEM (esposti come MCP)
SOLEM_NATIVE_TOOLS = [
    {
        "name": "solem_system_info",
        "description": "Stato sistema SOLEM (uptime, memoria, profilo, servizi)",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "solem_memory_search",
        "description": "Cerca nei record di memoria SOLEM (Livello A)",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "limit": {"type": "integer", "default": 20},
            },
            "required": ["query"],
        },
    },
    {
        "name": "solem_identity_section_get",
        "description": "Leggi una sezione dell'identity engine (es. roles, values)",
        "inputSchema": {
            "type": "object",
            "properties": {"section": {"type": "string"}},
            "required": ["section"],
        },
    },
    {
        "name": "solem_event_publish",
        "description": "Pubblica evento sul bus L3",
        "inputSchema": {
            "type": "object",
            "properties": {
                "topic": {"type": "string"},
                "payload": {"type": "object"},
            },
            "required": ["topic"],
        },
    },
    {
        "name": "solem_constitution_check",
        "description": "Valida azione contro constitution",
        "inputSchema": {
            "type": "object",
            "properties": {
                "action": {"type": "string"},
                "command": {"type": "string"},
            },
            "required": ["action"],
        },
    },
]


class MCPTool(BaseModel):
    name: str
    description: str
    inputSchema: dict[str, Any] = Field(default_factory=dict)
    server_id: str


class MCPInvokeRequest(BaseModel):
    args: dict[str, Any] = Field(default_factory=dict)


class MCPInvokeResponse(BaseModel):
    tool: str
    result: Any
    error: str | None = None


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/servers", response_model=list[dict])
async def list_servers() -> list[dict]:
    """Lista server MCP registrati + stato reachable."""
    out = []
    for s in DEFAULT_MCP_SERVERS:
        reachable = await _ping(s["url"])
        out.append({**s, "reachable": reachable})
    out.append({
        "id": "solem-native",
        "name": "SOLEM native tools",
        "url": "internal",
        "description": "Tool MCP nativi di SOLEM (no esterno)",
        "reachable": True,
    })
    return out


@router.get("/tools", response_model=list[MCPTool])
async def list_tools() -> list[MCPTool]:
    """Tool aggregati: native SOLEM + discovery GAVIO."""
    tools: list[MCPTool] = []

    # Native SOLEM
    for t in SOLEM_NATIVE_TOOLS:
        tools.append(MCPTool(**t, server_id="solem-native"))

    # Discovery GAVIO via MCP JSON-RPC tools/list
    for s in DEFAULT_MCP_SERVERS:
        try:
            tools.extend(await _discover_tools(s["url"], s["id"]))
        except Exception:
            pass

    return tools


@router.post("/invoke/{tool_name}", response_model=MCPInvokeResponse)
async def invoke_tool(tool_name: str, req: MCPInvokeRequest) -> MCPInvokeResponse:
    """Esegui tool MCP. Native SOLEM gestiti localmente, GAVIO proxiati."""
    # Native dispatch
    for t in SOLEM_NATIVE_TOOLS:
        if t["name"] == tool_name:
            return await _invoke_native(tool_name, req.args)

    # Proxy a GAVIO MCP
    for s in DEFAULT_MCP_SERVERS:
        try:
            result = await _invoke_remote(s["url"], tool_name, req.args)
            return MCPInvokeResponse(tool=tool_name, result=result)
        except Exception:
            continue

    raise HTTPException(404, {"code": "tool_not_found", "tool": tool_name})


# ─── Helpers ──────────────────────────────────────────────────────────


async def _ping(url: str) -> bool:
    try:
        async with httpx.AsyncClient(timeout=2.0) as c:
            r = await c.get(url.rsplit("/mcp", 1)[0] + "/health", timeout=2.0)
            return r.status_code == 200
    except httpx.HTTPError:
        return False


async def _discover_tools(url: str, server_id: str) -> list[MCPTool]:
    """Chiama JSON-RPC tools/list sul server MCP remoto."""
    payload = {"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}
    async with httpx.AsyncClient(timeout=3.0) as c:
        r = await c.post(url, json=payload)
        if r.status_code != 200:
            return []
        data = r.json()
        tools_data = data.get("result", {}).get("tools", [])
        return [
            MCPTool(
                name=t.get("name", "unknown"),
                description=t.get("description", ""),
                inputSchema=t.get("inputSchema", {}),
                server_id=server_id,
            )
            for t in tools_data
        ]


async def _invoke_remote(url: str, tool: str, args: dict) -> Any:
    """Invoca tool via JSON-RPC tools/call."""
    payload = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "tools/call",
        "params": {"name": tool, "arguments": args},
    }
    async with httpx.AsyncClient(timeout=30.0) as c:
        r = await c.post(url, json=payload)
        r.raise_for_status()
        data = r.json()
        if "error" in data:
            raise RuntimeError(data["error"].get("message", "MCP error"))
        return data.get("result")


async def _invoke_native(tool: str, args: dict) -> MCPInvokeResponse:
    """Dispatch native tools SOLEM (chiamando endpoint interni)."""
    try:
        if tool == "solem_system_info":
            from . import system as sys_mod
            r = await sys_mod.system_info()
            return MCPInvokeResponse(tool=tool, result=r.model_dump())

        if tool == "solem_memory_search":
            from . import memory as mem_mod
            req = mem_mod.SearchRequest(**args)
            hits = await mem_mod.search(req)
            return MCPInvokeResponse(tool=tool, result=[h.model_dump() for h in hits])

        if tool == "solem_identity_section_get":
            from . import identity as id_mod
            sec = await id_mod.get_section(args["section"])
            return MCPInvokeResponse(tool=tool, result=sec.model_dump())

        if tool == "solem_event_publish":
            from . import events
            ev = events.Event(source="mcp", **args)
            res = await events.publish(ev)
            return MCPInvokeResponse(tool=tool, result=res.model_dump())

        if tool == "solem_constitution_check":
            from . import constitution
            req = constitution.CheckRequest(**args)
            res = await constitution.check_action(req)
            return MCPInvokeResponse(tool=tool, result=res.model_dump())

        return MCPInvokeResponse(tool=tool, result=None, error="tool not implemented")
    except Exception as e:
        return MCPInvokeResponse(tool=tool, result=None, error=str(e))
