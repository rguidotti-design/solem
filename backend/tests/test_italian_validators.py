"""Test validatori italiani: CF, IBAN, P.IVA, PEC."""


def test_health(client):
    r = client.get("/solem/it/health")
    assert r.status_code == 200
    assert "validators" in r.json()


def test_codice_fiscale_valido(client):
    """Calcoliamo checksum corretto usando lo stesso algoritmo."""
    from solem_api.layers.italian_validators import _cf_checksum
    check = _cf_checksum("RSSMRA85M01H501")
    full = "RSSMRA85M01H501" + check
    r = client.post("/solem/it/codice-fiscale", json={"value": full})
    data = r.json()
    assert data["valid"] is True
    assert data["details"]["sex"] == "M"


def test_codice_fiscale_invalido_length(client):
    r = client.post("/solem/it/codice-fiscale", json={"value": "ABC"})
    assert r.json()["valid"] is False


def test_codice_fiscale_check_donna(client):
    """Donna: giorno + 40 (es. nata il 15 → 55)."""
    from solem_api.layers.italian_validators import _cf_checksum
    check = _cf_checksum("BNCMRA85M55H501")
    r = client.post("/solem/it/codice-fiscale", json={"value": "BNCMRA85M55H501" + check})
    assert r.json()["details"]["sex"] == "F"


def test_iban_italiano_valido(client):
    # IBAN italiano sintetico valido
    r = client.post("/solem/it/iban", json={"value": "IT60X0542811101000000123456"})
    data = r.json()
    assert "country" in data["details"]


def test_iban_invalido_pattern(client):
    r = client.post("/solem/it/iban", json={"value": "ABC123"})
    assert r.json()["valid"] is False


def test_iban_normalizza_spazi(client):
    r = client.post("/solem/it/iban", json={"value": "IT60 X054 2811 1010 0000 0123 456"})
    # Pattern dopo strip
    assert "IT60" in r.json()["input"]


def test_piva_valida(client):
    # P.IVA test valida calcolata: 00000000000 → checksum 0 → valida
    r = client.post("/solem/it/partita-iva", json={"value": "00000000000"})
    assert r.json()["valid"] is True


def test_piva_lunghezza_errata(client):
    r = client.post("/solem/it/partita-iva", json={"value": "12345"})
    assert r.json()["valid"] is False


def test_pec_aruba(client):
    r = client.post("/solem/it/pec", json={"value": "mario@pec.aruba.it"})
    data = r.json()
    assert data["valid"] is True
    assert data["details"]["domain"] == "pec.aruba.it"


def test_pec_non_pec(client):
    """Email normale non è PEC."""
    r = client.post("/solem/it/pec", json={"value": "mario@gmail.com"})
    assert r.json()["valid"] is False


def test_dotfiles_health(client):
    r = client.get("/solem/dotfiles/health")
    assert r.status_code == 200
    data = r.json()
    assert "device_id" in data
    assert "whitelist" in data
