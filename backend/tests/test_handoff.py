"""Test handoff continuity tra device."""
import pytest


@pytest.fixture(autouse=True)
def isolated_handoff(monkeypatch, tmp_path):
    monkeypatch.setattr("solem_api.layers.handoff.HANDOFF_FILE", tmp_path / "handoff.json")
    yield


def _push(client, **kw):
    body = {
        "kind": kw.get("kind", "open_url"),
        "payload": kw.get("payload", {"url": "https://news.ycombinator.com"}),
        "owner_username": kw.get("owner", "ruben"),
        "source_device_id": kw.get("source", "laptop"),
        "target_device_id": kw.get("target"),
        "title": kw.get("title", "Apri HN"),
        "description": kw.get("desc", ""),
    }
    return client.post("/solem/handoff/push", json=body)


def test_push_returns_id(client):
    r = _push(client)
    assert r.status_code == 200
    assert "id" in r.json()


def test_pending_excludes_source_device(client):
    _push(client, source="laptop", target=None)
    # Stesso device → no
    r = client.get("/solem/handoff/pending?device_id=laptop&owner_username=ruben")
    assert r.json() == []
    # Altro device → sì
    r = client.get("/solem/handoff/pending?device_id=phone&owner_username=ruben")
    assert len(r.json()) == 1


def test_pending_targeted(client):
    _push(client, source="laptop", target="phone")
    # phone vede l'handoff
    r = client.get("/solem/handoff/pending?device_id=phone&owner_username=ruben")
    assert len(r.json()) == 1
    # tablet (non target) NO
    r = client.get("/solem/handoff/pending?device_id=tablet&owner_username=ruben")
    assert r.json() == []


def test_claim_marks_handoff(client):
    push = _push(client, source="laptop", target=None).json()
    r = client.post(f"/solem/handoff/claim/{push['id']}?device_id=phone")
    assert r.status_code == 200
    assert r.json()["claimed_by"] == "phone"

    # Secondo claim → 409
    r2 = client.post(f"/solem/handoff/claim/{push['id']}?device_id=phone")
    assert r2.status_code == 409


def test_owner_filter(client):
    _push(client, owner="ruben", source="laptop")
    _push(client, owner="other-user", source="laptop")
    r = client.get("/solem/handoff/pending?device_id=phone&owner_username=ruben")
    assert len(r.json()) == 1
    assert r.json()[0]["owner_username"] == "ruben"


def test_cancel_removes_item(client):
    push = _push(client).json()
    r = client.delete(f"/solem/handoff/{push['id']}")
    assert r.status_code == 200
    r2 = client.get("/solem/handoff/pending?device_id=phone&owner_username=ruben")
    assert r2.json() == []
