"""SECRETS — gestione chiavi cifrate a riposo + rotazione.

Single responsibility: SOLO storage/recupero secret cifrati. Niente
distribuzione (è sops-nix che lo fa via Nix). Niente HTTP exposure dei
plaintext (gli endpoint ritornano solo metadata: chi, quando, hash).

Backend cifratura:
  - cryptography Fernet (AES-128-CBC + HMAC-SHA256) se installato
  - fallback XOR + checksum (NON sicuro, solo per Windows dev)

Master key:
  - Letta da /var/lib/solem-secrets/master.key (32 byte, mode 0600 root)
  - Generata al primo uso se mancante
  - Backup raccomandato OFFLINE (printout o usb encrypted)

Endpoint:
  GET  /secrets               — lista nomi (NON plaintext) + metadata
  POST /secrets/{name}        — set/update (plaintext → cifrato a riposo)
  GET  /secrets/{name}        — get (plaintext, richiede auth federation)
  DELETE /secrets/{name}      — rimuovi
  POST /secrets/rotate        — rotazione master key (re-cifra tutto)
"""
from __future__ import annotations

import base64
import hashlib
import json
import os
import secrets as py_secrets
import time
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/secrets", tags=["secrets"])

SECRETS_DIR = Path(os.environ.get("SOLEM_SECRETS_DIR", "/var/lib/solem-secrets"))
MASTER_KEY_FILE = SECRETS_DIR / "master.key"
SECRETS_FILE = SECRETS_DIR / "store.json"


class SecretSet(BaseModel):
    value: str = Field(..., min_length=1, description="plaintext da cifrare")
    description: str = Field("", max_length=200)


class SecretMeta(BaseModel):
    name: str
    description: str
    created_at: str
    updated_at: str
    sha256_first8: str = Field(..., description="prefisso hash plaintext per audit (non reversibile)")


# ─── Crypto backend ───────────────────────────────────────────────────


def _ensure_master_key() -> bytes:
    SECRETS_DIR.mkdir(parents=True, exist_ok=True)
    if not MASTER_KEY_FILE.exists():
        # Genera 32 byte random
        MASTER_KEY_FILE.write_bytes(py_secrets.token_bytes(32))
        try:
            MASTER_KEY_FILE.chmod(0o600)
        except OSError:
            pass  # Windows: ignora
    return MASTER_KEY_FILE.read_bytes()


def _fernet():
    try:
        from cryptography.fernet import Fernet
        key = _ensure_master_key()
        # Fernet vuole 32 byte url-safe-b64
        fkey = base64.urlsafe_b64encode(key[:32])
        return Fernet(fkey)
    except ImportError:
        return None


def _encrypt(plaintext: str) -> str:
    fern = _fernet()
    if fern:
        return fern.encrypt(plaintext.encode()).decode()
    # Fallback XOR (solo dev/Windows — NON usare in prod)
    key = _ensure_master_key()
    data = plaintext.encode()
    out = bytes((b ^ key[i % len(key)]) for i, b in enumerate(data))
    return "xor:" + base64.b64encode(out).decode()


def _decrypt(ciphertext: str) -> str:
    if ciphertext.startswith("xor:"):
        key = _ensure_master_key()
        data = base64.b64decode(ciphertext[4:])
        out = bytes((b ^ key[i % len(key)]) for i, b in enumerate(data))
        return out.decode()
    fern = _fernet()
    if not fern:
        raise HTTPException(503, {"code": "fernet_unavailable", "hint": "install cryptography lib"})
    try:
        return fern.decrypt(ciphertext.encode()).decode()
    except Exception as e:
        raise HTTPException(500, {"code": "decryption_failed", "error": str(e)})


# ─── Storage ──────────────────────────────────────────────────────────


