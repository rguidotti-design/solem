{ config, pkgs, lib, ... }:

# SOLEM PUBLIC APIS — CLI wrapper per ~ 20 API gratuite FOSS/no-auth.
#
# Single responsibility: SOLO installare CLI `solem-api <category> <q>` che
# wrappa API pubbliche selezionate da github.com/public-apis/public-apis.
#
# Criterio selezione (priorità):
#   1. FOSS (server open-source): LibreTranslate, Nominatim (OSM), OpenMeteo,
#      Wikipedia, OpenLibrary, OpenStreetMap, OpenFoodFacts
#   2. Free no-auth: Frankfurter (ECB), ipapi, JSONPlaceholder, Lingva,
#      Numbers API, MyMemory, Random Quotes
#   3. Free + auth (key opzionale env): HaveIBeenPwned, OpenCVE, HuggingFace
#
# Costo: 0 € (free tier o FOSS self-host).
# Utilizzo da GAVIO: tool calling per arricchire risposte.

let
  cfg = config.solem.publicApis;

  apiCli = pkgs.writeShellApplication {
    name = "solem-api";
    runtimeInputs = with pkgs; [ curl jq coreutils ];
    text = ''
      ACTION="''${1:-help}"
      shift || true

      case "$ACTION" in

        # ── METEO (OpenMeteo: FOSS, no auth) ─────────────────────────
        weather|meteo)
          CITY="''${1:-Rome}"
          # Geocode → coords (Nominatim FOSS)
          read -r LAT LON < <(curl -s "https://nominatim.openstreetmap.org/search?q=$CITY&format=json&limit=1" \
            -H "User-Agent: solem-api/0.1" | jq -r '.[0] | .lat + " " + .lon')
          curl -s "https://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&current=temperature_2m,weather_code,wind_speed_10m" | \
            jq '.current'
          ;;

        # ── GEOCODING (Nominatim OSM: FOSS) ──────────────────────────
        geocode|map)
          Q="''${1:?Usage: solem-api geocode <city/address>}"
          curl -s "https://nominatim.openstreetmap.org/search?q=$Q&format=json&limit=5" \
            -H "User-Agent: solem-api/0.1" | \
            jq '.[] | {name: .display_name, lat: .lat, lon: .lon}'
          ;;

        # ── TRADUZIONE (LibreTranslate FOSS / MyMemory free) ─────────
        translate|trad)
          TXT="''${1:?Usage: solem-api translate <text> [src=en] [dst=it]}"
          SRC="''${2:-auto}"
          DST="''${3:-it}"
          # MyMemory: 5000 chars/day senza key
          curl -s --get "https://api.mymemory.translated.net/get" \
            --data-urlencode "q=$TXT" \
            --data-urlencode "langpair=$SRC|$DST" | \
            jq -r '.responseData.translatedText'
          ;;

        # ── CURRENCY (Frankfurter: ECB, FOSS) ────────────────────────
        currency|fx|cambio)
          FROM="''${1:-EUR}"
          TO="''${2:-USD}"
          AMOUNT="''${3:-1}"
          curl -s "https://api.frankfurter.app/latest?from=$FROM&to=$TO&amount=$AMOUNT" | \
            jq "{base: .base, date: .date, rate: .rates.$TO}"
          ;;

        # ── DICTIONARY (Free Dictionary API) ─────────────────────────
        dict|dizionario)
          WORD="''${1:?Usage: solem-api dict <word> [lang=en]}"
          LANG="''${2:-en}"
          curl -s "https://api.dictionaryapi.dev/api/v2/entries/$LANG/$WORD" | \
            jq '.[0].meanings[] | {pos: .partOfSpeech, def: .definitions[0].definition}'
          ;;

        # ── WIKIPEDIA (FOSS, no auth) ────────────────────────────────
        wiki)
          Q="''${1:?Usage: solem-api wiki <topic> [lang=it]}"
          LANG="''${2:-it}"
          curl -s "https://$LANG.wikipedia.org/api/rest_v1/page/summary/$Q" | \
            jq '{title: .title, extract: .extract}'
          ;;

        # ── IP INFO (ipapi: free no auth) ────────────────────────────
        ip-info|whoami-ip)
          IP="''${1:-}"
          curl -s "https://ipapi.co/$IP/json/" | jq
          ;;

        # ── NEWS (GNews, free 100/day, opzionale GNEWS_KEY env) ──────
        news)
          Q="''${1:-italia}"
          if [ -n "''${GNEWS_KEY:-}" ]; then
            curl -s "https://gnews.io/api/v4/search?q=$Q&lang=it&apikey=$GNEWS_KEY" | \
              jq '.articles[] | {title: .title, url: .url}'
          else
            # Fallback: Wikipedia search (FOSS)
            curl -s "https://it.wikipedia.org/w/api.php?action=opensearch&search=$Q&limit=5&format=json" | jq
          fi
          ;;

        # ── BOOKS (OpenLibrary: FOSS) ────────────────────────────────
        books|libri)
          Q="''${1:?Usage: solem-api books <query>}"
          curl -s "https://openlibrary.org/search.json?q=$Q&limit=5" | \
            jq '.docs[] | {title: .title, author: .author_name, year: .first_publish_year}'
          ;;

        # ── FOOD (OpenFoodFacts: FOSS) ───────────────────────────────
        food|cibo)
          BARCODE="''${1:?Usage: solem-api food <EAN-barcode>}"
          curl -s "https://world.openfoodfacts.org/api/v0/product/$BARCODE.json" | \
            jq '.product | {name: .product_name, brand: .brands, nutriscore: .nutriscore_grade}'
          ;;

        # ── HAVE-I-BEEN-PWNED (free no auth) ─────────────────────────
        breach|hibp)
          EMAIL="''${1:?Usage: solem-api breach <email>}"
          # HIBP richiede chiave per email check; per password sha1 OK senza
          if [ -n "''${HIBP_KEY:-}" ]; then
            curl -s -H "hibp-api-key: $HIBP_KEY" \
              "https://haveibeenpwned.com/api/v3/breachedaccount/$EMAIL" | jq
          else
            echo "HIBP email check richiede HIBP_KEY env."
            echo "Free alternative: scarica DB locale da https://haveibeenpwned.com/Passwords"
          fi
          ;;

        # ── PUBLIC HOLIDAYS (Nager.Date: free no auth) ────────────────
        holidays|festivita)
          YEAR="''${1:-$(date +%Y)}"
          CC="''${2:-IT}"
          curl -s "https://date.nager.at/api/v3/PublicHolidays/$YEAR/$CC" | \
            jq '.[] | {date: .date, name: .name, local: .localName}'
          ;;

        # ── COUNTRY INFO (restcountries: free no auth) ───────────────
        country|paese)
          NAME="''${1:?Usage: solem-api country <name>}"
          curl -s "https://restcountries.com/v3.1/name/$NAME" | \
            jq '.[0] | {name: .name.common, capital: .capital[0], pop: .population, region: .region}'
          ;;

        # ── CAT/DOG/FOX (entertainment) ──────────────────────────────
        cat) curl -s "https://api.thecatapi.com/v1/images/search" | jq '.[0].url' ;;
        dog) curl -s "https://dog.ceo/api/breeds/image/random" | jq -r '.message' ;;
        fox) curl -s "https://randomfox.ca/floof/" | jq -r '.image' ;;

        # ── QUOTES (zenquotes: free no auth) ─────────────────────────
        quote|citazione)
          curl -s "https://zenquotes.io/api/random" | jq '.[0] | {q: .q, a: .a}'
          ;;

        # ── ADVICE (adviceslip: free no auth) ────────────────────────
        advice|consiglio)
          curl -s "https://api.adviceslip.com/advice" | jq '.slip.advice'
          ;;

        # ── NUMBERS FACT (numbersapi: free no auth) ──────────────────
        number|numero)
          N="''${1:-$RANDOM}"
          curl -s "http://numbersapi.com/$N/trivia"
          echo
          ;;

        # ── TRIVIA (OpenTDB: free no auth) ───────────────────────────
        trivia)
          CAT="''${1:-9}"  # 9 = General Knowledge
          curl -s "https://opentdb.com/api.php?amount=1&category=$CAT&type=multiple" | \
            jq '.results[0] | {q: .question, a: .correct_answer}'
          ;;

        # ── JOKE (icanhazdadjoke: free no auth) ──────────────────────
        joke|barzelletta)
          curl -s -H "Accept: text/plain" "https://icanhazdadjoke.com/"
          echo
          ;;

        # ── COLOR (TheColorAPI: free no auth) ────────────────────────
        color|colore)
          HEX="''${1:?Usage: solem-api color <hex e.g. ff5733>}"
          curl -s "https://www.thecolorapi.com/id?hex=$HEX" | \
            jq '{hex: .hex.value, rgb: .rgb.value, name: .name.value}'
          ;;

        # ── QR CODE (qrserver: free no auth) ─────────────────────────
        qr)
          DATA="''${1:?Usage: solem-api qr <text> [out=qr.png]}"
          OUT="''${2:-qr.png}"
          curl -s --get "https://api.qrserver.com/v1/create-qr-code/" \
            --data-urlencode "data=$DATA" --data-urlencode "size=300x300" -o "$OUT"
          echo "QR salvato in: $OUT"
          ;;

        # ── CRYPTO PRICES (CoinGecko: free no auth) ──────────────────
        crypto|btc)
          COIN="''${1:-bitcoin}"
          VS="''${2:-eur}"
          curl -s "https://api.coingecko.com/api/v3/simple/price?ids=$COIN&vs_currencies=$VS" | jq
          ;;

        # ─────────────────────────────────────────────────────────────
        # EXTRA APIs (14 nuove, tutte free no-auth)
        # ─────────────────────────────────────────────────────────────

        # ── NASA APOD ────────────────────────────────────────────────
        nasa|apod)
          curl -s "https://api.nasa.gov/planetary/apod?api_key=DEMO_KEY" | \
            jq '{title: .title, url: .url, date: .date}'
          ;;

        # ── ISS position ─────────────────────────────────────────────
        iss)
          curl -s "http://api.open-notify.org/iss-now.json" | jq
          ;;

        # ── People in space ──────────────────────────────────────────
        space|astronauts)
          curl -s "http://api.open-notify.org/astros.json" | jq
          ;;

        # ── Country flag download ────────────────────────────────────
        flag)
          CODE="''${1:?Usage: solem-api flag <iso-2-code>}"
          OUT="''${2:-flag-$CODE.png}"
          curl -s "https://flagcdn.com/w320/$CODE.png" -o "$OUT"
          echo "Flag salvato: $OUT"
          ;;

        # ── Time zone ────────────────────────────────────────────────
        time|orario)
          TZ="''${1:-Europe/Rome}"
          curl -s "https://worldtimeapi.org/api/timezone/$TZ" | \
            jq '{datetime: .datetime, timezone: .timezone, utc_offset: .utc_offset}'
          ;;

        # ── DuckDuckGo instant search ────────────────────────────────
        search|cerca)
          Q="''${1:?Usage: solem-api search <query>}"
          curl -s --get "https://api.duckduckgo.com/" \
            --data-urlencode "q=$Q" --data "format=json" --data "no_html=1" | \
            jq '{abstract: .AbstractText, source: .AbstractSource, url: .AbstractURL}'
          ;;

        # ── HTTP cat (fun) ───────────────────────────────────────────
        http-cat)
          CODE="''${1:-200}"
          OUT="''${2:-http-$CODE.jpg}"
          curl -s "https://http.cat/$CODE" -o "$OUT"
          echo "HTTP $CODE cat: $OUT"
          ;;

        # ── Pokemon ──────────────────────────────────────────────────
        pokemon)
          NAME="''${1:?Usage: solem-api pokemon <name>}"
          curl -s "https://pokeapi.co/api/v2/pokemon/$NAME" | \
            jq '{name: .name, height: .height, weight: .weight, types: [.types[].type.name]}'
          ;;

        # ── MusicBrainz (FOSS) ───────────────────────────────────────
        artist|music)
          Q="''${1:?Usage: solem-api artist <name>}"
          curl -s --get "https://musicbrainz.org/ws/2/artist" \
            -H "User-Agent: solem-api/0.1" \
            --data-urlencode "query=$Q" --data "fmt=json" --data "limit=3" | \
            jq '.artists[] | {name: .name, country: .country, type: .type}'
          ;;

        # ── GitHub user (free no auth) ───────────────────────────────
        github|gh-user)
          USER="''${1:?Usage: solem-api github <username>}"
          curl -s "https://api.github.com/users/$USER" | \
            jq '{login: .login, name: .name, bio: .bio, public_repos: .public_repos, followers: .followers}'
          ;;

        # ── HuggingFace search (free no auth) ────────────────────────
        hf|huggingface)
          Q="''${1:?Usage: solem-api hf <model-keyword>}"
          curl -s "https://huggingface.co/api/models?search=$Q&limit=5" | \
            jq '.[] | {id: .id, downloads: .downloads}'
          ;;

        # ── Public IP (ipify) ────────────────────────────────────────
        myip)
          curl -s "https://api.ipify.org?format=json" | jq -r '.ip'
          ;;

        # ── URL shortener (is.gd) ────────────────────────────────────
        shorten|short)
          URL="''${1:?Usage: solem-api shorten <url>}"
          curl -s --get "https://is.gd/create.php" \
            --data-urlencode "url=$URL" --data "format=simple"
          echo
          ;;

        # ── Sunrise / Sunset ─────────────────────────────────────────
        sun|sunrise)
          LAT="''${1:-41.9028}"
          LON="''${2:-12.4964}"
          curl -s "https://api.sunrise-sunset.org/json?lat=$LAT&lng=$LON&formatted=0" | \
            jq '.results | {sunrise: .sunrise, sunset: .sunset, day_length: .day_length}'
          ;;

        # ── HELP ────────────────────────────────────────────────────
        help|--help|-h|*)
          cat <<'HELP'
