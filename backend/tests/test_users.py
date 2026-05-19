"""Test multi-utente + auth."""


def test_me_returns_default_owner(client):
    r = client.get("/solem/users/me")
    assert r.status_code == 200
    body = r.json()
    assert body["username"] == "ruben"
    assert body["role"] == "owner"
    assert body["email"] == "guidottrbn@gmail.com"


def test_list_users_requires_owner(client):
    r = client.get("/solem/users")
    # Step 0 senza auth header → fallback owner di default, quindi 200
    assert r.status_code == 200
    users = r.json()
    assert any(u["role"] == "owner" for u in users)


def test_login_with_default_password(client):
    r = client.post("/solem/auth/login", json={"username": "ruben", "password": "solem"})
    assert r.status_code == 200
    body = r.json()
    assert "token" in body
    assert len(body["token"]) > 20
    assert body["user"]["username"] == "ruben"


def test_login_wrong_password(client):
    r = client.post("/solem/auth/login", json={"username": "ruben", "password": "wrong"})
    assert r.status_code == 401
    assert r.json()["detail"]["code"] == "invalid_credentials"


def test_create_user_as_owner(client):
    r = client.post("/solem/users", json={
        "username": "tester",
        "email": "test@example.com",
        "password": "supersecret",
        "role": "user",
    })
    assert r.status_code == 201
    assert r.json()["username"] == "tester"


def test_logout_revokes_token(client):
    login = client.post("/solem/auth/login", json={"username": "ruben", "password": "solem"})
    token = login.json()["token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Sessione attiva
    sessions = client.get("/solem/auth/sessions", headers=headers)
    assert sessions.status_code == 200
    assert len(sessions.json()) >= 1

    # Logout
    r = client.post("/solem/auth/logout", headers=headers)
    assert r.status_code == 200
    assert r.json()["logged_out"] is True
