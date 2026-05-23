"""Test cluster_migration: register task → heartbeat → orphan → sweep."""
import time
import pytest


@pytest.fixture(autouse=True)
def isolated_migration(monkeypatch, tmp_path):
    monkeypatch.setattr("solem_api.layers.cluster_migration.STATE_FILE",
                        tmp_path / "migration.json")


def test_health(client):
    r = client.get("/solem/migration/health")
    assert r.status_code == 200
    data = r.json()
    assert data["heartbeat_ttl_sec"] == 60
    assert "tasks_by_state" in data


def test_register_task(client):
    r = client.post("/solem/migration/register", json={
        "task_id": "task-1",
        "task_kind": "llm_inference",
        "device_id": "beelink",
        "size_hint": "small",
        "requires_gpu": False,
    })
    assert r.status_code == 200
    data = r.json()
    assert data["state"] == "running"
    assert data["current_device"] == "beelink"
    assert data["original_device"] == "beelink"


def test_heartbeat_updates_progress(client):
    client.post("/solem/migration/register", json={
        "task_id": "task-2", "device_id": "beelink",
        "size_hint": "tiny", "task_kind": "embedding", "requires_gpu": False,
    })
    r = client.post("/solem/migration/heartbeat", json={
        "task_id": "task-2", "device_id": "beelink", "progress_pct": 75.0,
    })
    assert r.status_code == 200
    assert r.json()["state"] == "running"

    # Verifica progress salvato
    task = client.get("/solem/migration/task-2").json()
    assert task["progress_pct"] == 75.0


def test_complete_task(client):
    client.post("/solem/migration/register", json={
        "task_id": "task-done", "device_id": "beelink",
        "size_hint": "small", "task_kind": "stt", "requires_gpu": False,
    })
    r = client.post("/solem/migration/complete", json={
        "task_id": "task-done", "device_id": "beelink",
        "success": True, "result_summary": "OK",
    })
    assert r.status_code == 200
    assert r.json()["final_state"] == "done"


def test_failed_task(client):
    client.post("/solem/migration/register", json={
        "task_id": "task-fail", "device_id": "beelink",
        "size_hint": "small", "task_kind": "tts", "requires_gpu": False,
    })
    r = client.post("/solem/migration/complete", json={
        "task_id": "task-fail", "device_id": "beelink",
        "success": False, "result_summary": "ERROR",
    })
    assert r.json()["final_state"] == "failed"


def test_active_list_only_running(client):
    client.post("/solem/migration/register", json={
        "task_id": "t-a", "device_id": "beelink",
        "size_hint": "tiny", "task_kind": "stt", "requires_gpu": False,
    })
    client.post("/solem/migration/register", json={
        "task_id": "t-b", "device_id": "laptop",
        "size_hint": "tiny", "task_kind": "stt", "requires_gpu": False,
    })
    client.post("/solem/migration/complete", json={
        "task_id": "t-a", "device_id": "beelink", "success": True,
    })

    active = client.get("/solem/migration/active").json()
    ids = {t["task_id"] for t in active}
    assert "t-b" in ids
    assert "t-a" not in ids  # completed, non più active


def test_orphan_detection_via_sweep(client, monkeypatch):
    """Forza un task come stale heartbeat → sweep lo marca orphaned."""
    client.post("/solem/migration/register", json={
        "task_id": "stale", "device_id": "ghost-device",
        "size_hint": "tiny", "task_kind": "stt", "requires_gpu": False,
    })

    # Forza heartbeat indietro nel tempo
    from solem_api.layers.cluster_migration import _load, _save
    state = _load()
    state["tasks"]["stale"]["last_heartbeat"] = time.time() - 3600  # 1h fa
    _save(state)

    r = client.post("/solem/migration/sweep")
    assert r.status_code == 200
    data = r.json()
    # Marcato orphaned (può anche essere migrated se dispatch ha trovato un device)
    # Almeno uno tra marked_orphaned e migrated deve essere ≥1, o stato finale ≠ running
    task = client.get("/solem/migration/stale").json()
    assert task["state"] in ("orphaned", "migrated")


def test_task_timeout(client, monkeypatch):
    """Task vecchio oltre TASK_TIMEOUT_SEC → marked failed."""
    client.post("/solem/migration/register", json={
        "task_id": "ancient", "device_id": "beelink",
        "size_hint": "tiny", "task_kind": "stt", "requires_gpu": False,
    })
    from solem_api.layers.cluster_migration import _load, _save
    state = _load()
    state["tasks"]["ancient"]["started_at"] = time.time() - 10000  # >> timeout
    state["tasks"]["ancient"]["last_heartbeat"] = time.time() - 10000
    _save(state)

    client.post("/solem/migration/sweep")
    task = client.get("/solem/migration/ancient").json()
    assert task["state"] == "failed"


def test_get_unknown_task(client):
    r = client.get("/solem/migration/ghost-task-id")
    assert r.status_code == 404
