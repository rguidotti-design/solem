"""USERS + AUTH — gestione utenti multi-tenant

Step 0: 1 utente owner hardcoded (Ruben). API esposta per non rompere quando
Step 4 si attiva multi-tenant pubblico. Auth endpoints presenti ma semplificati.

Step 4+: registrazione pubblica, OAuth providers, JWT firmato, RBAC granulare.

Endpoint:
  GET  /users/me                — utente corrente (Step 0: sempre owner)
  GET  /users                   — lista utenti (richiede role owner)
  POST /users                   — crea nuovo utente (owner only)
  POST /auth/login              — login con username + password
  POST /auth/logout             — revoca token sessione
  GET  /auth/sessions           — sessioni attive dell'utente corrente
"""
from __future__ import annotations

import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from typing import Literal

from fastapi import APIRouter, Depends, Header, HTTPException, Request, status
from pydantic import BaseModel, Field

from .db import get_conn, tx

router = APIRouter(prefix="", tags=["users"])  # niente prefix — sub-route esplicite

DEFAULT_OWNER_ID = "00000000-0000-0000-0000-000000000001"
SESSION_TTL = timedelta(days=7)


# ─── Schemas ──────────────────────────────────────────────────────────


class User(BaseModel):
    user_id: str
    username: str
    email: str
    role: Literal["owner", "user", "readonly"]
    created_at: str
    last_login: str | None = None
    is_active: bool


class UserCreate(BaseModel):
    username: str = Field(..., min_length=3, max_length=32)
    email: str
    password: str = Field(..., min_length=8)
    role: Literal["user", "readonly"] = "user"


class LoginRequest(BaseModel):
    username: str
    password: str


class LoginResponse(BaseModel):
    token: str
    expires_at: str
    user: User


class Session(BaseModel):
    token_preview: str = Field(..., description="primi 8 char del token (no full token)")
    created_at: str
    expires_at: str
    last_used: str | None = None
    ip: str | None = None
    user_agent: str | None = None


# ─── Bootstrap owner ──────────────────────────────────────────────────


def _ensure_default_owner() -> None:
    """Crea l'utente owner di default al primo accesso, se non esiste."""
    c = get_conn()
    row = c.execute("SELECT user_id FROM users WHERE user_id = ?", (DEFAULT_OWNER_ID,)).fetchone()
    if row is None:
        with tx() as t:
            t.execute(
                """INSERT INTO users (user_id, username, email, password_hash, role)
                   VALUES (?, ?, ?, ?, 'owner')""",
                (
                    DEFAULT_OWNER_ID,
                    "ruben",
                    "guidottrbn@gmail.com",
                    _hash_password("solem"),  # password iniziale, cambiare via /auth/change-password
                ),
            )


# ─── Helpers ──────────────────────────────────────────────────────────


def _hash_password(password: str) -> str:
    """Hash semplice sha-256+salt per Step 0. Step 2+: argon2id via passlib."""
    salt = secrets.token_hex(16)
    h = hashlib.sha256((salt + password).encode("utf-8")).hexdigest()
    return f"sha256${salt}${h}"


def _verify_password(password: str, hashed: str) -> bool:
    try:
        algo, salt, h = hashed.split("$", 2)
    except ValueError:
        return False
    if algo != "sha256":
        return False
    expected = hashlib.sha256((salt + password).encode("utf-8")).hexdigest()
    return secrets.compare_digest(h, expected)


def _row_to_user(r) -> User:
    return User(
        user_id=r["user_id"],
        username=r["username"],
        email=r["email"],
        role=r["role"],
        created_at=r["created_at"],
        last_login=r["last_login"],
        is_active=bool(r["is_active"]),
    )


# ─── Dependency: current user from session token ─────────────────────


async def get_current_user(authorization: str | None = Header(None)) -> User:
    """Step 0: se manca Authorization header → ritorna owner hardcoded.
    Step 2+: token obbligatorio + verifica scadenza + revoca."""
    _ensure_default_owner()
    c = get_conn()

    if not authorization or not authorization.startswith("Bearer "):
        # Step 0 fallback: ritorna owner di default (compatibilità single-user)
        row = c.execute("SELECT * FROM users WHERE user_id = ?", (DEFAULT_OWNER_ID,)).fetchone()
        return _row_to_user(row)

    token = authorization.removeprefix("Bearer ").strip()
    s = c.execute(
        """SELECT s.*, u.user_id AS uid FROM sessions s
           JOIN users u ON u.user_id = s.user_id
           WHERE s.token = ? AND s.revoked_at IS NULL
                 AND datetime(s.expires_at) > datetime('now')""",
        (token,),
    ).fetchone()
    if s is None:
        raise HTTPException(401, {"code": "invalid_token", "message": "Token sessione non valido o scaduto"})

    # Aggiorna last_used
    with tx() as t:
        t.execute("UPDATE sessions SET last_used = datetime('now') WHERE token = ?", (token,))

    row = c.execute("SELECT * FROM users WHERE user_id = ?", (s["uid"],)).fetchone()
    return _row_to_user(row)


