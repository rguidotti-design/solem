"""AUTH KEYS — gestione chiavi JWT signing + audit log ed25519.

Single responsibility: SOLO gestione chiavi crittografiche.

Chiavi generate al primo boot in /var/lib/solem-secrets/:
  - jwt-signing.key    (ed25519 per firmare JWT sessione)
  - jwt-signing.pub    (verifica)
  - audit-signing.key  (ed25519 per firmare ogni evento audit)
  - audit-signing.pub  (verifica + esportabile per check esterno)

NB: oggi questo modulo è scaffolding. La firma ed25519 effettiva sui token
sessione (oggi token random opaqui) e su event audit (oggi unsigned) arriva
quando il modulo viene attivato da configuration.nix.

Vedi anche:
  - ADR-006 Constitutional triple-defense (Layer 1 audit firmato)
  - Prompt Master v4.0 sez. 4.11 (audit immutabile firmato)
"""
from __future__ import annotations

import base64
import hashlib
import os
import secrets
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter(prefix="/auth-keys", tags=["security"])

KEY_DIR = Path(os.environ.get("SOLEM_SECRETS_DIR", "/var/lib/solem-secrets"))
JWT_KEY = KEY_DIR / "jwt-signing.key"
JWT_PUB = KEY_DIR / "jwt-signing.pub"
AUDIT_KEY = KEY_DIR / "audit-signing.key"
AUDIT_PUB = KEY_DIR / "audit-signing.pub"


# ─── Generazione chiavi ed25519 ───────────────────────────────────────


def _ensure_keys() -> dict[str, str]:
    """Genera chiavi se mancanti. Usa cryptography se disponibile, altrimenti
    placeholder text (per Step 0 senza dep cryptography)."""
    try:
        KEY_DIR.mkdir(parents=True, exist_ok=True)
        os.chmod(KEY_DIR, 0o700)
    except OSError:
        return {"error": f"cannot create {KEY_DIR}"}

    if not JWT_KEY.exists():
        _generate_key_pair(JWT_KEY, JWT_PUB)
    if not AUDIT_KEY.exists():
        _generate_key_pair(AUDIT_KEY, AUDIT_PUB)

    return {
        "jwt_signing_key": str(JWT_KEY),
        "jwt_signing_pub": str(JWT_PUB),
        "audit_signing_key": str(AUDIT_KEY),
        "audit_signing_pub": str(AUDIT_PUB),
    }


def _generate_key_pair(priv_path: Path, pub_path: Path) -> None:
    """Genera coppia ed25519. Prova cryptography, fallback random 32-byte."""
    try:
        from cryptography.hazmat.primitives.asymmetric import ed25519
        from cryptography.hazmat.primitives import serialization

        priv = ed25519.Ed25519PrivateKey.generate()
        priv_bytes = priv.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        )
        pub_bytes = priv.public_key().public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        )
        priv_path.write_bytes(priv_bytes)
        pub_path.write_bytes(pub_bytes)
    except ImportError:
        # Fallback senza cryptography: random 32-byte (placeholder Step 0)
        priv_bytes = secrets.token_bytes(32)
        pub_bytes = hashlib.sha256(priv_bytes).digest()
        priv_path.write_bytes(b"# Placeholder Step 0 (cryptography non installato)\n" + base64.b64encode(priv_bytes))
        pub_path.write_bytes(b"# Placeholder Step 0\n" + base64.b64encode(pub_bytes))

    os.chmod(priv_path, 0o600)
    os.chmod(pub_path, 0o644)


def sign_audit_event(payload: dict) -> dict:
    """Firma un evento audit con la chiave ed25519. Aggiunge campo `signature`."""
    _ensure_keys()
    import json as _json
    canonical = _json.dumps(payload, sort_keys=True, ensure_ascii=False).encode("utf-8")
    try:
        from cryptography.hazmat.primitives.asymmetric import ed25519
        from cryptography.hazmat.primitives import serialization
        priv = serialization.load_pem_private_key(AUDIT_KEY.read_bytes(), password=None)
        if not isinstance(priv, ed25519.Ed25519PrivateKey):
            raise TypeError("expected ed25519")
        sig = priv.sign(canonical)
        return {**payload, "signature": base64.b64encode(sig).decode(), "sig_algo": "ed25519"}
    except (ImportError, Exception):
        # Fallback: HMAC-SHA256 con secret derivato
        secret = AUDIT_KEY.read_bytes() if AUDIT_KEY.exists() else b""
        import hmac
        sig = hmac.new(secret, canonical, hashlib.sha256).hexdigest()
        return {**payload, "signature": sig, "sig_algo": "hmac-sha256-fallback"}


def verify_audit_signature(event: dict) -> bool:
    """Verifica firma di un evento audit. True se valida."""
    if "signature" not in event:
        return False
    sig_algo = event.get("sig_algo", "")
    payload = {k: v for k, v in event.items() if k not in ("signature", "sig_algo")}
    import json as _json
    canonical = _json.dumps(payload, sort_keys=True, ensure_ascii=False).encode("utf-8")

    if sig_algo == "ed25519":
        try:
            from cryptography.hazmat.primitives.asymmetric import ed25519
            from cryptography.hazmat.primitives import serialization
            pub = serialization.load_pem_public_key(AUDIT_PUB.read_bytes())
            if not isinstance(pub, ed25519.Ed25519PublicKey):
                return False
            sig = base64.b64decode(event["signature"])
            pub.verify(sig, canonical)
            return True
        except Exception:
            return False

    if sig_algo == "hmac-sha256-fallback":
        secret = AUDIT_KEY.read_bytes() if AUDIT_KEY.exists() else b""
        import hmac
        expected = hmac.new(secret, canonical, hashlib.sha256).hexdigest()
        return hmac.compare_digest(event["signature"], expected)

    return False


# ─── Endpoint ──────────────────────────────────────────────────────────


class KeyInfo(BaseModel):
    name: str
    path: str
    exists: bool
    algorithm: str = "ed25519"
    public_key_pem: str | None = None


@router.get("/info", response_model=list[KeyInfo])
async def keys_info() -> list[KeyInfo]:
    _ensure_keys()
    out = []
    for name, priv, pub in [
        ("jwt", JWT_KEY, JWT_PUB),
        ("audit", AUDIT_KEY, AUDIT_PUB),
    ]:
        pub_pem = None
        if pub.exists():
            try:
                pub_pem = pub.read_text(errors="ignore")[:500]
            except OSError:
                pass
        out.append(KeyInfo(
            name=name, path=str(priv), exists=priv.exists(), public_key_pem=pub_pem,
        ))
    return out


class VerifyRequest(BaseModel):
    event: dict[str, Any]


@router.post("/verify-audit")
async def verify(req: VerifyRequest) -> dict:
    return {"valid": verify_audit_signature(req.event)}
