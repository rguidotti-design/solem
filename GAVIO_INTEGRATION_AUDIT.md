# GAVIO — Integration Audit (Fase 0, Prompt Master v4.0)

**Data**: 2026-05-17
**Auditor**: assistente di sistema (per direttiva utente)
**Repo GAVIO**: `c:\Users\guido\Desktop\gavio\` (locale + GitHub `rguidotti-design/gavio` con CI Actions)

---

## 1. Cos'è GAVIO (stato osservato dal codice + README)

> *Assistente personale gerarchico multi-agente. FastAPI + Supabase + Groq Llama + frontend HTML+PWA. Italiano-first, IT/EN/ES/FR i18n, deploy zero-budget (Tailscale Funnel).*

### 1.1 Stack runtime
- **Backend**: Python 3.12, FastAPI + uvicorn, async
- **Entrypoint**: `server.py` (HTTPS self-signed opzionale via `GAVIO_HTTPS`)
- **Porte**: 8000 (HTTP/HTTPS)
- **DB**: Supabase cloud (Postgres + pgvector + Auth + Storage) — free tier
- **LLM cloud**: Groq Llama 3.3 70B (free tier ~14K req/giorno, no carta)
- **LLM locale**: Ollama (`OLLAMA_HOST`)
- **Frontend**: HTML + JS vanilla + PWA (service worker), brand serif bordeaux/nero (oggi separato dal navy di SOLEM)
- **Deploy storico**: Tailscale Funnel (free tier) — `gavio.tail72feef.ts.net`

### 1.2 Inventario file
- **162 file Python top-level** (logica nodi/utility)
- **47 file Python in `api/`** (router FastAPI)
- **Frontend**: `static/` con `index.html`, `admin.html`, `manifest.webmanifest`, `sw.js`, `icons/`, `models/`
- **Pyproject**: `pyproject.toml` minimal (solo pytest+coverage config)
- **Requirements**: `requirements.txt` con vere deps top-level

### 1.3 Architettura (ricostruita dai nomi file)

**Orchestrator + nodi** (dalla spec founder originaria — 9 nodi):
- `orchestrator.py` — orchestrator centrale (entrypoint logica)
- Nodi: `health`, `finance`, `growth`, `lifestyle`, `messaging`, `file`, `wiki`, `system`, `extra`

**Capability moduli** (oltre 100 file Python rilevati):
- `identity.py` — Identity Engine (sezioni utente)
- `memory.py` — memoria
- `wiki.py` — wiki utente
- `auth.py`, `safety.py`, `evals.py`, `self_improve.py`
- `pc_actions.py` / `system_control.py` — controllo PC
- `browser_tools.py` / `browser_automation.py` — Playwright Chromium
- `coding.py` / `coding_agent.py` / `code_intel_advanced.py` / `code_reviewer.py` / `code_runner.py`
- `agent_team.py` / `agent_tools.py` / `coding_intel.py`
- `media_ops.py` (rinominato da `actions_files.py`)
- `auto_summary.py`, `auto_pipeline.py`, `chat_archive.py`
- `brain_neural.py` (?), `bias_detector.py`, `circuit_breaker.py`
- `business_intel.py`, `calendar_awareness.py`
- `cli/gavio.py` — CLI utente
- + decine di altri moduli per growth/health/lifestyle/messaging…

**API routes** (47 router in `api/`):
- Admin: `admin_ai.py`, `admin_dev.py`, `admin_intel.py`, `admin_llm.py`, `admin_misc.py`, `admin_ops.py`, `admin_pc.py`
- Capability execution: `exec_agents.py`, `exec_media.py`, `exec_misc.py`, `exec_pc.py`
- Domain: `coach.py`, `goals.py`, `plans.py`, `reminders.py`, `notes.py`, `pages.py`
- Memory/Knowledge: `kb.py`, `kg.py`, `memory.py`, `wiki.py`, `learn.py`, `summaries.py`, `insights.py`
- Personal: `charter.py`, `me.py`, `feedback.py`
- Integration: `google.py`, `messaging.py`, `push.py`
- Tools: `browser.py`, `pc.py`, `pc_legacy.py`, `files.py`, `artifacts.py`
- Security/auth: `auth.py`-equivalent, `gdpr.py`, `security.py`, `sessions.py`
- Misc: `mcp.py` ← **già usa Model Context Protocol** ✅
- Frontend: `frontend.py`, `pages.py`

### 1.4 LLM provider supportati (audit memoria pre-sessione)
- Default: `auto` (router intelligente)
- Disponibili: `ollama`, `groq`, `local`, `hub`, `together`, `openrouter`, `mistral`, `cerebras`, `gemini`, `github`, `sambanova`, `deepinfra`, `cloudflare`, `claude_code`
- **Per direttiva utente "solo gratis"**: di default si usa solo Ollama + Groq free tier; gli altri restano disponibili come fallback opzionale ma non incoraggiati

### 1.5 Capabilities di sistema (dipendenze native)
- Tesseract OCR (`pytesseract`)
- FFmpeg (`faster-whisper` STT)
- Playwright Chromium (browser automation)
- Docker (sandbox `/sandbox/exec` opt-in via `GAVIO_ENABLE_DOCKER`)
- Tailscale CLI (tunnel watchdog) — sostituibile con WireGuard self-host SOLEM
- pyautogui/pyperclip (computer use)
- pywebpush / edge-tts

### 1.6 Storage state
- Workspace dir `workspace/` con: `dataset/` (continual learning), `artifacts/`, `browser_screenshots/`, `computer_use/`, `wiki-founder/`, `vector_memory.db`
- `~/.certifi/` per cert self-signed

---

## 2. Punti di contatto SOLEM × GAVIO (oggi)

### 2.1 Attivi
- **GAVIO gira come `gavio.service`** systemd in SOLEM con bootstrap venv automatico (uv)
- **9p shared mount**: codice GAVIO su host visto da VM in `/opt/gavio` — modifiche live
- **Ollama nativo** in SOLEM serve sia GAVIO sia gli specialisti AI registrati in `agents.py`
- **SOLEM API auto-discovery**: `/solem/capabilities` legge GAVIO `/openapi.json` e genera capability `gavio.<op_id>` per ogni endpoint
- **GAVIO agent registrato** in SOLEM `agents` DB come primary AI con `endpoint=http://127.0.0.1:8000`
- **`/etc/gavio/env`** gestito da SOLEM con permessi 0600 + env file systemd

