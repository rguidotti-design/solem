"""Test L5 Memory (livello A + B)."""


def test_store_and_recent(client):
    r = client.post("/solem/memory/store", json={
        "source": "chat",
        "content": "Ricorda che il deploy avviene il venerdì",
        "importance": 0.7,
        "metadata": {"thread_id": "abc"},
    })
    assert r.status_code == 201
    assert r.json()["content"].startswith("Ricorda")

    r2 = client.get("/solem/memory/recent")
    assert r2.status_code == 200
    items = r2.json()
    assert len(items) >= 1
    assert items[0]["source"] == "chat"


def test_filter_by_source(client):
    client.post("/solem/memory/store", json={"source": "chat", "content": "msg chat"})
    client.post("/solem/memory/store", json={"source": "decision", "content": "ho deciso X"})
    r = client.get("/solem/memory/recent?source=decision")
    items = r.json()
    assert all(i["source"] == "decision" for i in items)


def test_search_finds_substring(client):
    client.post("/solem/memory/store", json={
        "source": "idea",
        "content": "Idea: integrare WireGuard nativamente in SOLEM",
        "importance": 0.9,
    })
    r = client.post("/solem/memory/search", json={"query": "WireGuard"})
    assert r.status_code == 200
    hits = r.json()
    assert len(hits) >= 1
    assert "WireGuard" in hits[0]["record"]["content"]


def test_universe_store_with_privacy(client):
    r = client.post("/solem/memory/universe/store", json={
        "source_type": "email",
        "source_id": "msg-id-1",
        "content": "email confidenziale",
        "privacy_level": "sacred",
    })
    assert r.status_code == 201
    assert r.json()["privacy_level"] == "sacred"


def test_universe_filter_by_type(client):
    client.post("/solem/memory/universe/store", json={
        "source_type": "calendar",
        "source_id": "evt1",
        "content": "meeting",
    })
    r = client.get("/solem/memory/universe/recent?source_type=calendar")
    items = r.json()
    assert all(i["source_type"] == "calendar" for i in items)
