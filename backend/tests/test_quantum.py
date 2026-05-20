"""Test quantum: submit OpenQASM Hadamard + result (mock o Aer)."""
import pytest


@pytest.fixture(autouse=True)
def isolated_quantum(monkeypatch, tmp_path):
    monkeypatch.setattr("solem_api.layers.quantum.JOBS_FILE", tmp_path / "quantum_jobs.json")
    monkeypatch.setattr("solem_api.layers.quantum.IBM_TOKEN_FILE", tmp_path / "ibm.token")


# Circuit Hadamard semplice (OpenQASM 2.0)
HADAMARD = """
OPENQASM 2.0;
include "qelib1.inc";
qreg q[1];
creg c[1];
h q[0];
measure q -> c;
"""


def test_health(client):
    r = client.get("/solem/quantum/health")
    assert r.status_code == 200
    data = r.json()
    assert "qiskit_available" in data
    assert data["simulator_ready"] is True


def test_providers_list(client):
    r = client.get("/solem/quantum/providers")
    assert r.status_code == 200
    ids = {p["id"] for p in r.json()}
    assert {"simulator", "ibm_quantum", "rigetti", "ionq", "mock"} <= ids
    # Simulator e mock sempre available
    sim = next(p for p in r.json() if p["id"] == "simulator")
    assert sim["available"] is True
    assert sim["free"] is True


def test_submit_hadamard_simulator(client):
    r = client.post("/solem/quantum/submit", json={
        "name": "hadamard-test",
        "openqasm": HADAMARD,
        "shots": 100,
        "provider": "simulator",
        "backend_name": "aer_simulator",
    })
    assert r.status_code == 200
    job = r.json()
    assert job["state"] == "done"  # simulator esegue inline
    assert job["qubits"] == 1
    assert job["shots"] == 100


def test_result_has_counts(client):
    sub = client.post("/solem/quantum/submit", json={
        "name": "h", "openqasm": HADAMARD, "shots": 200,
        "provider": "simulator", "backend_name": "aer",
    }).json()
    r = client.get(f"/solem/quantum/jobs/{sub['job_id']}/result")
    assert r.status_code == 200
    counts = r.json()["counts"]
    # Hadamard su 1 qubit → ~50/50 tra '0' e '1'
    total = sum(counts.values())
    assert total == 200


def test_jobs_list_persists(client):
    client.post("/solem/quantum/submit", json={
        "name": "q1", "openqasm": HADAMARD, "shots": 10,
        "provider": "mock", "backend_name": "mock",
    })
    r = client.get("/solem/quantum/jobs")
    assert r.status_code == 200
    assert any(j["name"] == "q1" for j in r.json())


def test_cancel(client):
    sub = client.post("/solem/quantum/submit", json={
        "name": "to-cancel", "openqasm": HADAMARD, "shots": 1,
        "provider": "mock", "backend_name": "mock",
    }).json()
    r = client.delete(f"/solem/quantum/jobs/{sub['job_id']}")
    assert r.status_code == 200
    assert r.json()["cancelled"] is True