### 2.2 Pianificati ma non implementati
- IPC ring buffer shared memory (oggi: solo HTTP REST tra SOLEM↔GAVIO)
- Capability declarative Nix `gavio.capabilities = {...}` con approval-on-first-use
- Event bus L3 bidirezionale (GAVIO non publish ancora su `/solem/events`)
- Memoria L5 condivisa (oggi GAVIO ha sua memoria, SOLEM ha sua `solem_memory`)
- MCP tool registry (GAVIO ha `api/mcp.py` ma SOLEM non lo consuma ancora)
- Constitutional layer
- Kill switch hotkey desktop

### 2.3 Conflitti architetturali da risolvere

| Argomento | GAVIO oggi | SOLEM v4.0 target | Decisione richiesta |
|-----------|-----------|--------------------|---------------------|
| **Storage memoria** | Supabase cloud + `vector_memory.db` SQLite locale opt | SOLEM `/var/lib/gavio/memory/` + qdrant/lancedb embedded | Migrare GAVIO a SOLEM storage o lasciare Supabase free tier come opzione? |
| **DB Auth** | Supabase Auth | SOLEM `users.py` + sessions JWT | Unificare? |
| **Branding UI** | Serif bordeaux/nero | Navy + oro (SOLEM) | GAVIO mantiene sua palette o si allinea a SOLEM navy? |
| **Frontend** | Static HTML+PWA proprio | SOLEM dashboard | Coesistono (porte diverse) o unificare? |
| **CLI** | `cli/gavio.py` proprio | SOLEM `solem` CLI | Coesistono come 2 binari distinti |
| **MCP** | `api/mcp.py` GAVIO | SOLEM Tool registry v4.0 | GAVIO MCP diventa fonte autorevole, SOLEM lo proxy |
| **Computer use** | `pc_actions.py`/`computer_use.py` | SOLEM semantic UI AT-SPI | Sovrapposizione: GAVIO usa screen-grab+pyautogui, SOLEM target è AT-SPI native |
| **Tailscale** | Deploy Tailscale Funnel | SOLEM mesh WireGuard self-host | GAVIO dismette Tailscale quando SOLEM bare-metal + dominio Let's Encrypt? |

---

## 3. Capacità GAVIO che richiedono supporto specifico SOLEM v4.0

