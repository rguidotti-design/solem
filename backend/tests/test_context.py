"""Test L2 Context Engine."""


def test_context_now_empty(client):
    r = client.get("/solem/context/now")
    assert r.status_code == 200
    body = r.json()
    assert "ts" in body
    assert "server_ts" in body


def test_push_snapshot_and_read(client):
    snap = {
        "location": "ufficio",
        "active_role": "founder",
        "current_task": "coding solem",
        "apps_open": ["vscode", "firefox"],
    }
    r = client.post("/solem/context/snapshot", json=snap)
    assert r.status_code == 201
    body = r.json()
    assert body["location"] == "ufficio"
    assert body["apps_open"] == ["vscode", "firefox"]

    # /now ora riflette il push
    r2 = client.get("/solem/context/now")
    body2 = r2.json()
    assert body2["location"] == "ufficio"
    assert body2["seconds_since_snapshot"] >= 0


def test_history(client):
    for i in range(3):
        client.post("/solem/context/snapshot", json={"location": f"loc-{i}"})
    r = client.get("/solem/context/history?limit=10")
    assert r.status_code == 200
    history = r.json()
    assert len(history) >= 3
    # Più recente per primo
    assert history[0]["location"] == "loc-2"


def test_history_limit_clamp(client):
    r = client.get("/solem/context/history?limit=1000")
    assert r.status_code == 200

    r2 = client.get("/solem/context/history?limit=0")
    assert r2.status_code == 422  # validation error: ge=1