def _load() -> dict:
    if not SECRETS_FILE.exists():
        return {}
    try:
        return json.loads(SECRETS_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        return {}


def _save(data: dict) -> None:
    SECRETS_DIR.mkdir(parents=True, exist_ok=True)
    SECRETS_FILE.write_text(json.dumps(data, indent=2))
    try:
        SECRETS_FILE.chmod(0o600)
    except OSError:
        pass


# ─── Auth helper ──────────────────────────────────────────────────────


def _require_token(authorization: str | None):
    """Verifica JWT-like di /solem/federation/login. Importa inline per
    evitare circular import."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, {"code": "missing_bearer_token"})
    token = authorization[7:]
    from solem_api.layers.federation import _verify_token
    payload = _verify_token(token)
    if not payload:
        raise HTTPException(401, {"code": "token_invalid_or_expired"})
    return payload


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/health", response_model=dict)
async def secrets_health() -> dict:
    fern = _fernet()
    return {
        "secrets_dir": str(SECRETS_DIR),
        "fernet_available": fern is not None,
        "master_key_exists": MASTER_KEY_FILE.exists(),
        "total_secrets": len(_load()),
        "warning": None if fern else "cryptography lib non installata: usato XOR fallback (NON sicuro per produzione)",
    }


@router.get("", response_model=list[SecretMeta])
async def list_secrets() -> list[SecretMeta]:
    """Lista metadata (NON plaintext)."""
    data = _load()
    return [
        SecretMeta(
            name=name,
            description=meta.get("description", ""),
            created_at=meta.get("created_at", ""),
            updated_at=meta.get("updated_at", ""),
            sha256_first8=meta.get("sha256_first8", ""),
        )
        for name, meta in data.items()
    ]


@router.post("/{name}", response_model=SecretMeta)
async def set_secret(name: str, req: SecretSet,
                     authorization: str | None = Header(None)) -> SecretMeta:
    _require_token(authorization)
    if not name.replace("_", "").replace("-", "").isalnum():
        raise HTTPException(400, {"code": "invalid_name", "hint": "[A-Za-z0-9_-]+"})

    data = _load()
    now = datetime.now(timezone.utc).isoformat()
    sha = hashlib.sha256(req.value.encode()).hexdigest()[:8]
    data[name] = {
        "ciphertext": _encrypt(req.value),
        "description": req.description,
        "created_at": data.get(name, {}).get("created_at", now),
        "updated_at": now,
        "sha256_first8": sha,
    }
    _save(data)
    return SecretMeta(
        name=name,
        description=req.description,
        created_at=data[name]["created_at"],
        updated_at=now,
        sha256_first8=sha,
    )


@router.get("/{name}/value", response_model=dict)
async def get_secret_value(name: str,
                           authorization: str | None = Header(None)) -> dict:
    payload = _require_token(authorization)
    data = _load()
    if name not in data:
        raise HTTPException(404, {"code": "secret_not_found"})
    return {
        "name": name,
        "value": _decrypt(data[name]["ciphertext"]),
        "accessed_by": payload["u"],
        "accessed_at": datetime.now(timezone.utc).isoformat(),
    }


@router.delete("/{name}")
async def delete_secret(name: str,
                        authorization: str | None = Header(None)) -> dict:
    _require_token(authorization)
    data = _load()
    if name not in data:
        raise HTTPException(404, {"code": "secret_not_found"})
    del data[name]
    _save(data)
    return {"deleted": True, "name": name}


@router.post("/rotate", response_model=dict)
async def rotate_master_key(authorization: str | None = Header(None)) -> dict:
    """Rotazione: decripta tutto con vecchia chiave, genera nuova, ricifra.

    PERICOLO: se interrotto a metà, alcuni secret saranno con vecchia
    chiave. Backup raccomandato prima.
    """
    _require_token(authorization)
    data = _load()

    # 1. Decripta TUTTO con la chiave corrente
    plaintexts: dict[str, str] = {}
    for name, meta in data.items():
        plaintexts[name] = _decrypt(meta["ciphertext"])

    # 2. Backup vecchia master key
    if MASTER_KEY_FILE.exists():
        backup = MASTER_KEY_FILE.with_suffix(f".bak.{int(time.time())}")
        MASTER_KEY_FILE.rename(backup)

    # 3. Genera nuova master key
    MASTER_KEY_FILE.write_bytes(py_secrets.token_bytes(32))
    try:
        MASTER_KEY_FILE.chmod(0o600)
    except OSError:
        pass

    # 4. Re-cifra tutto
    now = datetime.now(timezone.utc).isoformat()
    for name, plain in plaintexts.items():
        data[name]["ciphertext"] = _encrypt(plain)
        data[name]["rotated_at"] = now
    _save(data)

    return {
        "rotated": True,
        "secrets_rotated": len(plaintexts),
        "backup_old_key": str(MASTER_KEY_FILE.with_suffix(f".bak.*")),
        "warning": "BACKUP la nuova master key offline!",
    }
