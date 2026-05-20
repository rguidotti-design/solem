"""Smoke test: l'app si carica e tutti i router montano correttamente."""
import pytest


def test_app_imports_clean():
    """L'import di main non deve sollevare eccezioni."""
    from solem_api import main
    assert main.app is not None


def test_health_endpoint(client):
    r = client.get("/health")
    assert r.status_code == 200
    data = r.json()
    assert data["status"] == "ok"
    assert "version" in data


def test_manifest_endpoint(client):
    r = client.get("/solem/manifest")
    assert r.status_code == 200
    data = r.json()
    assert data["name"] == "SOLEM"
    assert "layers" in data
    assert len(data["layers"]) == 7


def test_all_critical_router_mounted(client):
    """Verifica che TUTTI i router critici siano montati."""
    critical_endpoints = [
        "/solem/identity/me",
        "/solem/capabilities",
        "/solem/cluster/health",
        "/solem/federation/health",
        "/solem/handoff/health",
        "/solem/ai/status",
        "/solem/live",
        "/solem/hpc/health",
        "/solem/quantum/health",
        "/solem/datacenter/health",
        "/solem/vector/status",
        "/solem/voice/wake/status",
        "/solem/focus/health",
        "/solem/crashes/health",
        "/solem/updates/status",
    ]
    for endpoint in critical_endpoints:
        r = client.get(endpoint)
        assert r.status_code != 404, f"endpoint {endpoint} non montato"


def test_openapi_schema_includes_new_domains(client):
    r = client.get("/openapi.json")
    assert r.status_code == 200
    spec = r.json()
    paths = set(spec["paths"].keys())

    # I 3 nuovi domini di scala futura devono esserci
    assert any("/solem/hpc/" in p for p in paths), "HPC routes mancanti"
    assert any("/solem/quantum/" in p for p in paths), "Quantum routes mancanti"
    assert any("/solem/datacenter/" in p for p in paths), "DataCenter routes mancanti"

    # Trittico federazione
    assert any("/solem/federation/" in p for p in paths), "Federation mancante"
    assert any("/solem/handoff/" in p for p in paths), "Handoff mancante"
    assert any("/solem/cluster/" in p for p in paths), "Cluster mancante"


def test_layers_count_matches_manifest(client):
    """7 layer architetturali documentati nel manifest."""
    r = client.get("/solem/manifest")
    layers = r.json()["layers"]
    layer_ids = {l["layer"] for l in layers}
    assert layer_ids == {"L1", "L2", "L3", "L4", "L5", "L6", "L7"}
