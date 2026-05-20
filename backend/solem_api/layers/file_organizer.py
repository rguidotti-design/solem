"""FILE ORGANIZER — auto-tag + auto-sort directory via AI.

Single responsibility: SOLO classificare file e proporre azioni di
riordino. NIENTE move automatico (sicurezza: l'utente conferma).

Strategie:
  1. Estensione + MIME → categoria deterministica (immagini, doc, video...)
  2. Per categorie ambigue (.pdf può essere doc/libro/ricetta) →
     chiamata a /ai/route con preview testo (primi 2000 char) →
     suggestion path destinazione semantica
  3. Cluster di file simili → propone tag comune (es. "viaggio Roma 2025")

Endpoint:
  POST /organizer/scan       — analizza dir, ritorna proposte (no apply)
  POST /organizer/apply      — esegue move dopo conferma
  GET  /organizer/rules      — regole categoria→path
  POST /organizer/rules      — aggiunge regola custom
"""
from __future__ import annotations

import json
import mimetypes
import os
import shutil
from pathlib import Path

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/organizer", tags=["file-organizer"])

RULES_FILE = Path("/var/lib/solem/organizer_rules.json")
SOLEM_URL = os.environ.get("SOLEM_INTERNAL_URL", "http://127.0.0.1:8001")

DEFAULT_RULES: dict[str, str] = {
    "image/*":             "Pictures",
    "video/*":             "Videos",
    "audio/*":             "Music",
    "application/pdf":     "Documents/PDF",
    "text/markdown":       "Documents/Notes",
    "text/csv":            "Documents/Data",
    "application/zip":     "Downloads/Archives",
    "application/x-tar":   "Downloads/Archives",
    "application/x-gzip":  "Downloads/Archives",
    "application/x-7z-compressed": "Downloads/Archives",
}


class Proposal(BaseModel):
    source: str
    suggested_destination: str
    reason: str
    confidence: float
    category: str


class ScanRequest(BaseModel):
    directory: str
    use_ai_for_ambiguous: bool = True
    recursive: bool = False


class ApplyRequest(BaseModel):
    proposals: list[Proposal]
    dry_run: bool = True


class Rule(BaseModel):
    mime_pattern: str = Field(..., description="MIME glob es. 'image/*', 'application/pdf'")
    destination: str = Field(..., description="Path relativo a $HOME")


def _load_rules() -> dict[str, str]:
    if not RULES_FILE.exists():
        return DEFAULT_RULES.copy()
    try:
        return {**DEFAULT_RULES, **json.loads(RULES_FILE.read_text())}
    except (OSError, json.JSONDecodeError):
        return DEFAULT_RULES.copy()


def _save_rules(rules: dict[str, str]) -> None:
    RULES_FILE.parent.mkdir(parents=True, exist_ok=True)
    custom = {k: v for k, v in rules.items() if DEFAULT_RULES.get(k) != v}
    RULES_FILE.write_text(json.dumps(custom, indent=2))


def _mime_match(mime: str, pattern: str) -> bool:
    if pattern.endswith("/*"):
        return mime.startswith(pattern[:-2] + "/")
    return mime == pattern


def _classify_static(file: Path) -> tuple[str, str, float] | None:
    """Ritorna (destination, category, confidence)."""
    mime, _ = mimetypes.guess_type(str(file))
    if not mime:
        return None
    rules = _load_rules()
    for pat, dest in rules.items():
        if _mime_match(mime, pat):
            return dest, pat, 0.95
    return None


async def _ai_classify(file: Path) -> tuple[str, str, float]:
    """AI fallback per file ambigui. Manda preview a /ai/route."""
    try:
        if file.stat().st_size < 200_000:
            try:
                preview = file.read_text(encoding="utf-8", errors="replace")[:2000]
            except OSError:
                preview = ""
        else:
            preview = ""
    except OSError:
        preview = ""

    prompt = (
        f"Filename: {file.name}\n"
        f"Preview (first 2000 chars):\n{preview}\n\n"
        "Suggest a SINGLE destination folder path (relative to $HOME) for this file. "
        "Use semantic naming like 'Documents/Recipes' or 'Pictures/Travel/Italy'. "
        "Reply with ONLY the path, nothing else."
    )

    try:
        async with httpx.AsyncClient(timeout=15.0) as c:
            r = await c.post(
                f"{SOLEM_URL}/solem/ai/route",
                json={"messages": [{"role": "user", "content": prompt}], "hint": "auto", "max_tokens": 100},
            )
            if r.status_code != 200:
                return "Documents/Misc", "ai-fallback-error", 0.3
            data = r.json()
            suggestion = data.get("content", "").strip().splitlines()[0]
            # Sanitize
            suggestion = suggestion.replace("..", "").lstrip("/")
            if not suggestion or len(suggestion) > 200:
                return "Documents/Misc", "ai-invalid-response", 0.3
            return suggestion, "ai-classified", 0.7
    except httpx.HTTPError:
        return "Documents/Misc", "ai-unavailable", 0.3


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/health", response_model=dict)
async def org_health() -> dict:
    return {
        "rules_file": str(RULES_FILE),
        "default_rules": DEFAULT_RULES,
        "custom_rules_loaded": len(_load_rules()) - len(DEFAULT_RULES),
    }


@router.get("/rules", response_model=list[Rule])
async def list_rules() -> list[Rule]:
    return [Rule(mime_pattern=k, destination=v) for k, v in _load_rules().items()]


@router.post("/rules", response_model=list[Rule])
async def add_rule(rule: Rule) -> list[Rule]:
    rules = _load_rules()
    rules[rule.mime_pattern] = rule.destination
    _save_rules(rules)
    return await list_rules()


@router.post("/scan", response_model=list[Proposal])
async def scan(req: ScanRequest) -> list[Proposal]:
    src = Path(req.directory).expanduser().resolve()
    if not src.exists() or not src.is_dir():
        raise HTTPException(404, {"code": "directory_not_found"})

    proposals: list[Proposal] = []
    iterator = src.rglob("*") if req.recursive else src.iterdir()
    for f in iterator:
        if not f.is_file():
            continue
        static_result = _classify_static(f)
        if static_result:
            dest, cat, conf = static_result
            mime, _ = mimetypes.guess_type(str(f))
            proposals.append(Proposal(
                source=str(f),
                suggested_destination=str(Path.home() / dest / f.name),
                reason=f"mime={mime}",
                confidence=conf,
                category=cat,
            ))
        elif req.use_ai_for_ambiguous:
            dest, cat, conf = await _ai_classify(f)
            proposals.append(Proposal(
                source=str(f),
                suggested_destination=str(Path.home() / dest / f.name),
                reason="ai-suggestion",
                confidence=conf,
                category=cat,
            ))

    return proposals


@router.post("/apply", response_model=dict)
async def apply(req: ApplyRequest) -> dict:
    moved = 0
    skipped = 0
    errors: list[str] = []
    for p in req.proposals:
        src = Path(p.source)
        dst = Path(p.suggested_destination)
        if not src.exists():
            skipped += 1
            continue
        if req.dry_run:
            moved += 1
            continue
        try:
            dst.parent.mkdir(parents=True, exist_ok=True)
            if dst.exists():
                stem, suffix = dst.stem, dst.suffix
                i = 1
                while dst.exists():
                    dst = dst.with_name(f"{stem}-{i}{suffix}")
                    i += 1
            shutil.move(str(src), str(dst))
            moved += 1
        except OSError as e:
            errors.append(f"{src} → {dst}: {e}")

    return {"moved": moved, "skipped": skipped, "errors": errors, "dry_run": req.dry_run}
