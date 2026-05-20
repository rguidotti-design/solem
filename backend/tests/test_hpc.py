"""Test HPC: submit + list + cancel su backend mock."""
import pytest


@pytest.fixture(autouse=True)
def isolated_hpc(monkeypatch, tmp_path):
    monkeypatch.setattr("solem_api.layers.hpc.JOBS_LOG", tmp_path / "hpc_jobs.log")
    # Forza mock (slurm non installato in CI/Windows)
    monkeypatch.setenv("SOLEM_HPC_BACKEND", "mock")
    monkeypatch.setattr("solem_api.layers.hpc.BACKEND", "mock")


def _spec(name="test-job", **kw):
    base = {
        "name": name,
        "command": "echo hello",
        "partition": "default",
        "nodes": 1,
        "cpus_per_task": 2,
        "mem_gb": 4,
        "gpus": 0,
        "time_limit_min": 30,
        "env": {},
    }
    base.update(kw)
    return base


def test_health_reports_mock(client):
    r = client.get("/solem/hpc/health")
    assert r.status_code == 200
    assert r.json()["backend_active"] == "mock"


def test_submit_mock_returns_job_id(client):
    r = client.post("/solem/hpc/submit", json=_spec())
    assert r.status_code == 200
    data = r.json()
    assert data["job_id"].startswith("mock-")
    assert data["state"] == "pending"
    assert data["backend"] == "mock"


def test_submit_validates_limits(client):
    r = client.post("/solem/hpc/submit", json=_spec(nodes=2000))
    assert r.status_code == 422   # > 1024 nodi


def test_list_jobs_includes_submitted(client):
    client.post("/solem/hpc/submit", json=_spec("job-A"))
    client.post("/solem/hpc/submit", json=_spec("job-B"))
    r = client.get("/solem/hpc/jobs")
    assert r.status_code == 200
    names = [j["name"] for j in r.json()]
    assert "job-A" in names
    assert "job-B" in names


def test_cancel_mock(client):
    sub = client.post("/solem/hpc/submit", json=_spec()).json()
    r = client.delete(f"/solem/hpc/jobs/{sub['job_id']}")
    assert r.status_code == 200
    assert r.json()["backend"] == "mock"


def test_partitions_empty_on_mock(client):
    r = client.get("/solem/hpc/partitions")
    assert r.status_code == 200
    # mock backend → niente partition reale
    assert r.json() == []
