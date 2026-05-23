"""Performance smoke: latenza endpoint critici sotto soglia."""
import time
import pytest


# Soglie generose (in-memory + Windows host overhead). In Linux su Beelink
# saranno 5-10× più strette.
SOGLIA_HEALTH_MS = 200
SOGLIA_MANIFEST_MS = 500
SOGLIA_CLUSTER_TOPOLOGY_MS = 300


def _bench(client, path, method="GET", body=None, iters=10):
    durations = []
    for _ in range(iters):
        t0 = time.perf_counter()
        if method == "GET":
            r = client.get(path)
        else:
            r = client.post(path, json=body or {})
        assert r.status_code in (200, 404, 422)
        durations.append((time.perf_counter() - t0) * 1000)
    return sum(durations) / len(durations)


def test_health_under_200ms(client):
    avg = _bench(client, "/health", iters=20)
    assert avg < SOGLIA_HEALTH_MS, f"avg {avg:.1f}ms > {SOGLIA_HEALTH_MS}ms"


def test_manifest_under_500ms(client):
    avg = _bench(client, "/solem/manifest", iters=10)
    assert avg < SOGLIA_MANIFEST_MS, f"avg {avg:.1f}ms > {SOGLIA_MANIFEST_MS}ms"


def test_cluster_topology_under_300ms(client):
    avg = _bench(client, "/solem/cluster/topology", iters=10)
    assert avg < SOGLIA_CLUSTER_TOPOLOGY_MS, f"avg {avg:.1f}ms > {SOGLIA_CLUSTER_TOPOLOGY_MS}ms"


def test_concurrent_health_ok(client):
    """20 GET /health consecutivi non devono mai fallire."""
    for _ in range(20):
        r = client.get("/health")
        assert r.status_code == 200
        assert r.json()["status"] == "ok"


def test_404_returns_quickly(client):
    """Anche un 404 deve essere veloce."""
    avg = _bench(client, "/solem/this/does/not/exist", iters=10)
    assert avg < SOGLIA_HEALTH_MS, f"404 lento: {avg:.1f}ms"
