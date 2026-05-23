"""Test memory_federation: add/get/diff/sync + vector clock + tombstone."""
import pytest


@pytest.fixture(autouse=True)
def isolated_memory(monkeypatch, tmp_path):
    monkeypatch.setattr("solem_api.layers.memory_federation.DB_PATH", tmp_path / "memory.db")
    monkeypatch.setattr("solem_api.layers.memory_federation.DEVICE_ID", "test-device")


def test_health(client):
    r = client.get("/solem/memory/health")
    assert r.status_code == 200
    data = r.json()
    assert data["device_id"] == "test-device"
    assert data["live_memories"] == 0


def test_add_memory(client):
    r = client.post("/solem/memory", json={
        "kind": "user", "text": "Ruben preferisce italiano",
    })
    assert r.status_code == 200
    data = r.json()
    assert data["device_origin"] == "test-device"
    assert data["vector_clock"] == {"test-device": 1}
    assert data["tombstoned"] is False


def test_list_filter_by_kind(client):
    client.post("/solem/memory", json={"kind": "user", "text": "fatto1"})
    client.post("/solem/memory", json={"kind": "project", "text": "fatto2"})
    client.post("/solem/memory", json={"kind": "user", "text": "fatto3"})

    all_mem = client.get("/solem/memory/all").json()
    assert len(all_mem) == 3

    user_only = client.get("/solem/memory/all?kind=user").json()
    assert len(user_only) == 2
    assert all(m["kind"] == "user" for m in user_only)


def test_update_memory(client):
    created = client.post("/solem/memory", json={"kind": "user", "text": "v1"}).json()
    mid = created["id"]

    updated = client.put(f"/solem/memory/{mid}", json={
        "id": mid, "kind": "user", "text": "v2",
    }).json()
    assert updated["text"] == "v2"
    # vector clock bumped
    assert updated["vector_clock"]["test-device"] == 2


def test_tombstone_via_delete(client):
    created = client.post("/solem/memory", json={"kind": "user", "text": "to-kill"}).json()
    mid = created["id"]

    r = client.delete(f"/solem/memory/{mid}")
    assert r.status_code == 200
    assert r.json()["tombstoned"] is True

    # All default exclude tombstoned
    live = client.get("/solem/memory/all").json()
    assert len(live) == 0

    # Con include_tombstoned=true torna
    with_tomb = client.get("/solem/memory/all?include_tombstoned=true").json()
    assert len(with_tomb) == 1
    assert with_tomb[0]["tombstoned"] is True


def test_diff_since_empty_vc(client):
    client.post("/solem/memory", json={"kind": "user", "text": "m1"})
    client.post("/solem/memory", json={"kind": "user", "text": "m2"})

    # Empty vc → ritorna tutto
    r = client.get("/solem/memory/diff/since?vc_b64=")
    assert r.status_code == 200
    diff = r.json()
    assert len(diff["memories"]) == 2
    assert diff["new_vector_clock"]["test-device"] == 2


def test_diff_since_partial_vc(client):
    import base64
    import json
    client.post("/solem/memory", json={"kind": "user", "text": "m1"})  # vc={test-device:1}
    client.post("/solem/memory", json={"kind": "user", "text": "m2"})  # vc={test-device:2}

    # Peer ha già visto fino a 1 → ritorna solo m2
    vc = {"test-device": 1}
    vc_b64 = base64.urlsafe_b64encode(json.dumps(vc).encode()).rstrip(b"=").decode()
    r = client.get(f"/solem/memory/diff/since?vc_b64={vc_b64}")
    diff = r.json()
    assert len(diff["memories"]) == 1
    assert diff["memories"][0]["text"] == "m2"


def test_get_not_found(client):
    r = client.get("/solem/memory/ghost")
    assert r.status_code == 404
