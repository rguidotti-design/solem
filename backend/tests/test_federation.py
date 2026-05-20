"""Test federation: create account → challenge → login (HMAC fallback)."""
import hashlib
import hmac

import pytest


@pytest.fixture(autouse=True)
def isolated_fed_state(monkeypatch, tmp_path):
    monkeypatch.setattr("solem_api.layers.federation.FED_DIR", tmp_path)
    monkeypatch.setattr("solem_api.layers.federation.ACCOUNTS_FILE", tmp_path / "accounts.json")
    monkeypatch.setattr("solem_api.layers.federation.SESSIONS_FILE", tmp_path / "sessions.json")
    monkeypatch.setattr("solem_api.layers.federation.GATEWAY_SECRET_FILE", tmp_path / "gateway.secret")
    # Reset challenge in-memory
    from solem_api.layers import federation
    federation._CHALLENGES.clear()
    yield


# In assenza di cryptography, federation usa HMAC-SHA256(pubkey_b64, message)
# come fallback. I test usano questo comportamento per essere portabili Windows.
def _sign_hmac(pubkey_b64: str, message: bytes) -> str:
    return hmac.new(pubkey_b64.encode(), message, hashlib.sha256).hexdigest()


def test_create_account_minimal(client):
    # 32 byte base64-encoded
    pub = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
    r = client.post("/solem/federation/accounts", json={
        "username": "ruben",
        "display_name": "Ruben Guidotti",
        "public_key_b64": pub,
    })
    assert r.status_code == 200
    assert r.json()["username"] == "ruben"


def test_create_account_invalid_pubkey(client):
    r = client.post("/solem/federation/accounts", json={
        "username": "x", "display_name": "x",
        "public_key_b64": "not-base64-32-bytes",
    })
    assert r.status_code == 400


def test_duplicate_account_409(client):
    pub = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
    client.post("/solem/federation/accounts", json={
        "username": "ruben", "display_name": "r", "public_key_b64": pub,
    })
    r = client.post("/solem/federation/accounts", json={
        "username": "ruben", "display_name": "r", "public_key_b64": pub,
    })
    assert r.status_code == 409


def test_challenge_unknown_user_404(client):
    r = client.post("/solem/federation/challenge", json={"username": "ghost"})
    assert r.status_code == 404


def test_full_login_flow_with_hmac_fallback(client):
    pub = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
    client.post("/solem/federation/accounts", json={
        "username": "ruben", "display_name": "r", "public_key_b64": pub,
    })

    ch_r = client.post("/solem/federation/challenge", json={"username": "ruben"})
    assert ch_r.status_code == 200
    challenge = ch_r.json()["challenge"]

    # Skippa se la lib cryptography è disponibile (signature non sarà HMAC)
    try:
        from cryptography.hazmat.primitives.asymmetric import ed25519  # noqa: F401
        pytest.skip("cryptography lib present: ed25519 path attivo, HMAC fallback non testabile qui")
    except ImportError:
        pass

    sig = _sign_hmac(pub, challenge.encode())

    r = client.post("/solem/federation/login", json={
        "username": "ruben",
        "challenge": challenge,
        "signature_b64": sig,
        "device_id": "laptop-1",
    })
    assert r.status_code == 200
    token = r.json()["token"]
    assert token.count(".") == 2

    # Verify
    v = client.post("/solem/federation/verify", json={"token": token})
    assert v.status_code == 200
    assert v.json()["valid"] is True
    assert v.json()["username"] == "ruben"


def test_invalid_token_401(client):
    r = client.post("/solem/federation/verify", json={"token": "garbage.token.here"})
    assert r.status_code == 401
