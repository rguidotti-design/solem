"""Test cluster: register device → heartbeat → dispatch → topology."""
import os
import tempfile
from pathlib import Path

import pytest


@pytest.fixture(autouse=True)
def isolated_cluster_state(monkeypatch, tmp_path):
    fake = tmp_path / "cluster.json"
    monkeypatch.setattr("solem_api.layers.cluster.REGISTRY_FILE", fake)
    yield


def _device_payload(device_id="dev-laptop", gpu=False, ram=16, cores=8):
    return {
        "device_id": device_id,
        "name": device_id,
        "endpoint": f"http://{device_id}.solem.local:8001",
        "capabilities": {
            "cpu_cores": cores,
            "cpu_model": "test cpu",
            "ram_gb": ram,
            "disk_free_gb": 100,
            "gpu": {"kind": "nvidia" if gpu else "none", "model": "RTX" if gpu else None, "vram_gb": 24 if gpu else 0},
            "arch": "x86_64",
            "os": "linux",
        },
        "roles": ["worker", "gpu-server"] if gpu else ["worker"],
    }


def test_register_and_list_device(client):
    r = client.post("/solem/cluster/register", json=_device_payload())
    assert r.status_code == 200
    assert r.json()["device_id"] == "dev-laptop"

    r2 = client.get("/solem/cluster/devices")
    assert r2.status_code == 200
    devices = r2.json()
    assert len(devices) == 1
    assert devices[0]["online"] is True


def test_heartbeat_updates_load(client):
    client.post("/solem/cluster/register", json=_device_payload())
    r = client.post("/solem/cluster/heartbeat", json={
        "device_id": "dev-laptop", "load_pct": 67.5,
        "ram_used_pct": 45, "gpu_used_pct": 0, "inflight_tasks": 2,
    })
    assert r.status_code == 200
    devices = client.get("/solem/cluster/devices").json()
    assert devices[0]["load_pct"] == 67.5
    assert devices[0]["inflight_tasks"] == 2


def test_heartbeat_unregistered_fails(client):
    r = client.post("/solem/cluster/heartbeat", json={
        "device_id": "ghost", "load_pct": 0, "ram_used_pct": 0,
    })
    assert r.status_code == 404


def test_dispatch_prefers_gpu_for_inference(client):
    client.post("/solem/cluster/register", json=_device_payload("laptop", gpu=False, ram=16))
    client.post("/solem/cluster/register", json=_device_payload("server-gpu", gpu=True, ram=64))

    r = client.post("/solem/cluster/dispatch", json={
        "task_kind": "llm_inference",
        "size_hint": "large",
        "requires_gpu": True,
    })
    assert r.status_code == 200
    assert r.json()["device_id"] == "server-gpu"
    assert "GPU" in r.json()["reason"]


def test_dispatch_no_capable_device(client):
    client.post("/solem/cluster/register", json=_device_payload("tiny", gpu=False, ram=2, cores=2))
    r = client.post("/solem/cluster/dispatch", json={
        "task_kind": "llm_inference", "size_hint": "xlarge",
        "requires_gpu": True, "min_vram_gb": 24,
    })
    assert r.status_code == 503


def test_topology_aggregates_resources(client):
    client.post("/solem/cluster/register", json=_device_payload("a", ram=16, cores=8))
    client.post("/solem/cluster/register", json=_device_payload("b", gpu=True, ram=64, cores=16))
    r = client.get("/solem/cluster/topology")
    assert r.status_code == 200
    data = r.json()
    assert data["online_devices"] == 2
    assert data["total_cpu_cores"] == 24
    assert data["total_ram_gb"] == 80.0
    assert data["total_vram_gb"] == 24.0
    assert data["gpu_devices"] == 1


def test_remove_device(client):
    client.post("/solem/cluster/register", json=_device_payload("temp"))
    r = client.delete("/solem/cluster/devices/temp")
    assert r.status_code == 200
    devices = client.get("/solem/cluster/devices").json()
    assert len(devices) == 0
