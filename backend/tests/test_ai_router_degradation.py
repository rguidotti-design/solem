"""Test graceful degradation: GAVIO offline → cache → pattern → 503."""
import pytest


@pytest.fixture(autouse=True)
def isolated_cache(monkeypatch, tmp_path):
    monkeypatch.setattr("solem_api.layers.ai_router.CACHE_FILE", tmp_path / "ai-cache.json")
    yield


@pytest.fixture
def gavio_offline(monkeypatch):
    """Forza GAVIO a essere irraggiungibile."""
    import httpx

    async def fake_post(*args, **kwargs):
        raise httpx.ConnectError("gavio down")

    # Patch httpx.AsyncClient.post nel modulo ai_router
    class FakeClient:
        async def __aenter__(self): return self
        async def __aexit__(self, *a): pass
        async def post(self, *a, **k): raise httpx.ConnectError("gavio down")

    monkeypatch.setattr("solem_api.layers.ai_router.httpx.AsyncClient", lambda *a, **k: FakeClient())


def test_offline_pattern_fallback_status(client, gavio_offline):
    r = client.post("/solem/ai/route", json={
        "messages": [{"role": "user", "content": "qual è lo stato sistema?"}],
        "hint": "auto", "max_tokens": 100,
    })
    assert r.status_code == 200
    data = r.json()
    assert data["degraded"] is True
    assert data["degraded_source"] == "pattern"
    assert "offline" in data["content"].lower() or "sistema" in data["content"].lower()


def test_offline_pattern_fallback_focus(client, gavio_offline):
    r = client.post("/solem/ai/route", json={
        "messages": [{"role": "user", "content": "blocca social 25 minuti"}],
        "hint": "auto",
    })
    assert r.status_code == 200
    assert r.json()["degraded_source"] == "pattern"


def test_offline_pattern_fallback_backup(client, gavio_offline):
    r = client.post("/solem/ai/route", json={
        "messages": [{"role": "user", "content": "fai backup ora"}],
        "hint": "auto",
    })
    assert r.status_code == 200
    assert "backup" in r.json()["content"].lower() or "restic" in r.json()["content"].lower()


def test_offline_unknown_query_503(client, gavio_offline):
    r = client.post("/solem/ai/route", json={
        "messages": [{"role": "user", "content": "spiega la teoria quantistica"}],
        "hint": "auto",
    })
    assert r.status_code == 503
    assert "gavio_offline" in r.json()["detail"]["code"]


def test_status_endpoint_does_not_break_when_gavio_down(client, gavio_offline):
    r = client.get("/solem/ai/status")
    # /ai/status fa una GET, non POST; con la fixture solo post è patched.
    # Ma il punto è che il route non crasha:
    assert r.status_code == 200
