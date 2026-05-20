"""Test cluster scoring con device_class (workstation/edge-cpu/edge-gpu/glass)."""
import pytest


@pytest.fixture(autouse=True)
def isolated_cluster_state(monkeypatch, tmp_path):
    monkeypatch.setattr("solem_api.layers.cluster.REGISTRY_FILE", tmp_path / "cluster.json")


def _dev(device_id, device_class="workstation", gpu=False, ram=16, cores=8, vram=0):
    return {
        "device_id": device_id,
        "name": device_id,
        "endpoint": f"http://{device_id}:8001",
        "capabilities": {
            "cpu_cores": cores,
            "cpu_model": "test cpu",
            "ram_gb": ram,
            "disk_free_gb": 100,
            "gpu": {
                "kind": "nvidia" if gpu else ("integrated" if device_class == "edge-gpu" else "none"),
                "model": "test GPU" if gpu or device_class == "edge-gpu" else None,
                "vram_gb": vram,
            },
            "arch": "aarch64" if device_class.startswith("edge") else "x86_64",
            "os": "linux",
            "device_class": device_class,
        },
        "roles": ["worker"],
    }


def test_workstation_wins_xlarge_inference(client):
    """Task xlarge (LLM grande) → workstation, NON edge."""
    client.post("/solem/cluster/register",
                json=_dev("beelink", device_class="workstation", ram=32, cores=8))
    client.post("/solem/cluster/register",
                json=_dev("pi5", device_class="edge-cpu", ram=8, cores=4))

    r = client.post("/solem/cluster/dispatch", json={
        "task_kind": "llm_inference",
        "size_hint": "xlarge",
        "requires_gpu": False,
    })
    # xlarge richiede 32 GB → solo workstation può
    assert r.status_code == 200
    assert r.json()["device_id"] == "beelink"


def test_edge_gpu_wins_vision_small(client):
    """Vision small → edge-gpu (Jetson) bonus +50."""
    client.post("/solem/cluster/register",
                json=_dev("beelink", device_class="workstation", ram=32, cores=8))
    client.post("/solem/cluster/register",
                json=_dev("jetson", device_class="edge-gpu", ram=8, cores=6, vram=8))

    r = client.post("/solem/cluster/dispatch", json={
        "task_kind": "vision",
        "size_hint": "small",
        "requires_gpu": False,
    })
    # Jetson edge-gpu vince per vision small
    assert r.status_code == 200
    assert r.json()["device_id"] == "jetson"


def test_edge_cpu_wins_stt_tiny(client):
    """STT tiny → edge-cpu (Pi) bonus +40."""
    client.post("/solem/cluster/register",
                json=_dev("beelink", device_class="workstation", ram=32, cores=8))
    client.post("/solem/cluster/register",
                json=_dev("pi5", device_class="edge-cpu", ram=8, cores=4))

    r = client.post("/solem/cluster/dispatch", json={
        "task_kind": "stt",
        "size_hint": "tiny",
        "requires_gpu": False,
    })
    assert r.status_code == 200
    # Edge-cpu vince per STT tiny low-latency
    assert r.json()["device_id"] == "pi5"


def test_glass_never_gets_inference(client):
    """Glass (occhiali) NON deve ricevere inference."""
    client.post("/solem/cluster/register",
                json=_dev("beelink", device_class="workstation", ram=32, cores=8))
    client.post("/solem/cluster/register",
                json=_dev("glass-ruben", device_class="glass-companion", ram=2, cores=2))

    r = client.post("/solem/cluster/dispatch", json={
        "task_kind": "llm_inference",
        "size_hint": "small",
        "requires_gpu": False,
    })
    assert r.status_code == 200
    # Beelink workstation deve vincere, NON glass
    assert r.json()["device_id"] == "beelink"


def test_iot_only_accepts_tiny(client):
    """Device IoT → solo task tiny."""
    client.post("/solem/cluster/register",
                json=_dev("workstation", device_class="workstation", ram=32))
    client.post("/solem/cluster/register",
                json=_dev("pico", device_class="iot", ram=2, cores=2))

    # Medium → IoT penalizzato -200
    r = client.post("/solem/cluster/dispatch", json={
        "task_kind": "generic_cpu", "size_hint": "medium", "requires_gpu": False,
    })
    assert r.status_code == 200
    assert r.json()["device_id"] == "workstation"


def test_edge_cpu_rejects_large_task(client):
    """Pi NON deve ricevere task medium+ anche se è l'unico online."""
    client.post("/solem/cluster/register",
                json=_dev("pi5", device_class="edge-cpu", ram=8, cores=4))

    r = client.post("/solem/cluster/dispatch", json={
        "task_kind": "llm_inference", "size_hint": "large", "requires_gpu": False,
    })
    # large richiede 16 GB → Pi (8 GB) sotto soglia → 503
    assert r.status_code == 503


def test_topology_includes_device_class(client):
    """Topology aggrega anche device_class info."""
    client.post("/solem/cluster/register",
                json=_dev("beelink", device_class="workstation", ram=32))
    client.post("/solem/cluster/register",
                json=_dev("pi5", device_class="edge-cpu", ram=8))
    client.post("/solem/cluster/register",
                json=_dev("jetson", device_class="edge-gpu", ram=8, vram=8))

    r = client.get("/solem/cluster/topology")
    assert r.status_code == 200
    data = r.json()
    assert data["online_devices"] == 3
    # device_class deve essere nelle capabilities dei device
    classes = {d["capabilities"]["device_class"] for d in data["devices"]}
    assert "workstation" in classes
    assert "edge-cpu" in classes
    assert "edge-gpu" in classes
