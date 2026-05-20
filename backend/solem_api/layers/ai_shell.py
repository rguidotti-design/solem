"""AI SHELL — natural language → shell command (warp-style).

Single responsibility: SOLO trasformare NL in comando shell. NIENTE
esecuzione: ritorna solo il comando + spiegazione. L'utente conferma da
solo (sicurezza).

Endpoint:
  POST /ai-shell/suggest   — "trova file pdf modificati ultima settimana"
                              → comando: find ~ -name "*.pdf" -mtime -7
                              + spiegazione: "ricerca ricorsiva ..."
  POST /ai-shell/explain   — comando bash → spiegazione passo passo
"""
from __future__ import annotations

import os
import re

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/ai-shell", tags=["ai-shell"])

SOLEM_URL = os.environ.get("SOLEM_INTERNAL_URL", "http://127.0.0.1:8001")

DANGEROUS_PATTERNS = [
    r"\brm\s+-rf\s+/\b",
    r"\bmkfs\.",
    r"\bdd\s+.*of=/dev/",
    r"\b:\(\)\{:\|:&\};:",  # fork bomb
    r"\bchmod\s+-R\s+777\s+/",
    r"\b>\s*/etc/(passwd|shadow|sudoers)\b",
]


class SuggestRequest(BaseModel):
    query: str = Field(..., min_length=3)
    shell: str = Field("bash", description="bash|fish|zsh|powershell")
    safe_mode: bool = Field(True, description="Rifiuta comandi pericolosi")


class SuggestResponse(BaseModel):
    command: str
    explanation: str
    dangerous: bool
    warnings: list[str] = Field(default_factory=list)


class ExplainRequest(BaseModel):
    command: str


class ExplainResponse(BaseModel):
    command: str
    explanation: str
    dangerous: bool


def _check_dangerous(cmd: str) -> tuple[bool, list[str]]:
    warnings: list[str] = []
    for pat in DANGEROUS_PATTERNS:
        if re.search(pat, cmd):
            warnings.append(f"match pericoloso: {pat}")
    return bool(warnings), warnings


async def _ai_call(prompt: str) -> str:
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
        return r.json().get("content", "").strip()


@router.post("/suggest", response_model=SuggestResponse)
async def suggest(req: SuggestRequest) -> SuggestResponse:
    prompt = (
        f"You are a shell expert. Convert the following user request into a single "
        f"{req.shell} command. Output format MUST be:\n"
        "COMMAND: <the command>\n"
        "EXPLANATION: <one-line explanation in Italian>\n\n"
        f"Request: {req.query}\n\n"
        "Rules:\n"
        "- Output ONLY the COMMAND and EXPLANATION lines.\n"
        "- Prefer safe, non-destructive commands.\n"
        "- Use modern tools (rg over grep, fd over find, eza over ls).\n"
        "- If the request is unsafe or ambiguous, output 'COMMAND: REFUSED' "
        "and explain why in EXPLANATION."
    )
    raw = await _ai_call(prompt)

    cmd_match = re.search(r"COMMAND:\s*(.+?)(?=\nEXPLANATION:|$)", raw, re.DOTALL)
    exp_match = re.search(r"EXPLANATION:\s*(.+?)$", raw, re.DOTALL)
    command = cmd_match.group(1).strip() if cmd_match else raw.strip().splitlines()[0]
    explanation = exp_match.group(1).strip() if exp_match else "(no explanation provided)"

    dangerous, warnings = _check_dangerous(command)
    if req.safe_mode and dangerous:
        return SuggestResponse(
            command="REFUSED",
            explanation=f"Comando bloccato (safe_mode): {', '.join(warnings)}",
            dangerous=True,
            warnings=warnings,
        )

    return SuggestResponse(
        command=command,
        explanation=explanation,
        dangerous=dangerous,
        warnings=warnings,
    )


@router.post("/explain", response_model=ExplainResponse)
async def explain(req: ExplainRequest) -> ExplainResponse:
    dangerous, _ = _check_dangerous(req.command)
    prompt = (
        f"Explain the following shell command in Italian, step by step. "
        f"List each pipe stage / option. Keep it concise (max 5 bullet points).\n\n"
        f"COMMAND: {req.command}"
    )
    explanation = await _ai_call(prompt)
    return ExplainResponse(command=req.command, explanation=explanation, dangerous=dangerous)
