"""Test context_actions: MIME → action suggest + execute redirect."""
import pytest


def test_health(client):
    r = client.get("/solem/actions/health")
    assert r.status_code == 200
    data = r.json()
    assert "static_mime_categories" in data
    assert data["ai_fallback_enabled"] is True


def test_suggest_pdf(client, tmp_path):
    pdf = tmp_path / "report.pdf"
    pdf.write_bytes(b"%PDF-1.4\n...")

    r = client.post("/solem/actions/suggest", json={
        "path": str(pdf), "use_ai_for_ambiguous": False,
    })
    assert r.status_code == 200
    actions = r.json()
    assert len(actions) >= 3
    ids = {a["id"] for a in actions}
    assert "summarize" in ids
    assert "extract-text" in ids
    # tutti action source statico (no AI per pdf)
    assert all(a["source"] == "static" for a in actions)


def test_suggest_image(client, tmp_path):
    img = tmp_path / "photo.png"
    img.write_bytes(b"\x89PNG\r\n\x1a\n")

    actions = client.post("/solem/actions/suggest", json={"path": str(img)}).json()
    ids = {a["id"] for a in actions}
    assert "describe" in ids
    assert "ocr" in ids
    assert "detect-objects" in ids


def test_suggest_audio(client, tmp_path):
    audio = tmp_path / "voice.mp3"
    audio.write_bytes(b"\xff\xfb")  # mp3 magic

    actions = client.post("/solem/actions/suggest", json={"path": str(audio)}).json()
    ids = {a["id"] for a in actions}
    assert "transcribe" in ids


def test_suggest_text(client, tmp_path):
    txt = tmp_path / "note.txt"
    txt.write_text("ciao")

    actions = client.post("/solem/actions/suggest", json={"path": str(txt)}).json()
    ids = {a["id"] for a in actions}
    assert "summarize" in ids
    assert "translate" in ids


def test_suggest_path_not_found(client):
    r = client.post("/solem/actions/suggest", json={
        "path": "/nonexistent/file.pdf",
    })
    assert r.status_code == 404


def test_execute_returns_redirect(client, tmp_path):
    pdf = tmp_path / "test.pdf"
    pdf.write_bytes(b"%PDF-1.4\n")
    r = client.post("/solem/actions/execute", json={
        "action_id": "summarize",
        "path": str(pdf),
        "overrides": {"language": "fr"},
    })
    assert r.status_code == 200
    data = r.json()
    assert data["redirect_to"] == "/solem/summarize/file"
    assert data["method"] == "POST"
    assert data["suggested_payload"]["language"] == "fr"


def test_execute_action_not_found(client, tmp_path):
    pdf = tmp_path / "test.pdf"
    pdf.write_bytes(b"%PDF-1.4\n")
    r = client.post("/solem/actions/execute", json={
        "action_id": "describe",  # solo per immagini, non pdf
        "path": str(pdf),
    })
    assert r.status_code == 404
    assert "available" in r.json()["detail"]
