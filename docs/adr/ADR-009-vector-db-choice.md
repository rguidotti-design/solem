# ADR-009 — Vector DB embedded: LanceDB

**Status**: Accettato
**Data**: 2026-05-17

## Contesto

Prompt Master v4.0 sez. 2.4 + 4.5 richiede vector DB embedded per: filesystem semantico, memoria L1-L3, embedding cache GAVIO. ADR-006 e roadmap M1.2 menzionano "qdrant/lancedb/chroma → ADR-009".

## Opzioni considerate

| Engine | Pro | Contro |
|--------|-----|--------|
| **qdrant** | Production-grade, REST + gRPC API, filtering avanzato | Richiede process server separato (overhead) |
| **chroma** | Pythonic, embedded mode, popolare | Performance limitata su grandi dataset, file format proprietario |
| **lancedb** | **Embedded vero** (no server), columnar storage Arrow, multi-modale, zero-copy reads, scale lineare | Più giovane (2023+), community più piccola |
| **sqlite-vss** | Già abbiamo SQLite | Limitato (no filtering avanzato, no multi-modal) |

## Decisione: **LanceDB**

Motivi:
1. **Embedded vero**: zero server process, libreria Python. SOLEM resta single-binary architecture.
2. **Columnar Apache Arrow**: zero-copy con `polars` (già nelle creator deps), `pyarrow`, NumPy
3. **Scale lineare**: testato fino a milioni di vettori senza degradazione
4. **Multi-modale**: support nativo per testo + immagini + audio embeddings (utile per L5 universe memory `photo`)
5. **File on-disk** standard: lance format aperto, esportabile, audit-able
6. **FOSS**: Apache 2.0
7. **Storage**: directory `/var/lib/gavio/memory/lance/` con table per topic (es. `chat`, `documents`, `code`)

## Conseguenze

**Positive**:
- Niente overhead servizio separato
- Polars/Arrow integration nativa (data layer creator già attivo)
- Single source di verità (file on-disk versionabile + backup automatico)

**Negative**:
- Community più piccola di Qdrant (mitigato da: API stabile, Apache 2, fork-able)
- Versionato meno stabile → pin versione esatta in `nixos/modules/gavio.nix`

## Implementazione

- M1.2: pacchetto `python312Packages.lancedb` aggiunto in `gavio.nix` (system Python deps)
- Path: `/var/lib/gavio/memory/lance/<table>/` con permessi 0700 gavio:users
- Modulo Python wrapper in `backend/solem_api/layers/vector_store.py` per astrarre LanceDB → permette future migrazione a Qdrant/Chroma senza cambiare client code (Open/Closed)

## Alternative scartate per ora

- **Qdrant**: ottimo ma richiede processo server, lo riconsidereremo Step 4+ se serve scaling multi-utente
- **Chroma**: file format proprietario, performance limitata
- **sqlite-vss**: troppo limitato

Riferimento: <https://lancedb.com> · GitHub `lancedb/lancedb` · Apache 2.0
