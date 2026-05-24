# SOLEM — 22 API gratuite integrate

> Selezione da [github.com/public-apis/public-apis](https://github.com/public-apis/public-apis).
> Criterio: FOSS o free-tier no-auth. Tutto 0 €.

CLI: `solem-api <categoria> <argomento>` (vedi `solem-api help`).

---

## 🌍 Geo & Tempo

| Categoria | API | FOSS? | Auth |
|---|---|---|---|
| **Meteo** | [Open-Meteo](https://open-meteo.com) | ✅ | ❌ no-auth |
| **Geocoding** | [Nominatim (OSM)](https://nominatim.openstreetmap.org) | ✅ | ❌ no-auth (rate-limit 1 req/s) |
| **IP info** | [ipapi.co](https://ipapi.co) | ❌ closed | ❌ no-auth (free tier 1000/day) |
| **Festività** | [Nager.Date](https://date.nager.at) | ✅ | ❌ no-auth |
| **Paesi** | [restcountries](https://restcountries.com) | ✅ | ❌ no-auth |

## 📚 Conoscenza

| Categoria | API | FOSS? | Auth |
|---|---|---|---|
| **Wikipedia** | [Wikipedia REST](https://www.mediawiki.org/wiki/API:REST_API) | ✅ AGPL | ❌ no-auth |
| **Libri** | [OpenLibrary](https://openlibrary.org/developers/api) | ✅ AGPL | ❌ no-auth |
| **Dizionario** | [Free Dictionary](https://dictionaryapi.dev) | ❌ | ❌ no-auth |
| **Numeri** | [Numbers API](http://numbersapi.com) | ❌ | ❌ no-auth |

## 💸 Finanza

| Categoria | API | FOSS? | Auth |
|---|---|---|---|
| **Cambio EUR** | [Frankfurter (ECB)](https://www.frankfurter.app) | ✅ MIT | ❌ no-auth |
| **Crypto** | [CoinGecko](https://www.coingecko.com/api) | ❌ closed | ❌ no-auth (free) |

## 🗣️ Linguaggio

| Categoria | API | FOSS? | Auth |
|---|---|---|---|
| **Traduzione** | [MyMemory](https://mymemory.translated.net) | ❌ | ❌ no-auth (5000c/d) |
| **Alt FOSS** | [LibreTranslate](https://libretranslate.com) | ✅ AGPL | Self-host gratis |

## 🍱 Vita reale

| Categoria | API | FOSS? | Auth |
|---|---|---|---|
| **Cibo** | [OpenFoodFacts](https://world.openfoodfacts.org/data) | ✅ ODbL | ❌ no-auth |
| **News** | Wikipedia search (fallback) | ✅ | ❌ no-auth |
| **News alt** | [GNews](https://gnews.io) | ❌ | API key (free 100/day) |

## 🔐 Sicurezza

| Categoria | API | FOSS? | Auth |
|---|---|---|---|
| **Email breach** | [HIBP v3](https://haveibeenpwned.com/API/v3) | ❌ | API key (~$4) |
| **Password breach** | [HIBP Pwned](https://haveibeenpwned.com/Passwords) | ❌ | ❌ no-auth (k-anonymity) |
| **Vuln CVE** | [OpenCVE](https://www.opencve.io) | ✅ AGPL | Self-host |

## 🎲 Entertainment / Easter

| Categoria | API | FOSS? | Auth |
|---|---|---|---|
| Quotes | [ZenQuotes](https://zenquotes.io) | ❌ | ❌ |
| Advice | [adviceslip](https://api.adviceslip.com) | ❌ | ❌ |
| Trivia | [OpenTDB](https://opentdb.com) | ✅ | ❌ |
| Joke | [icanhazdadjoke](https://icanhazdadjoke.com) | ❌ | ❌ |
| Color | [TheColorAPI](https://www.thecolorapi.com) | ❌ | ❌ |
| QR Code | [qrserver](https://goqr.me/api) | ❌ | ❌ |
| Cat pic | [TheCatAPI](https://thecatapi.com) | ❌ | ❌ no-auth |
| Dog pic | [Dog CEO](https://dog.ceo/dog-api) | ❌ | ❌ |
| Fox pic | [randomfox.ca](https://randomfox.ca) | ❌ | ❌ |

---

## Esempi

```bash
# Meteo a Roma (Open-Meteo + Nominatim FOSS)
solem-api weather Rome

# Geocoding indirizzo
solem-api geocode "Piazza San Marco, Venezia"

# Traduzione automatica
solem-api translate "hello world" en it

# Cambio valuta
solem-api currency EUR USD 100

# Cerca su Wikipedia in italiano
solem-api wiki Pasta it

# Ingredienti dal codice a barre
solem-api food 8001505005707

# Festività italiane 2026
solem-api holidays 2026 IT

# Prezzi Bitcoin in EUR
solem-api crypto bitcoin eur

# QR code da link
solem-api qr "https://github.com/rguidotti-design/solem" out.png
```

## Per GAVIO

GAVIO può chiamare queste API come **tools** per arricchire le risposte:

```python
# Esempio Python (GAVIO backend)
import subprocess, json

def get_weather(city: str) -> dict:
    out = subprocess.check_output(["solem-api", "weather", city])
    return json.loads(out)
```

## Vantaggi vs API cloud paid

- **Costo**: 0 € per sempre
- **Privacy**: nessun account, nessun log centralizzato
- **No vendor lock-in**: tutte sostituibili
- **FOSS-first**: 6 su 22 sono FOSS pure (server open-source)
- **Self-host opzionale**: LibreTranslate, OpenCVE, Frankfurter sono self-hostabili

## Ad altre API che potrei aggiungere

Vedi [github.com/public-apis/public-apis](https://github.com/public-apis/public-apis) per:

- **Health**: USDA Food (nutrizionale), OpenFDA (farmaci)
- **Government Italy**: ISTAT, INPS, AdE (codice fiscale)
- **Astronomy**: NASA APOD, Solar System, AstronomyAPI
- **Music**: MusicBrainz (FOSS), Genius lyrics
- **Sports**: TheSportsDB (FOSS), API-Football (free tier)
- **Transit**: TransitLand, EveryPolitician
- **Cloud Storage FOSS**: Storj, Filebase
- **ML**: HuggingFace Inference (free), Replicate (free trial)

Per aggiungerle: `solem.publicApis.enable = true` + estendi `solem-api` CLI.

---

**Tutti i path passano per CLI, GAVIO può comporre risposte usando questi tool.**
