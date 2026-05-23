"""Test secrets store + audit_chain integrity."""
import pytest


@pytest.fixture(autouse=True)
def isolated_secrets(monkeypatch, tmp_path):
    monkeypatch.setattr("solem_api.layers.secrets.SECRETS_DIR", tmp_path / "secrets")
    monkeypatch.setattr("solem_api.layers.secrets.SECRETS_FILE", tmp_path / "secrets/store.json")
    monkeypatch.setattr("solem_api.layers.secrets.MASTER_KEY_FILE", tmp_path / "secrets/master.key")
    monkeypatch.setattr("solem_api.layers.audit_chain.LOG_FILE",
                        tmp_path / "audit.jsonl")


def test_secrets_health(client):
    r = client.get("/solem/secrets/health")
    assert r.status_code == 200
    data = r.json()
    assert "fernet_available" in data
    assert "master_key_exists" in data


def test_secrets_list_empty_without_auth(client):
    r = client.get("/solem/secrets")
    assert r.status_code == 200
    assert r.json() == []


def test_secrets_set_requires_auth(client):
    """Senza Bearer token, POST deve fallire 401."""
    r = client.post("/solem/secrets/api_key", json={
        "value": "secret123", "description": "test",
    })
    assert r.status_code == 401


def test_audit_health(client):
    r = client.get("/solem/audit/health")
    assert r.status_code == 200
    data = r.json()
    assert data["tamper_evident"] is True


def test_audit_log_event(client):
    r = client.post("/solem/audit/log", json={
        "actor": "test", "action": "login.test",
        "target": "test-target", "severity": "info",
    })
    assert r.status_code == 200
    rec = r.json()
    assert rec["seq"] == 1
    assert rec["actor"] == "test"
    assert rec["prev_hash"] == "0" * 64


def test_audit_chain_integrity(client):
    """Append 3 record + verify chain."""
    client.post("/solem/audit/log", json={"actor": "a", "action": "act1"})
    client.post("/solem/audit/log", json={"actor": "a", "action": "act2"})
    client.post("/solem/audit/log", json={"actor": "b", "action": "act3"})

    r = client.get("/solem/audit/verify")
    assert r.status_code == 200
    data = r.json()
    assert data["valid"] is True
    assert data["records"] == 3
    assert data["total_anomalies"] == 0


def test_audit_by_actor(client):
    client.post("/solem/audit/log", json={"actor": "alice", "action": "act1"})
    client.post("/solem/audit/log", json={"actor": "bob", "action": "act2"})
    client.post("/solem/audit/log", json={"actor": "alice", "action": "act3"})

    alice_events = client.get("/solem/audit/by-actor/alice").json()
    assert len(alice_events) == 2
    assert all(e["actor"] == "alice" for e in alice_events)


def test_audit_recent_limit(client):
    for i in range(5):
        client.post("/solem/audit/log", json={"actor": "x", "action": f"a{i}"})

    recent = client.get("/solem/audit/recent?limit=3").json()
    assert len(recent) == 3
    # Più recenti per ultimi
    assert recent[-1]["action"] == "a4"
