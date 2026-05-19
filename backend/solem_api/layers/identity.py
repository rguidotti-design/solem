"""L1 — IDENTITY ENGINE

Chi è ciascun utente di SOLEM. Persiste su SQLite (db.py).

Modello dati:
  identities         — anagrafica base (user_id, name, email)
  identity_sections  — 5 sezioni standard + N libere (JSON blob per sezione)

Sezioni standard:
  roles      — ruoli che l'utente ricopre (founder, padre, runner, ecc.)
  values     — valori guida (libertà, qualità, famiglia, ecc.)
  goals      — obiettivi attuali (per area/orizzonte)
  routine    — abitudini ricorrenti
  persone    — relazioni significative

Sezioni custom: qualunque chiave non in standard → libera, formato JSON.

Endpoint:
  GET    /identity/me                    → identità completa (anagr. + sezioni)
  GET    /identity/sections              → solo sezioni
  GET    /identity/sections/{key}        → singola sezione
  PUT    /identity/sections/{key}        → upsert sezione (con versioning)
  DELETE /identity/sections/{key}        → rimuovi sezione
"""
from __future__ import annotations

import json
import uuid
from datetime import datetime, timezone
from typing import Any, Literal

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, EmailStr, Field

from .db import get_conn, tx

router = APIRouter(prefix="/identity", tags=["identity"])

# Step 0: single-user hardcoded. Step 2: dedotto da JWT.
DEFAULT_USER_ID = "00000000-0000-0000-0000-000000000001"

STANDARD_SECTIONS = {"roles", "values", "goals", "routine", "persone"}


# ─── Schemas ──────────────────────────────────────────────────────────


class IdentityBase(BaseModel):
    user_id: str
    name: str
    email: str  # EmailStr richiederebbe email-validator; teniamo str
    created_at: str
    updated_at: str


class IdentitySection(BaseModel):
    section_key: str = Field(..., description="standard (roles/values/goals/routine/persone) o custom_*")
    content: dict[str, Any] | list[Any] = Field(..., description="contenuto JSON arbitrario")
    version: int = 1
    updated_at: str
    is_standard: bool


class IdentityFull(IdentityBase):
    sections: dict[str, IdentitySection]


class SectionUpsert(BaseModel):
    content: dict[str, Any] | list[Any]


# ─── Bootstrap: crea identity di default al primo accesso ────────────


def _ensure_default_identity() -> None:
    c = get_conn()
    row = c.execute(
        "SELECT user_id FROM identities WHERE user_id = ?",
        (DEFAULT_USER_ID,),
    ).fetchone()
    if row is None:
        with tx() as t:
            t.execute(
                "INSERT INTO identities (user_id, name, email) VALUES (?, ?, ?)",
                (DEFAULT_USER_ID, "Ruben Guidotti", "guidottrbn@gmail.com"),
            )
            # Sezioni iniziali vuote per le 5 standard
            for key in STANDARD_SECTIONS:
                t.execute(
                    "INSERT INTO identity_sections (user_id, section_key, content) VALUES (?, ?, ?)",
                    (DEFAULT_USER_ID, key, "[]" if key in {"roles", "values"} else "{}"),
                )


def _row_to_identity_base(row) -> IdentityBase:
    return IdentityBase(
        user_id=row["user_id"],
        name=row["name"],
        email=row["email"],
        created_at=row["created_at"],
        updated_at=row["updated_at"],
    )


def _row_to_section(row) -> IdentitySection:
    return IdentitySection(
        section_key=row["section_key"],
        content=json.loads(row["content"]),
        version=row["version"],
        updated_at=row["updated_at"],
        is_standard=row["section_key"] in STANDARD_SECTIONS,
    )


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/me", response_model=IdentityFull)
async def get_me() -> IdentityFull:
    """Identità completa dell'utente corrente (anagrafica + tutte le sezioni)."""
    _ensure_default_identity()
    c = get_conn()
    row = c.execute("SELECT * FROM identities WHERE user_id = ?", (DEFAULT_USER_ID,)).fetchone()
    if row is None:
        raise HTTPException(404, "Identity non trovata")

    base = _row_to_identity_base(row)
    rows = c.execute(
        "SELECT section_key, content, version, updated_at FROM identity_sections WHERE user_id = ?",
        (DEFAULT_USER_ID,),
    ).fetchall()
    sections = {r["section_key"]: _row_to_section(r) for r in rows}

    return IdentityFull(**base.model_dump(), sections=sections)


@router.get("/sections", response_model=dict[str, IdentitySection])
async def list_sections() -> dict[str, IdentitySection]:
    _ensure_default_identity()
    c = get_conn()
    rows = c.execute(
        "SELECT section_key, content, version, updated_at FROM identity_sections WHERE user_id = ?",
        (DEFAULT_USER_ID,),
    ).fetchall()
    return {r["section_key"]: _row_to_section(r) for r in rows}


@router.get("/sections/{key}", response_model=IdentitySection)
async def get_section(key: str) -> IdentitySection:
    _ensure_default_identity()
    c = get_conn()
    row = c.execute(
        "SELECT section_key, content, version, updated_at FROM identity_sections WHERE user_id = ? AND section_key = ?",
        (DEFAULT_USER_ID, key),
    ).fetchone()
    if row is None:
        raise HTTPException(404, {"code": "section_not_found", "key": key})
    return _row_to_section(row)


@router.put("/sections/{key}", response_model=IdentitySection)
async def upsert_section(key: str, body: SectionUpsert) -> IdentitySection:
    """Crea o aggiorna una sezione identità. Incrementa version automaticamente."""
    _ensure_default_identity()

    # Validazione chiave: standard o custom_*
    if key not in STANDARD_SECTIONS and not key.startswith("custom_"):
        raise HTTPException(
            400,
            {
                "code": "invalid_section_key",
                "message": f"Chiave '{key}' non valida. Usa standard ({sorted(STANDARD_SECTIONS)}) o prefisso 'custom_'.",
            },
        )

    content_json = json.dumps(body.content, ensure_ascii=False)
    with tx() as t:
        # Upsert con version++
        existing = t.execute(
            "SELECT version FROM identity_sections WHERE user_id = ? AND section_key = ?",
            (DEFAULT_USER_ID, key),
        ).fetchone()
        new_version = (existing["version"] + 1) if existing else 1
        t.execute(
            """
            INSERT INTO identity_sections (user_id, section_key, content, version, updated_at)
            VALUES (?, ?, ?, ?, datetime('now'))
            ON CONFLICT(user_id, section_key)
            DO UPDATE SET content = excluded.content,
                          version = excluded.version,
                          updated_at = excluded.updated_at
            """,
            (DEFAULT_USER_ID, key, content_json, new_version),
        )

    return await get_section(key)


@router.delete("/sections/{key}")
async def delete_section(key: str) -> dict:
    if key in STANDARD_SECTIONS:
        raise HTTPException(
            400,
            {"code": "cannot_delete_standard", "message": f"La sezione standard '{key}' non si elimina, solo si svuota."},
        )
    with tx() as t:
        cur = t.execute(
            "DELETE FROM identity_sections WHERE user_id = ? AND section_key = ?",
            (DEFAULT_USER_ID, key),
        )
        if cur.rowcount == 0:
            raise HTTPException(404, {"code": "section_not_found", "key": key})
    return {"deleted": True, "key": key}
