"""Test L1 Identity Engine — CRUD sezioni + versioning."""


def test_get_me_creates_default_identity(client):
    r = client.get("/solem/identity/me")
    assert r.status_code == 200
    body = r.json()
    assert body["user_id"] == "00000000-0000-0000-0000-000000000001"
    assert body["name"] == "Ruben Guidotti"
    assert body["email"] == "guidottrbn@gmail.com"
    # 5 sezioni standard auto-create
    keys = set(body["sections"].keys())
    assert {"roles", "values", "goals", "routine", "persone"} <= keys


def test_list_sections(client):
    r = client.get("/solem/identity/sections")
    assert r.status_code == 200
    sections = r.json()
    assert "roles" in sections
    for key in ["roles", "values", "goals", "routine", "persone"]:
        assert sections[key]["is_standard"] is True


def test_upsert_standard_section_increments_version(client):
    # Iniziale
    r1 = client.get("/solem/identity/sections/roles")
    assert r1.status_code == 200
    v1 = r1.json()["version"]

    # Update
    r2 = client.put("/solem/identity/sections/roles", json={"content": ["founder", "operator"]})
    assert r2.status_code == 200
    assert r2.json()["content"] == ["founder", "operator"]
    assert r2.json()["version"] == v1 + 1

    # Re-update
    r3 = client.put("/solem/identity/sections/roles", json={"content": ["founder"]})
    assert r3.json()["version"] == v1 + 2


def test_create_custom_section(client):
    r = client.put("/solem/identity/sections/custom_hobbies", json={"content": ["calcio", "lettura"]})
    assert r.status_code == 200
    assert r.json()["is_standard"] is False
    assert r.json()["content"] == ["calcio", "lettura"]


def test_invalid_section_key_rejected(client):
    r = client.put("/solem/identity/sections/invalid_name", json={"content": []})
    assert r.status_code == 400
    assert r.json()["detail"]["code"] == "invalid_section_key"


def test_cannot_delete_standard_section(client):
    r = client.delete("/solem/identity/sections/roles")
    assert r.status_code == 400
    assert r.json()["detail"]["code"] == "cannot_delete_standard"


def test_delete_custom_section(client):
    # Crea poi cancella
    client.put("/solem/identity/sections/custom_tmp", json={"content": {}})
    r = client.delete("/solem/identity/sections/custom_tmp")
    assert r.status_code == 200
    assert r.json()["deleted"] is True
    # Ora non esiste
    r2 = client.get("/solem/identity/sections/custom_tmp")
    assert r2.status_code == 404


def test_get_nonexistent_section(client):
    r = client.get("/solem/identity/sections/custom_nonexistent")
    assert r.status_code == 404