# ─── Endpoints ────────────────────────────────────────────────────────


@router.get("/users/me", response_model=User)
async def me(user: User = Depends(get_current_user)) -> User:
    return user


@router.get("/users", response_model=list[User])
async def list_users(user: User = Depends(get_current_user)) -> list[User]:
    if user.role != "owner":
        raise HTTPException(403, {"code": "forbidden", "message": "Solo owner può listare utenti"})
    rows = get_conn().execute("SELECT * FROM users ORDER BY created_at").fetchall()
    return [_row_to_user(r) for r in rows]


@router.post("/users", response_model=User, status_code=201)
async def create_user(payload: UserCreate, requester: User = Depends(get_current_user)) -> User:
    if requester.role != "owner":
        raise HTTPException(403, {"code": "forbidden", "message": "Solo owner può creare utenti"})
    new_id = secrets.token_hex(16)
    new_id = f"{new_id[:8]}-{new_id[8:12]}-{new_id[12:16]}-{new_id[16:20]}-{new_id[20:32]}"
    with tx() as t:
        try:
            t.execute(
                """INSERT INTO users (user_id, username, email, password_hash, role)
                   VALUES (?, ?, ?, ?, ?)""",
                (new_id, payload.username, payload.email, _hash_password(payload.password), payload.role),
            )
        except Exception as e:
            raise HTTPException(409, {"code": "user_exists", "message": str(e)})
    row = get_conn().execute("SELECT * FROM users WHERE user_id = ?", (new_id,)).fetchone()
    return _row_to_user(row)


@router.post("/auth/login", response_model=LoginResponse)
async def login(req: LoginRequest, request: Request) -> LoginResponse:
    _ensure_default_owner()
    c = get_conn()
    row = c.execute("SELECT * FROM users WHERE username = ? AND is_active = 1", (req.username,)).fetchone()
    if row is None or not row["password_hash"] or not _verify_password(req.password, row["password_hash"]):
        raise HTTPException(401, {"code": "invalid_credentials", "message": "Username o password errati"})

    token = secrets.token_urlsafe(32)
    expires_at = (datetime.now(timezone.utc) + SESSION_TTL).isoformat()
    with tx() as t:
        t.execute(
            """INSERT INTO sessions (token, user_id, expires_at, ip, user_agent)
               VALUES (?, ?, ?, ?, ?)""",
            (
                token,
                row["user_id"],
                expires_at,
                request.client.host if request.client else None,
                request.headers.get("user-agent"),
            ),
        )
        t.execute("UPDATE users SET last_login = datetime('now') WHERE user_id = ?", (row["user_id"],))

    return LoginResponse(token=token, expires_at=expires_at, user=_row_to_user(row))


@router.post("/auth/logout")
async def logout(authorization: str = Header(...)) -> dict:
    if not authorization.startswith("Bearer "):
        raise HTTPException(400, {"code": "missing_token"})
    token = authorization.removeprefix("Bearer ").strip()
    with tx() as t:
        t.execute("UPDATE sessions SET revoked_at = datetime('now') WHERE token = ?", (token,))
    return {"logged_out": True}


@router.get("/auth/sessions", response_model=list[Session])
async def list_sessions(user: User = Depends(get_current_user)) -> list[Session]:
    rows = get_conn().execute(
        """SELECT token, created_at, expires_at, last_used, ip, user_agent
           FROM sessions WHERE user_id = ? AND revoked_at IS NULL
                 AND datetime(expires_at) > datetime('now')
           ORDER BY created_at DESC""",
        (user.user_id,),
    ).fetchall()
    return [
        Session(
            token_preview=r["token"][:8] + "…",
            created_at=r["created_at"],
            expires_at=r["expires_at"],
            last_used=r["last_used"],
            ip=r["ip"],
            user_agent=r["user_agent"],
        )
        for r in rows
    ]
