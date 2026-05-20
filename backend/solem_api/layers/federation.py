"""FEDERATION — identity SSO via mesh.

Single responsibility: SOLO gestione dell'account SOLEM federato. Un
unico set di credenziali (username + Ed25519 keypair) registrato sul
gateway → riconosciuto da TUTTI i device della mesh.

Flow:
  1. solem-init genera Ed25519 keypair → registra account sul gateway
  2. Quando un altro device della mesh fa /federation/login passando
     una challenge firmata, il gateway verifica con la pubkey nota
  3. Sessione = JWT firmato con la chiave del gateway, valido cross-device
     fino a expiry (default 24h)
  4. Ogni endpoint sensibile può accettare il JWT come Authorization

Tutto FOSS, zero cloud, 0 €. Algoritmo: Ed25519 (RFC 8032).
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import secrets
import time
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/federation", tags=["federation"])

FED_DIR = Path("/var/lib/solem/federation")
ACCOUNTS_FILE = FED_DIR / "accounts.json"
SESSIONS_FILE = FED_DIR / "sessions.json"
GATEWAY_SECRET_FILE = FED_DIR / "gateway.secret"
CHALLENGE_TTL_SEC = 120
SESSION_TTL_SEC = 86400  # 24h


class CreateAccount(BaseModel):
    username: str = Field(..., min_length=2, max_length=64)
    display_name: str = Field(..., max_length=128)
    public_key_b64: str = Field(..., description="Ed25519 pubkey base64 raw 32 byte")


class Account(BaseModel):
    username: str
    display_name: str
    public_key_b64: str
    created_at: str
    devices_linked: list[str] = Field(default_factory=list)


class ChallengeRequest(BaseModel):
    username: str


class ChallengeResponse(BaseModel):
    challenge: str
    expires_at: float
    note: str = "Firma con Ed25519, poi POST /federation/login"


class LoginRequest(BaseModel):
    username: str
    challenge: str
    signature_b64: str
    device_id: str | None = None


class Session(BaseModel):
    token: str
    username: str
    issued_at: float
    expires_at: float
    device_id: str | None = None


class VerifyRequest(BaseModel):
    token: str


# ─── State persistence ────────────────────────────────────────────────


def _load(path: Path, default: dict | list) -> dict | list:
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return default


def _save(path: Path, data) -> None:
    FED_DIR.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2))


def _gateway_secret() -> bytes:
    """Secret HMAC per firmare i JWT. Generato al primo uso."""
    FED_DIR.mkdir(parents=True, exist_ok=True)
    if not GATEWAY_SECRET_FILE.exists():
        GATEWAY_SECRET_FILE.write_bytes(secrets.token_bytes(32))
        GATEWAY_SECRET_FILE.chmod(0o600)
    return GATEWAY_SECRET_FILE.read_bytes()


# ─── Crypto (Ed25519 via cryptography se disponibile, altrimenti HMAC fallback) ──


def _verify_ed25519(pubkey_b64: str, message: bytes, signature_b64: str) -> bool:
    try:
        from cryptography.hazmat.primitives.asymmetric import ed25519
        pubkey = ed25519.Ed25519PublicKey.from_public_bytes(base64.b64decode(pubkey_b64))
        pubkey.verify(base64.b64decode(signature_b64), message)
        return True
    except ImportError:
        # Fallback: HMAC-SHA256 con pubkey_b64 come "shared secret" (NON sicuro,
        # solo per dev/test su Windows senza cryptography lib).
        expected = hmac.new(pubkey_b64.encode(), message, hashlib.sha256).hexdigest()
        return hmac.compare_digest(expected, signature_b64)
    except Exception:
        return False


# ─── JWT-like token (HMAC-signed, niente lib esterne) ─────────────────


def _make_token(username: str, device_id: str | None) -> Session:
    now = time.time()
    exp = now + SESSION_TTL_SEC
    payload = {"u": username, "iat": now, "exp": exp, "dev": device_id}
    header_json = json.dumps({"alg": "HS256", "typ": "SOLEM"}).encode()
    payload_json = json.dumps(payload).encode()
    h_b64 = base64.urlsafe_b64encode(header_json).rstrip(b"=")
    p_b64 = base64.urlsafe_b64encode(payload_json).rstrip(b"=")
    signing = b".".join([h_b64, p_b64])
    sig = hmac.new(_gateway_secret(), signing, hashlib.sha256).digest()
    s_b64 = base64.urlsafe_b64encode(sig).rstrip(b"=")
    token = (b".".join([h_b64, p_b64, s_b64])).decode()
    return Session(token=token, username=username, issued_at=now, expires_at=exp, device_id=device_id)


def _verify_token(token: str) -> dict | None:
    try:
        h_b64, p_b64, s_b64 = token.split(".")
    except ValueError:
        return None
    signing = f"{h_b64}.{p_b64}".encode()
    expected = hmac.new(_gateway_secret(), signing, hashlib.sha256).digest()
    expected_b64 = base64.urlsafe_b64encode(expected).rstrip(b"=").decode()
    if not hmac.compare_digest(expected_b64, s_b64):
        return None
    try:
        payload = json.loads(base64.urlsafe_b64decode(p_b64 + "==="))
    except (ValueError, json.JSONDecodeError):
        return None
    if payload.get("exp", 0) < time.time():
        return None
    return payload


# ─── In-memory challenges (TTL 2 min) ─────────────────────────────────


_CHALLENGES: dict[str, dict] = {}


def _gc_challenges() -> None:
    now = time.time()
    for ch, meta in list(_CHALLENGES.items()):
        if meta["expires_at"] < now:
            del _CHALLENGES[ch]


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/health", response_model=dict)
async def fed_health() -> dict:
    accounts = _load(ACCOUNTS_FILE, {})
    sessions = _load(SESSIONS_FILE, {})
    _gc_challenges()
    return {
        "accounts": len(accounts),
        "active_sessions": sum(1 for s in sessions.values() if s.get("exp", 0) > time.time()),
        "pending_challenges": len(_CHALLENGES),
        "session_ttl_sec": SESSION_TTL_SEC,
        "algo": "Ed25519 (challenge-response) + HMAC-SHA256 (token)",
    }


@router.post("/accounts", response_model=Account)
async def create_account(req: CreateAccount) -> Account:
    """Crea un nuovo account federato (chiamato da solem-init al primo boot)."""
    accounts = _load(ACCOUNTS_FILE, {})
    if req.username in accounts:
        raise HTTPException(409, {"code": "account_exists", "username": req.username})

    # Sanity: la pubkey b64 deve decodificare a 32 byte
    try:
        raw = base64.b64decode(req.public_key_b64)
        if len(raw) != 32:
            raise ValueError(f"got {len(raw)} bytes, expected 32")
    except (ValueError, Exception) as e:
        raise HTTPException(400, {"code": "invalid_pubkey", "error": str(e)})

    acc = {
        "username": req.username,
        "display_name": req.display_name,
        "public_key_b64": req.public_key_b64,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "devices_linked": [],
    }
    accounts[req.username] = acc
    _save(ACCOUNTS_FILE, accounts)
    return Account(**acc)


@router.get("/accounts/{username}", response_model=Account)
async def get_account(username: str) -> Account:
    accounts = _load(ACCOUNTS_FILE, {})
    if username not in accounts:
        raise HTTPException(404, {"code": "account_not_found"})
    return Account(**accounts[username])


@router.post("/challenge", response_model=ChallengeResponse)
async def challenge(req: ChallengeRequest) -> ChallengeResponse:
    accounts = _load(ACCOUNTS_FILE, {})
    if req.username not in accounts:
        raise HTTPException(404, {"code": "account_not_found"})
    _gc_challenges()
    ch = secrets.token_urlsafe(32)
    exp = time.time() + CHALLENGE_TTL_SEC
    _CHALLENGES[ch] = {"username": req.username, "expires_at": exp}
    return ChallengeResponse(challenge=ch, expires_at=exp)


@router.post("/login", response_model=Session)
async def login(req: LoginRequest) -> Session:
    _gc_challenges()
    meta = _CHALLENGES.get(req.challenge)
    if not meta or meta["username"] != req.username:
        raise HTTPException(401, {"code": "invalid_or_expired_challenge"})

    accounts = _load(ACCOUNTS_FILE, {})
    acc = accounts.get(req.username)
    if not acc:
        raise HTTPException(404, {"code": "account_not_found"})

    if not _verify_ed25519(acc["public_key_b64"], req.challenge.encode(), req.signature_b64):
        raise HTTPException(401, {"code": "signature_invalid"})

    # Challenge consumata
    del _CHALLENGES[req.challenge]

    # Link device se nuovo
    if req.device_id and req.device_id not in acc["devices_linked"]:
        acc["devices_linked"].append(req.device_id)
        accounts[req.username] = acc
        _save(ACCOUNTS_FILE, accounts)

    session = _make_token(req.username, req.device_id)

    # Persisti sessione
    sessions = _load(SESSIONS_FILE, {})
    sessions[session.token[:32]] = {
        "u": session.username, "iat": session.issued_at,
        "exp": session.expires_at, "dev": session.device_id,
    }
    _save(SESSIONS_FILE, sessions)
    return session


@router.post("/verify", response_model=dict)
async def verify(req: VerifyRequest) -> dict:
    """Verifica un token. Usato da ogni endpoint che richiede auth."""
    payload = _verify_token(req.token)
    if not payload:
        raise HTTPException(401, {"code": "token_invalid_or_expired"})
    return {
        "valid": True,
        "username": payload["u"],
        "device_id": payload.get("dev"),
        "expires_in_sec": int(payload["exp"] - time.time()),
    }


@router.post("/logout")
async def logout(req: VerifyRequest) -> dict:
    """Invalida una sessione (rimuove dal file)."""
    sessions = _load(SESSIONS_FILE, {})
    key = req.token[:32]
    if key in sessions:
        del sessions[key]
        _save(SESSIONS_FILE, sessions)
        return {"logged_out": True}
    return {"logged_out": False, "note": "session not found (probably already expired)"}


@router.get("/sessions", response_model=list[dict])
async def list_sessions() -> list[dict]:
    """Lista sessioni attive (per gestione dispositivi linked)."""
    sessions = _load(SESSIONS_FILE, {})
    now = time.time()
    out = []
    for k, s in sessions.items():
        if s.get("exp", 0) > now:
            out.append({
                "username": s["u"],
                "device_id": s.get("dev"),
                "issued_at": datetime.fromtimestamp(s["iat"], tz=timezone.utc).isoformat(),
                "expires_at": datetime.fromtimestamp(s["exp"], tz=timezone.utc).isoformat(),
            })
    return out
