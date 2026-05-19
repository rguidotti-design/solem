"""Test endpoint /health e /solem/manifest."""


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    assert "version" in body
    assert "timestamp" in body


def test_manifest_shape(client):
    r = client.get("/solem/manifest")
    assert r.status_code == 200
    m = r.json()
    assert m["name"] == "SOLEM"
    assert m["primary_ai"] == "gavio"
    assert m["step"] == 0
    assert len(m["layers"]) == 7
    layer_ids = [l["layer"] for l in m["layers"]]
    assert layer_ids == ["L1", "L2", "L3", "L4", "L5", "L6", "L7"]
    assert "modules" in m
    assert "runtime" in m


def test_docs_available(client):
    r = client.get("/docs")
    assert r.status_code == 200
    assert "swagger" in r.text.lower() or "openapi" in r.text.lower()


def test_openapi_schema(client):
    r = client.get("/openapi.json")
    assert r.status_code == 200
    spec = r.json()
    assert spec["info"]["title"] == "SOLEM API"
    # Verifica che tutti i router siano montati
    paths = spec["paths"]
    assert "/solem/identity/me" in paths
    assert "/solem/capabilities" in paths
    assert "/solem/system/info" in paths
    assert "/solem/users/me" in paths
