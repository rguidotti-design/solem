# SOLEM — Architettura

## Modello mentale

```
        UTENTE
           │
           ▼
        GAVIO  ← AI primaria, sempre presente
       ╱  │  ╲
      ╱   │   ╲
     ▼    ▼    ▼
   AI    AI    AI       AI specialiste (Step 3+)
   Mec   Leg   Fin
   ▲     ▲     ▲
   │     │     │
   └─────┴─────┘
   tutte accedono a Identity, Context, Memory, Capabilities
   coordinate via Event Bus
```

GAVIO è l'unica AI primaria. Le specialiste arriveranno in Step 3 (legale,
medica, meccanica, finanziaria) e saranno invocate da GAVIO.

---

## Come SOLEM ospita GAVIO (Step 0)

```
┌─────────────────────────────────────────────────────────┐
│ SOLEM (NixOS host)                                      │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ systemd                                             │ │
│ │  ├─ gavio.service       → uvicorn server:app :8000  │ │
│ │  ├─ ollama.service      → llama3.2 locale  :11434   │ │
│ │  ├─ docker.service      → sandbox (opzionale)       │ │
│ │  └─ sshd.service        → accesso remoto   :22      │ │
│ └─────────────────────────────────────────────────────┘ │
│                                                         │
│ Filesystem:                                             │
│  /opt/gavio              ← codice GAVIO (9p shared FS)  │
│  /var/lib/gavio/venv     ← venv Python                  │
│  /var/lib/gavio/data     ← stato persistente            │
│  /etc/gavio/env          ← API key & config             │
│  /var/lib/solem/         ← stato L1-L7 (futuro)         │
└─────────────────────────────────────────────────────────┘
```

L'utente accede a SOLEM in 3 modi:
- **Web GAVIO**: `http://localhost:8000` (frontend esistente)
- **SSH**: `ssh -p 2222 gavio@localhost`
- **Console seriale VM** (debug, lanciando con `nix run .#vm`)

---

## I 7 Layer SOLEM

Architettura target. Step 0 = scheletro, dettagli in spec founder.

| Layer | Nome | Step 0 | Step target |
|-------|------|--------|-------------|
| L1 | Identity Engine | stub (vive in KAIROS) | Step 2 — modulo Python dedicato |
| L2 | Context Engine | stub | Step 2 — snapshot ogni 5min |
| L3 | Orchestration + Event Bus | parziale (orchestrator.py in GAVIO) | Step 2 — Redis/NATS bus |
| L4 | Capabilities Pool | parziale (9 nodi GAVIO) | Step 2 — manifest standard |
| L5 | Memory & Knowledge | parziale (memory.py + wiki.py) | Step 3 — 3 livelli completi |
| L6 | Interop / External | stub | Step 3 — email, calendar, IoT |
| L7 | Extensions Marketplace | stub | Step 4 — plugin loader + sandbox |

**Sigillo del Core:** L1-L6 sono SOLEM Core (modifiche controllate dal founder).
L7 è l'unico layer "aperto" alle estensioni di terze parti.

---

## Stack tecnico (non discutibile)

| Componente | Tecnologia |
|------------|------------|
| OS | NixOS 24.11 (dichiarativo via flake) |
| Container | Docker |
| Backend | Python 3.12+, FastAPI, asyncio, Pydantic v2 |
| Frontend | TypeScript + React 18 + Tailwind, Vite, PWA |
| DB | Supabase (Postgres 16 + pgvector + Auth + Realtime + RLS) |
| LLM | wrapper multi-provider (Claude / Groq / Gemini / Ollama locale) |
| VPN | WireGuard (puro, dopo Step 0) |
| Auth | Supabase Auth + magic link + JWT |
| Crypto messaging | AES-256-GCM Day 1 → Signal Protocol Step 3 |
| Vector DB | pgvector Anno 1 → Qdrant Anno 2+ |

---

## Multi-tenant by design (anche se uno solo)

Nonostante Step 0 abbia 1 utente, le seguenti regole sono **già rispettate**:

1. Ogni tabella DB futura → colonna `user_id` (UUID) + RLS attiva
2. Identity sempre per-utente, mai globale
3. Capabilities stateless con `user_id` parametro
4. Ogni query filtrata per `user_id`
5. GAVIO è "istanza per-utente" concettualmente

L'attivazione del multi-tenant (Step 4) sarà solo accendere RLS pubblica e
aggiungere route auth — non un refactoring.

---

## AI-First API design

Ogni endpoint esposto da SOLEM/GAVIO segue questi vincoli:

- Output **sempre** JSON/Pydantic strutturato (mai stringhe libere)
- Errori machine-readable con codici precisi
- Streaming SSE nativo per output lunghi
- OpenAPI completo (per autodiscovery da parte di altre AI)
- Tool calling format compatibile OpenAI/Anthropic
- Idempotency keys su write
- Pagination cursor-based
- Filtering/sorting via query params standard

---

## Roadmap di costruzione

| Step | Periodo | Cosa arriva |
|------|---------|-------------|
| 0 | Mag-Giu 2026 | **OS scaffold + VM testabile, GAVIO come servizio** ← OGGI |
| 1 | Est-Aut 2026 | Beelink mini-PC, NixOS bare-metal, primi container Docker |
| 2 | Inv 2026/27 | L1+L2+L3 estratti come moduli, messaging E2E base, memoria livello A |
| 3 | 2027 | Memoria B+C, Jetson AI locale, device targeting, beta 3-5 utenti, prima AI specialista |
| 4 | 2028 | Multi-tenancy pubblica self-host (sempre gratis), brand, Extensions v1 |
| 5 | 2029+ | Distro custom consolidata, guide hardware, mobile PWA — sempre 100% gratis self-host |

Regola d'oro: **ogni step si apre solo dopo 30 giorni di uso reale del precedente**.