| Capacità GAVIO | Supporto SOLEM richiesto | Stato |
|----------------|--------------------------|-------|
| Computer use (`pc_actions.py`, `pyautogui`) | Wayland compositor + `ydotool` o AT-SPI semantic UI | ❌ |
| Browser automation (Playwright Chromium) | Chromium nativo + display server | 🟡 (pacchetto Chromium c'è, manca display headless config) |
| Voice STT (`faster-whisper`) | whisper.cpp nativo SOLEM | ❌ |
| Voice TTS (`edge-tts`) | piper TTS locale | ❌ (edge-tts richiede internet) |
| Audit + GDPR (`gdpr.py`) | Event bus L3 immutable append-only firmato | 🟡 (event bus c'è, manca firma cryptografica) |
| MCP tools | SOLEM proxy MCP + sandboxing tools | ❌ |
| Continual learning (`workspace/dataset/`) | Pipeline LoRA/QLoRA locale, GPU access | ❌ |
| Multi-device sync | WireGuard mesh + CRDT (yjs/automerge) | 🟡 (mesh stub, CRDT no) |
| Self-improvement (`self_improve.py`) | Fine-tuning pipeline locale + A/B testing infra | ❌ |
| Constitutional rules (safety.py + evals.py) | SOLEM constitutional layer system-wide | ❌ |
| Auto-summary (`auto_summary.py`) cron | systemd timer | ✅ (model pattern già usato per backup/context) |

---

## 4. Domande aperte all'utente (Ruben Guidotti)

Per finalizzare l'audit di GAVIO e l'integrazione:

1. **Stato sviluppo GAVIO**: quali aree sono **stable**, **WIP**, o **solo design**? Vorrei `MIGRATIONS.md` e `MODULES_INTEGRATION.md` letti per capirlo meglio (li ho visti ma non li ho riassunti qui).

2. **Modelli LLM target**: oggi GAVIO supporta 14 provider. La direttiva "solo gratis" implica:
   - Default = Ollama locale + Groq free tier ✅
   - Rimuoviamo provider paid dal codice GAVIO oppure li lasciamo opzionali con label "ATTENZIONE: a pagamento, sconsigliato"?

3. **Hardware target GAVIO**: oggi gira su tuo portatile + GitHub Actions free CI. Per Step 1 bare-metal Beelink → vuoi che GAVIO migri completamente sul Beelink o resti sul portatile con sync verso Beelink?

4. **Supabase free tier** è OK come direttiva "solo gratis"? (500MB DB + 50K users senza carta) Oppure preferisci self-host **Postgres + Authentik** dentro SOLEM?

5. **Tailscale Funnel sostituibile?** Per "solo coding + self-host" la roadmap dovrebbe sostituire Tailscale Funnel con: dominio `.local` mDNS in LAN, **WireGuard mesh SOLEM** + reverse proxy Caddy con cert self-signed o Let's Encrypt (gratuito). Quando vuoi pianificare la transizione?

6. **Constitutional rules GAVIO**: chi le definisce? Sono in `safety.py`? Vuoi che SOLEM le importi/proxy o resta tutto in GAVIO?

7. **Computer use vs Semantic UI**: GAVIO oggi usa pyautogui/screenshot. v4.0 vuole AT-SPI nativo. **Priorità Step 2** (quando arriva desktop Hyprland in SOLEM)?

8. **GAVIO frontend brand**: la palette bordeaux/serif di GAVIO oggi è separata dal navy di SOLEM. Riallinei GAVIO al navy o tieni i due branding distinti per non confondere?

9. **Identità GAVIO**: oggi è in `identity.py` GAVIO. SOLEM ha L1 Identity Engine con sezioni standard (roles/values/goals/routine/persone). **Step 2**: una delle due Identity diventa autoritativa, l'altra proxy. Quale?

10. **MCP server**: `api/mcp.py` di GAVIO espone un MCP server? Quali tool sono dichiarati? Posso leggere il file se mi confermi.

---

## 5. Sintesi

**GAVIO è il cervello già funzionante e maturo** (162 file Python, 47 router API, frontend PWA, multi-LLM, MCP, computer use).

**SOLEM è il corpo nuovo** che ospita GAVIO come "organo principale". Oggi i punti di contatto sono minimi (HTTP REST + 9p mount + auto-discovery OpenAPI). Per il target v4.0 "cittadino di prima classe" servono:

- IPC nativo (shared memory ring buffer)
- Capability Nix-declarative con approval-on-first-use
- Event bus bidirezionale L3
- Semantic UI AT-SPI
- Constitutional layer
- Kill switch
- Storage unificato `/var/lib/gavio/` strutturato

La roadmap di co-evoluzione è in [INTEGRATION_ROADMAP.md](INTEGRATION_ROADMAP.md).
