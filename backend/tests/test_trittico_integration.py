"""Integration test: federation → cluster → handoff end-to-end.

Scenario:
  1. Ruben crea il suo account SOLEM (federation).
  2. Beelink (laptop) si registra al cluster.
  3. iPhone PWA si registra come worker.
  4. Beelink pubblica handoff "leggi PDF a pagina 17" targeting iPhone.
  5. iPhone reclama l'handoff.
  6. Cluster dispatcha task LLM-inference → device migliore.
"""
import hashlib
import hmac

import pytest


@pytest.fixture(autouse=True)
def isolated_state(monkeypatch, tmp_path):
    monkeypatch.setattr("solem_api.layers.cluster.REGISTRY_FILE", tmp_path / "cluster.json")
    monkeypatch.setattr("solem_api.layers.federation.FED_DIR", tmp_path)
    monkeypatch.setattr("solem_api.layers.federation.ACCOUNTS_FILE", tmp_path / "accounts.json")
    monkeypatch.setattr("solem_api.layers.federation.SESSIONS_FILE", tmp_path / "sessions.json")
    monkeypatch.setattr("solem_api.layers.federation.GATEWAY_SECRET_FILE", tmp_path / "gateway.secret")
    monkeypatch.setattr("solem_api.layers.handoff.HANDOFF_FILE", tmp_path / "handoff.json")
    from solem_api.layers import federation
    federation._CHALLENGES.clear()


def test_full_trittico_flow(client):
    pub = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBA="  # 32 byte b64

    # ─── 1. Account SOLEM ───
    r = client.post("/solem/federation/accounts", json={
        "username": "ruben", "display_name": "Ruben Guidotti", "public_key_b64": pub,
    })
    assert r.status_code == 200

    # ─── 2. Beelink (laptop) registra nel cluster ───
    r = client.post("/solem/cluster/register", json={
        "device_id": "beelink",
        "name": "Beelink (gateway+worker)",
        "endpoint": "http://beelink.solem.local:8001",
        "capabilities": {
            "cpu_cores": 8, "cpu_model": "AMD Ryzen 7", "ram_gb": 32,
            "disk_free_gb": 500,
            "gpu": {"kind": "integrated", "model": "Vega", "vram_gb": 0},
            "arch": "x86_64", "os": "linux",
        },
        "roles": ["gateway", "worker"],
    })
    assert r.status_code == 200

    # ─── 3. iPhone PWA si registra come worker leggero ───
    r = client.post("/solem/cluster/register", json={
        "device_id": "iphone-ruben",
        "name": "iPhone Ruben",
        "endpoint": "pwa://iphone-ruben",
        "capabilities": {
            "cpu_cores": 6, "cpu_model": "Apple A17", "ram_gb": 8,
            "disk_free_gb": 60,
            "gpu": {"kind": "integrated", "model": "Apple GPU", "vram_gb": 0},
            "arch": "arm64", "os": "ios",
        },
        "roles": ["worker"],
    })
    assert r.status_code == 200

    # ─── 4. Cluster topology riflette 2 device ───
    topo = client.get("/solem/cluster/topology").json()
    assert topo["online_devices"] == 2
    assert topo["total_cpu_cores"] == 14
    assert topo["total_ram_gb"] == 40.0

    # ─── 5. Beelink pubblica handoff per iPhone ───
    push = client.post("/solem/handoff/push", json={
        "kind": "open_url",
        "payload": {"url": "file:///home/ruben/Documents/report.pdf", "scroll": 0.43},
        "owner_username": "ruben",
        "source_device_id": "beelink",
        "target_device_id": "iphone-ruben",
        "title": "Continua report.pdf",
        "description": "Pagina 17 · 43% scroll",
    })
    assert push.status_code == 200
    handoff_id = push.json()["id"]

    # ─── 6. iPhone vede l'handoff ───
    pending = client.get("/solem/handoff/pending?device_id=iphone-ruben&owner_username=ruben")
    assert pending.status_code == 200
    items = pending.json()
    assert len(items) == 1
    assert items[0]["title"] == "Continua report.pdf"

    # ─── 7. iPhone reclama l'handoff ───
    claim = client.post(f"/solem/handoff/claim/{handoff_id}?device_id=iphone-ruben")
    assert claim.status_code == 200
    assert claim.json()["claimed_by"] == "iphone-ruben"

    # ─── 8. Beelink fa dispatch task LLM → cluster sceglie chi ─
    disp = client.post("/solem/cluster/dispatch", json={
        "task_kind": "embedding",
        "size_hint": "small",
        "requires_gpu": False,
    })
    assert disp.status_code == 200
    # Beelink ha più RAM (32 vs 8) → vince
    assert disp.json()["device_id"] == "beelink"

    # ─── 9. Account ora ha 0 device linked (login non fatto in questo test) ──
    acc = client.get("/solem/federation/accounts/ruben").json()
    assert acc["devices_linked"] == []
