"""Test datacenter: register node + power + sensors (mock protocol)."""
import pytest


@pytest.fixture(autouse=True)
def isolated_dc(monkeypatch, tmp_path):
    monkeypatch.setattr("solem_api.layers.datacenter.INVENTORY_FILE",
                        tmp_path / "datacenter_inventory.json")
    monkeypatch.setattr("solem_api.layers.datacenter.BMC_CREDS_DIR", tmp_path / "bmc")


def _node(name="node1", rack="rack-A", role="compute", protocol="mock"):
    return {
        "name": name,
        "bmc_ip": "10.0.0.10",
        "bmc_protocol": protocol,
        "rack": rack,
        "rack_unit": 5,
        "role": role,
        "tags": [],
        "power_state": "unknown",
    }


def test_register_and_list(client):
    r = client.post("/solem/datacenter/nodes", json=_node())
    assert r.status_code == 200

    r2 = client.get("/solem/datacenter/nodes")
    assert len(r2.json()) == 1
    assert r2.json()[0]["name"] == "node1"


def test_filter_by_rack(client):
    client.post("/solem/datacenter/nodes", json=_node("n1", rack="A"))
    client.post("/solem/datacenter/nodes", json=_node("n2", rack="B"))
    r = client.get("/solem/datacenter/nodes?rack=A")
    assert len(r.json()) == 1


def test_filter_by_role(client):
    client.post("/solem/datacenter/nodes", json=_node("n1", role="compute"))
    client.post("/solem/datacenter/nodes", json=_node("n2", role="storage"))
    r = client.get("/solem/datacenter/nodes?role=storage")
    assert len(r.json()) == 1
    assert r.json()[0]["role"] == "storage"


def test_get_node_not_found(client):
    r = client.get("/solem/datacenter/nodes/ghost")
    assert r.status_code == 404


def test_power_mock(client):
    client.post("/solem/datacenter/nodes", json=_node("node1"))
    r = client.post("/solem/datacenter/nodes/node1/power",
                    json={"action": "on"})
    assert r.status_code == 200
    assert r.json()["result"] == "mock-ok"

    # Stato aggiornato
    n = client.get("/solem/datacenter/nodes/node1").json()
    assert n["power_state"] == "on"


def test_sensors_mock_returns_stubs(client):
    client.post("/solem/datacenter/nodes", json=_node("node1"))
    r = client.get("/solem/datacenter/nodes/node1/sensors")
    assert r.status_code == 200
    sensors = r.json()
    assert len(sensors) >= 3
    assert any("Temp" in s["name"] for s in sensors)


def test_racks_aggregate(client):
    client.post("/solem/datacenter/nodes", json=_node("n1", rack="A", role="compute"))
    client.post("/solem/datacenter/nodes", json=_node("n2", rack="A", role="storage"))
    client.post("/solem/datacenter/nodes", json=_node("n3", rack="B", role="gpu"))
    r = client.get("/solem/datacenter/racks")
    assert r.status_code == 200
    racks = r.json()
    rack_a = next(r for r in racks if r["rack"] == "A")
    assert rack_a["total_nodes"] == 2
    assert rack_a["by_role"]["compute"] == 1
    assert rack_a["by_role"]["storage"] == 1


def test_remove_node(client):
    client.post("/solem/datacenter/nodes", json=_node())
    r = client.delete("/solem/datacenter/nodes/node1")
    assert r.status_code == 200
    assert client.get("/solem/datacenter/nodes/node1").status_code == 404