solem-api — 22 API gratuite FOSS/no-auth

  Meteo:        solem-api weather Rome
  Geocoding:    solem-api geocode "Piazza Duomo, Milano"
  Traduzione:   solem-api translate "hello" en it
  Currency:     solem-api currency EUR USD 100
  Dizionario:   solem-api dict serendipity en
  Wikipedia:    solem-api wiki Pasta it
  IP info:      solem-api ip-info               (tuo IP)
  News:         solem-api news italia
  Libri:        solem-api books "il piccolo principe"
  Cibo:         solem-api food 8001505005707    (Nutella)
  Festività:    solem-api holidays 2026 IT
  Paesi:        solem-api country italy
  HIBP:         solem-api breach email@x.com    (richiede HIBP_KEY)
  Crypto:       solem-api crypto bitcoin eur
  Quotes:       solem-api quote
  Advice:       solem-api advice
  Numbers:      solem-api number 42
  Trivia:       solem-api trivia
  Joke:         solem-api joke
  Color:        solem-api color ff5733
  QR code:      solem-api qr "https://solem.org" out.png
  Animali:      solem-api cat | dog | fox

EXTRA (14 nuove):
  NASA APOD:    solem-api nasa                  immagine astronomica giorno
  ISS:          solem-api iss                   posizione International Space Station
  Astronauti:   solem-api space                 chi è ora in orbita
  Bandiera:     solem-api flag it               scarica bandiera Italia
  Orario:       solem-api time Europe/Rome      ora corrente fuso
  Cerca:        solem-api search "topic"        DuckDuckGo instant
  HTTP cat:     solem-api http-cat 404          immagine HTTP status
  Pokemon:      solem-api pokemon pikachu
  Musica:       solem-api artist Beatles
  GitHub:       solem-api github torvalds
  HF model:     solem-api hf bert
  Mio IP:       solem-api myip
  Short URL:    solem-api shorten <url>
  Alba/Tram.:   solem-api sun [lat] [lon]

Totale: 36 endpoint FOSS o free-tier no-auth. 0 €.
Documentazione: docs/PUBLIC-APIS.md
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.publicApis = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa CLI `solem-api` (wrapper 36 API gratuite FOSS/no-auth)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ apiCli ];
  };
}
