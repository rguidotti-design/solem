# GAVIO + SOLEM Public APIs (tool calling)

> GAVIO può arricchire le risposte chiamando le 22 API gratuite di `solem-api`.

## Pattern di tool-calling

Quando l'utente fa una domanda che richiede dati real-time, GAVIO può:

1. **Riconoscere intento** (es. "che tempo fa a Roma?")
2. **Mappare a tool** (`solem-api weather Roma`)
3. **Eseguire subprocess** (output JSON)
4. **Comporre risposta naturale** in italiano

### Esempio Python (GAVIO backend)

```python
import json, subprocess

def call_solem_api(category: str, *args) -> dict:
    """Tool wrapper: chiama solem-api CLI e ritorna JSON."""
    try:
        result = subprocess.run(
            ["solem-api", category, *args],
            capture_output=True, text=True, timeout=10, check=True,
        )
        return json.loads(result.stdout) if result.stdout.strip() else {}
    except (subprocess.SubprocessError, json.JSONDecodeError) as e:
        return {"error": str(e)}

def answer_with_tools(user_query: str) -> str:
    """Mock di intent detection + tool chain."""
    q = user_query.lower()
    if "tempo" in q or "meteo" in q:
        city = extract_city(q)  # NLP simple
        data = call_solem_api("weather", city)
        temp = data.get("temperature_2m", "?")
        return f"A {city} ci sono {temp}°C."
    if "tradu" in q:
        text = extract_text(q)
        data = call_solem_api("translate", text, "auto", "en")
        return f"Traduzione: {data}"
    if "cambio" in q or "euro" in q:
        data = call_solem_api("currency", "EUR", "USD")
        return f"1 EUR = {data['rate']} USD"
    # ...
    return "Non ho strumenti specifici per questa domanda."
```

## 22 tools mappati a intent

| Intento utente | Tool | Esempio |
|---|---|---|
| "che tempo fa a X?" | `weather X` | Meteo Open-Meteo |
| "dove si trova X?" | `geocode X` | Nominatim OSM |
| "traduci X" | `translate X` | MyMemory |
| "quanto vale 100 EUR in USD?" | `currency EUR USD 100` | Frankfurter ECB |
| "cosa significa X?" | `dict X` | Free Dictionary |
| "cerca X su wikipedia" | `wiki X` | Wikipedia REST |
| "che IP ho?" | `ip-info` | ipapi |
| "news di X" | `news X` | GNews/Wikipedia |
| "libri su X" | `books X` | OpenLibrary |
| "info su prodotto barcode" | `food <EAN>` | OpenFoodFacts |
| "festività italiane 2026" | `holidays 2026 IT` | Nager.Date |
| "info paese X" | `country X` | restcountries |
| "email è stata violata?" | `breach <email>` | HIBP (key richiesta) |
| "prezzo bitcoin" | `crypto bitcoin` | CoinGecko |
| "citazione motivante" | `quote` | ZenQuotes |
| "consiglio random" | `advice` | adviceslip |
| "trivia random" | `trivia` | OpenTDB |
| "barzelletta" | `joke` | icanhazdadjoke |
| "info colore #ff5733" | `color ff5733` | TheColorAPI |
| "QR code per link" | `qr <url>` | qrserver |
| "immagine gatto" | `cat` | TheCatAPI |
| "fatto sul numero 42" | `number 42` | Numbers API |

## Vantaggi rispetto a cloud LLM

| Aspetto | GAVIO + solem-api | ChatGPT/Claude |
|---|---|---|
| **Costo** | 0 € (FOSS+free tier) | $20+/mese subscription |
| **Latenza** | < 1s (locale) | 2-5s round-trip cloud |
| **Privacy** | Tutto local-first | Log centralizzato vendor |
| **Vendor lock-in** | Zero (sostituibili tutte) | Sì (API key proprietaria) |
| **Offline** | Sì (dopo cache) | No |
| **Customization** | Aggiungi API a tuo gusto | Solo plugins ufficiali |

## Demo immediata

```bash
# Senza GAVIO (test diretto API)
solem-api weather "Roma"
solem-api translate "ciao mondo" it en
solem-api currency EUR JPY 1000
solem-api qr "https://github.com/rguidotti-design/solem"

# Con GAVIO (futuro, quando integrazione tool-calling completa)
gavio "che tempo fa a Milano?"
# → GAVIO chiama solem-api weather Milano → compone risposta
```

## Estensione futura

Per aggiungere altre 30+ API da [public-apis](https://github.com/public-apis/public-apis):

1. Edita `nixos/modules/solem-public-apis.nix`
2. Aggiungi case shell per nuova API
3. Aggiorna `docs/PUBLIC-APIS.md`
4. (Opzionale) aggiungi unit test che chiama l'API in `nixos/tests/`

Categorie pendenti (esempi):

- **NASA APIs**: APOD picture-of-day, Mars Rover photos, Space-X launches
- **Health**: USDA Food (calorie/macros), OpenFDA (farmaci con foglietto)
- **Italia gov**: ISTAT statistics, Codice Fiscale generator
- **Music**: MusicBrainz (FOSS), Last.fm
- **Sports**: TheSportsDB (FOSS), F1 race data
- **ML inference**: HuggingFace free tier (text/image generation)
- **Transit**: GTFS feeds città italiane (Roma ATAC, Milano ATM)
