"""Test L3 Event Bus."""


def test_publish_event(client):
    r = client.post("/solem/events/publish", json={
        "source": "test",
        "topic": "user.test",
        "payload": {"msg": "ciao"},
    })
    assert r.status_code == 200
    body = r.json()
    assert body["event_id"] > 0


def test_history_filter_by_topic(client):
    client.post("/solem/events/publish", json={"source": "x", "topic": "system.alert", "payload": {}})
    client.post("/solem/events/publish", json={"source": "y", "topic": "user.intent",  "payload": {}})
    r = client.get("/solem/events/history?topic=system.")
    body = r.json()
    assert all(ev["topic"].startswith("system.") for ev in body)


def test_history_limit(client):
    for i in range(5):
        client.post("/solem/events/publish", json={"source": "test", "topic": "spam.test", "payload": {"i": i}})
    r = client.get("/solem/events/history?limit=3")
    assert len(r.json()) <= 3
