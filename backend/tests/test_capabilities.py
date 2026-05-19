"""Test L4 Capabilities — registry dichiarativo."""


def test_list_capabilities(client):
    r = client.get("/solem/capabilities")
    assert r.status_code == 200
    body = r.json()
    assert body["total"] > 10  # almeno le native SOLEM
    assert "solem" in body["sources"]


def test_filter_by_source_solem(client):
    r = client.get("/solem/capabilities?source=solem")
    body = r.json()
    assert all(c["source"] == "solem" for c in body["capabilities"])


def test_filter_by_tag_identity(client):
    r = client.get("/solem/capabilities?tag=identity")
    body = r.json()
    assert all("identity" in c["tags"] for c in body["capabilities"])


def test_text_search_q(client):
    r = client.get("/solem/capabilities?q=memoria")
    body = r.json()
    assert body["total"] >= 1
    for c in body["capabilities"]:
        text = (c["id"] + c["name"] + c["description"]).lower()
        assert "memoria" in text


def test_get_capability_by_id(client):
    r = client.get("/solem/capabilities/system.info")
    assert r.status_code == 200
    body = r.json()
    assert body["id"] == "system.info"
    assert body["method"] == "GET"


def test_get_nonexistent_capability(client):
    r = client.get("/solem/capabilities/does.not.exist")
    assert r.status_code == 404
