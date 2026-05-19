"""Test pairing PIN BBM-style."""

import re


def test_start_pairing_generates_pin(client):
    r = client.post("/solem/pairing/start")
    assert r.status_code == 200
    body = r.json()
    pin = body["pin"]
    assert re.fullmatch(r"[0-9A-F]{8}", pin), f"PIN non BBM-style: {pin}"
    assert "expires_at" in body


def test_pin_is_single_use(client):
    start = client.post("/solem/pairing/start").json()
    pin = start["pin"]

    confirm_body = {
        "pin": pin,
        "device_name": "test-device",
        "device_pubkey_wg": "FakePubKeyBase64==",
    }
    r1 = client.post("/solem/pairing/confirm", json=confirm_body)
    assert r1.status_code == 200
    assert r1.json()["assigned_ip"].startswith("10.42.0.")

    # Secondo uso dello stesso PIN fallisce
    r2 = client.post("/solem/pairing/confirm", json=confirm_body)
    assert r2.status_code == 404
    assert r2.json()["detail"]["code"] == "pin_unknown"


def test_unknown_pin_fails(client):
    r = client.post("/solem/pairing/confirm", json={
        "pin": "DEADBEEF",
        "device_name": "x",
        "device_pubkey_wg": "y",
    })
    assert r.status_code == 404


def test_devices_listed_after_pairing(client):
    start = client.post("/solem/pairing/start").json()
    client.post("/solem/pairing/confirm", json={
        "pin": start["pin"],
        "device_name": "my-phone",
        "device_pubkey_wg": "abc",
    })
    r = client.get("/solem/pairing/devices")
    body = r.json()
    assert any(d["name"] == "my-phone" for d in body["devices"])
