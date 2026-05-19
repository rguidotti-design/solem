# SOLEM × GAVIO — Integration Roadmap (Fase 0, Prompt Master v4.0)

**Data**: 2026-05-17
**Vincoli**: 100% gratuito, FOSS only, on-device first, self-host

---

## Premesse

Questa roadmap deriva dal **Prompt Master v4.0** + audit di SOLEM Step 0 (vedi [SOLEM_AUDIT_REPORT.md](SOLEM_AUDIT_REPORT.md)) + audit GAVIO (vedi [GAVIO_INTEGRATION_AUDIT.md](GAVIO_INTEGRATION_AUDIT.md)).

Allinea le **Milestone M0-M6** del Prompt Master con la roadmap esistente Step 0-5+ di SOLEM. **Sostituisce** la sezione Step 1-5+ di `ROADMAP.md` precedente (ROADMAP.md viene aggiornato in coda all'approvazione di questo documento).

**Tutto il lavoro è solo coding. Nessuna spesa monetaria.**

---

## Orizzonte 90 giorni — Mesi 1-3 (Giu-Ago 2026)

### Milestone 0 — Audit e foundations (Mese 1, Giugno 2026) ✅ CHIUSO 2026-05-17

- [x] **Audit Fase 0 approvato** (3 documenti + 18 risposte utente)
- [x] **ADR-001** — NixOS 24.11 stable + overlay unstable selettivo
- [x] **ADR-002** — Rust: nuovo critical-path by default, esistente Python resta
- [x] **ADR-003** — bcachefs Step 1 Beelink, ext4 VM test + script test anticipato
- [x] **ADR-004** — Supabase free + script `pg_dump` da OGGI per export rodato
- [x] **ADR-005** — Tailscale Funnel RESTA (opposta a default originale)
- [x] **ADR-006** — Constitutional triple-defense (Nix + SOLEM gateway + GAVIO enforcer)
- [x] **ADR-007** — HAL AI skeleton ora, driver Step 3 con Jetson
- [x] **ADR-008** — GAVIO sul Beelink single source, portatile client mesh

**Decisioni utente che modificano la roadmap originale**:

- **Tailscale resta** → rimuovo da Step 1 transizione WG+Caddy+LE
- **Export `pg_dump` Supabase** → aggiunto a M1.2 come immediate task
- **PoC AT-SPI su 1 app già durante Step 1** (originalmente solo Step 2)
- **systemd dependency `After=solem-identity.service`** in `gavio.service` (M1.3)
- **bcachefs test script in VM da subito** (M1.2)
- **HAL skeleton da subito** (M1.2)

### Milestone 1.1 — systemd hardening (Mese 2, Luglio 2026)

Risolve debito tecnico più urgente: Prompt Master v4.0 sez. 1.2.

- [ ] Hardening `gavio.service`:
  - `NoNewPrivileges=true`
  - `ProtectSystem=strict` con `ReadWritePaths=/var/lib/gavio /var/log/gavio`
  - `ProtectHome=tmpfs` (tranne se necessario)
  - `PrivateDevices=true` (eccetto se computer-use attivo)
  - `ProtectKernelTunables=true` + `ProtectKernelModules=true` + `ProtectControlGroups=true`
  - `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6`
  - `LockPersonality=true`, `RestrictRealtime=true`
  - `SystemCallFilter=@system-service`, `SystemCallErrorNumber=EPERM`
  - `MemoryDenyWriteExecute=true` (verificare compat con Python JIT)
- [ ] Hardening `solem-api.service`, `solem-keep.service` con stesso set
- [ ] **NB importante**: bilanciare con `ai-freedom.nix` — l'AI deve restare libera, hardening protegge il sistema **dall'esterno** non dall'AI stessa
- [ ] Documentare in `docs/HARDENING.md` perché ogni opzione è giustificata

### Milestone 1.2 — `/var/lib/gavio/` strutturato (Mese 2-3)

Allineamento a Prompt Master sez. 2.3.

- [ ] `/var/lib/gavio/models/` — gestiti via Nix (download script, hash-locked, content-addressable)
- [ ] `/var/lib/gavio/memory/` — vector DB embedded (decisione: **qdrant** vs **lancedb** vs **chroma** → ADR-006)
- [ ] `/var/lib/gavio/cache/` — KV-cache persistente cross-session
- [ ] `/var/lib/gavio/audit/` — log immutabile append-only **firmato cryptograficamente** (ed25519)
- [ ] `/var/lib/gavio/state/` — stato conversazionale, contesti
- [ ] Encryption-at-rest opt-in (LUKS è sufficiente bare-metal Step 1)
- [ ] Snapshot automatici di `memory/` ogni 6h → integrato in `solem-backup.nix`

### Milestone 1.3 — Capability Nix-declarative (Mese 3)

Allineamento a Prompt Master sez. 4.6.

- [ ] Definire schema Nix:
  ```nix
  gavio.capabilities = {
    filesystem.read = [ "/home/gavio/Documents" ];
    filesystem.write = [ "/home/gavio/Documents/gavio-output" ];
    network.outbound = [ "api.example.com" ];
    execute = [ "python" "git" "ffmpeg" ];
    ui.observe = true;
    ui.act = false;
  };
  ```
- [ ] Generare da Nix → file `/etc/gavio/capabilities.json` letto da GAVIO al boot
- [ ] **Approval-on-first-use**: GAVIO chiede consenso utente alla prima invocazione, salva in `/var/lib/gavio/state/granted_caps.json`
- [ ] CLI `solem` aggiunge subcomando `solem caps grant/revoke <cap>`
- [ ] Endpoint API `/solem/capabilities/grants/{user_id}` per audit

---

## Orizzonte 6 mesi — Mesi 4-6 (Set-Nov 2026)

### Milestone 2 — Semantic UI + IPC + Voice (PROMPT v4.0 Milestone 2)

#### M2.1 — IPC nativo SOLEM ↔ GAVIO

Sostituisce HTTP REST locale con IPC veloce per traffico massivo.

- [ ] Unix socket per richieste piccole (`/run/gavio/gavio.sock`)
- [ ] **Shared memory ring buffer** per inference streaming (output token-by-token)
- [ ] D-Bus session bus per integrazione desktop (Hyprland, notifiche, tray)
- [ ] Backward-compat: HTTP `:8000` resta per client remoti via WireGuard mesh
- [ ] Bench: latency target < 0.5ms per IPC vs ~5ms per HTTP localhost

#### M2.2 — Voice locale (whisper.cpp + piper)

Sostituisce `faster-whisper` Python con `whisper.cpp` nativo + `edge-tts` (cloud, NO!) con `piper` locale.

- [ ] Modulo NixOS `solem-voice.nix` opt-in:
  - `services.whisper-cpp` (server JSON-RPC su porta 8004)
  - `services.piper` (TTS server)
- [ ] Endpoint `/solem/voice/stt` proxy a whisper.cpp
- [ ] Endpoint `/solem/voice/tts` proxy a piper
- [ ] CLI `gavio "..."` accetta `--voice` per output audio
- [ ] Hotkey globale desktop: registra audio → STT → query GAVIO → TTS

#### M2.3 — Semantic UI AT-SPI

Sostituisce computer-use pyautogui+screenshot con accessibility tree.

- [ ] NixOS modulo `solem-semantic-ui.nix` con `at-spi2-core` attivo
- [ ] Daemon `solem-ui-observer` Python che dump AT-SPI tree → JSON struttura semantica
- [ ] Endpoint `/solem/ui/observe` → ritorna struttura corrente desktop
- [ ] Endpoint `/solem/ui/act` → chiama metodi AT-SPI per click/type/scroll
- [ ] Fallback: screen capture + OCR (tesseract già installato) + parsing UI per app non-AT-SPI
- [ ] Manifest GTK/Qt application: SOLEM mantiene whitelist app cooperative

#### M2.4 — MCP tool registry centrale

Allineamento a Prompt Master sez. 4.7.

- [ ] Modulo `solem-mcp.nix` con tool registry dichiarativo
- [ ] Backend `layers/mcp.py` (nuovo) — proxy MCP a GAVIO `api/mcp.py` + native SOLEM tools
- [ ] Sandboxing automatico tool via bubblewrap/firejail
- [ ] Versioning + firma tool (hash Nix)
- [ ] CLI `solem mcp list/install/run <tool>`

### Milestone 2.5 — Kill switch + Constitutional layer (Mese 5-6)

- [ ] Hotkey globale `Super+Shift+K` → `systemctl stop gavio.service` + `solem-api/agents/*/disable`
- [ ] Constitutional rules in `/etc/gavio/constitution.json` dichiarativo:
  - Regole assolute (es. "mai eliminare /home senza confirm 2FA")
  - Categorie azione (lettura/scrittura/execution/network)
  - Enforced lato SOLEM (gateway) prima di passare richiesta a GAVIO
- [ ] Two-factor confirmation per azioni distruttive (prompt via D-Bus notification)

---

## Orizzonte 1 anno — Mesi 7-12 (Dic 2026 - Mag 2027)

### Milestone 3 — Autonomy + Multi-instance (PROMPT v4.0 Milestone 3)

#### M3.1 — Memoria L0-L3 completa (Mese 7-8)

Allineamento a Prompt Master sez. 4.5.

- [ ] **L0 working memory** — Python in-RAM contesto attivo (già esiste in GAVIO)
- [ ] **L1 short-term** — vector DB embedded (qdrant/lancedb scelto in ADR-006)
- [ ] **L2 long-term** — vector DB cifrato (LUKS bare-metal Step 1) con embedding
- [ ] **L3 archived** — cold storage compresso zstd
- [ ] Embedding model locale: `nomic-embed-text` via Ollama (gratis on-device)
- [ ] Migration GAVIO `vector_memory.db` → SOLEM `/var/lib/gavio/memory/`
- [ ] API `/solem/memory/recall?query=...` con cosine search vector

#### M3.2 — Multi-instance Gavio (Mese 9-10)

- [ ] CRDT sync via **automerge** o **yjs** (entrambi FOSS) tra istanze SOLEM nella mesh
- [ ] Replication selettiva: identity replicata 1:1, memoria parzialmente (privacy-aware), context per-device
- [ ] Compute offloading: device A delega inference pesante a device B in mesh tramite SOLEM API
- [ ] Discovery via mDNS Avahi (già attivo) + WireGuard route
- [ ] CLI `solem-mesh delegate <agent_id> <task>` → ruota verso device disponibile

#### M3.3 — Filesystem semantico (Mese 11-12)

Allineamento a Prompt Master sez. 2.4.

- [ ] Indicizzazione background dei file utente (con consenso) → embedding in `lancedb`
- [ ] CLI `solem find "documenti su SOLEM dell'anno scorso"` → ricerca semantica
- [ ] Permessi granulari per directory (whitelist/blacklist)
- [ ] Indice incrementale via inotify

---

## Orizzonte 3 anni — Mesi 13-36

### Milestone 4 — Intelligence (Mesi 13-18)

#### M4.1 — Auto-improvement pipeline locale

- [ ] Logging interazioni con consenso → `/var/lib/gavio/audit/interactions/`
- [ ] Pipeline LoRA fine-tuning notturna via `peft`/`unsloth` (richiede GPU; Step 3+ con Jetson)
- [ ] A/B testing locale tra varianti GAVIO con metriche (accuracy, latency, user feedback)
- [ ] Rollback automatico se versione nuova performa peggio
- [ ] Distillation: modelli più grandi (es. Llama 70B su Jetson) → modelli più piccoli per laptop

#### M4.2 — Federated learning multi-device

- [ ] **Flower** (FOSS) per federazione tra istanze SOLEM dell'utente
- [ ] Mai cloud, sempre on-device, sync tramite WireGuard mesh
- [ ] Gradient sharing privacy-preserving (differential privacy)
- [ ] Opt-in esplicito per ogni device

#### M4.3 — Rust adoption progressiva

Decisione in ADR-002. Se priorità Step 2+:

- [ ] Riscrivere `solem-keep` watchdog in Rust
- [ ] Riscrivere `solem-doctor` in Rust con `clap` CLI
- [ ] Kernel module opzionale per Gavio Runtime Subsystem in Rust (rust-for-linux)
- [ ] FFI Python↔Rust dove ha senso (es. inference dispatcher)

### Milestone 5 — Release pubblica beta (Mesi 19-24)

- [ ] Documentazione bilingue IT+EN completa (mdBook)
- [ ] Sito statico (Hugo o mdBook) hostato su Codeberg Pages (FOSS, gratis)
- [ ] Forge git: migrare a **Forgejo self-host** (su Beelink stesso quando attivo Step 1)
- [ ] CI: **Woodpecker** o **Forgejo Actions** self-host
- [ ] Discourse forum self-host
- [ ] Matrix `synapse` self-host per chat community
- [ ] Programma early adopter — solo self-hoster, mai utenti paganti
- [ ] Hardening security esteso: pentest community, bug bounty con donazioni

### Milestone 6 — Convergenza multi-device (Mesi 25-36)

- [ ] **SOLEM Mobile** su PinePhone Pro (mobile NixOS FOSS)
- [ ] **Plasma Mobile** o **Phosh** convergent UI
- [ ] Compute offloading trasparente: phone → desktop in LAN
- [ ] **Raspberry Pi** edge bridge IoT con MQTT broker
- [ ] **Release 1.0** dopo 12 mesi di beta stabile

---

## Cross-cutting (sempre attivo)

### Sicurezza
- [ ] Audit trimestrale codebase
- [ ] STRIDE threat model per ogni nuovo modulo
- [ ] Reproducible builds verificati automaticamente
- [ ] Penetration testing community Step 5+

### Performance
- Target latency `/health < 50ms`, `/manifest < 200ms`, `solem-doctor < 5s`
- Bench vs NixOS vanilla / Ubuntu / Fedora / Arch

### Test coverage
- Step 1: > 70% backend
- Step 2: > 85% backend
- NixOS integration tests + fuzz testing (AFL++ / cargo-fuzz) + property-based (proptest/hypothesis)

### Documentazione
- Bilingue **italiano + inglese** (priorità italiano per founder)
- Ogni feature ha: .md + esempio funzionante + test
- ADR per ogni decisione architetturale importante
- RFC pubblici su Forgejo

### Accessibilità
- WCAG AAA dove applicabile (Step 4+)
- Orca screen reader
- Cognitive accessibility supportata

### Sostenibilità (tutto gratis, mai feature gating)
- Donazioni: Open Collective / GitHub Sponsors / Liberapay / Ko-fi
- Grant: NLnet / Sovereign Tech Fund / Prototype Fund / NGI Zero
- Hosting iniziale: Codeberg / GitHub free tier finché non arrivano grant
- Bug bounty con donazioni accumulate

---

## Deliverable per ogni Milestone (standard)

1. **Spec RFC-style** (Markdown in `docs/rfc/RFC-NNN-titolo.md`)
2. **Diagrammi architetturali** Mermaid embedded
3. **Moduli Nix funzionanti + test NixOS** (`tests/nixos/`)
4. **Test backend** pytest + integration + fuzz dove sensato
5. **Documentazione bilingue** IT+EN
6. **Threat model** STRIDE per nuovi moduli
7. **Benchmark** rilevanti
8. **PR upstream** a `nixpkgs` quando sensato
9. **ADR** per decisioni architetturali (`docs/adr/ADR-NNN-titolo.md`)
10. **Manifest capability** per ogni componente GAVIO

---

## Gate decisionali (non procedere se non risolti)

1. **Gate M0** (oggi): approvazione utente di questo documento + audit
2. **Gate M1**: hardening systemd completato + `/var/lib/gavio/` strutturato
3. **Gate M2**: IPC nativo bench OK + semantic UI funzionante su almeno 1 app desktop
4. **Gate M3**: memoria L0-L3 con embedding locale + multi-instance sync demo 2 device
5. **Gate M4**: auto-improvement misurato con metriche concrete
6. **Gate M5**: beta pubblica con primo utente self-hoster esterno (non founder)
7. **Gate M6**: SOLEM Mobile boot su PinePhone Pro

---

## Cosa NON facciamo (per direttiva utente "solo coding, solo gratis")

- ❌ Mai servizi cloud paganti (AWS/GCP/Azure/OpenAI/Anthropic/Pinecone/MongoDB Atlas)
- ❌ Mai modelli AI proprietari (solo open weight Llama/Mistral/Qwen/DeepSeek/Phi/Gemma)
- ❌ Mai feature gating / tier paid
- ❌ Mai hardware proprietario richiesto
- ❌ Mai telemetria silente
- ❌ Mai Docker Desktop / GitHub Copilot / Notion / Slack proprietari per coordinamento
- ❌ Mai vendita di hardware bundled da noi
- ❌ Mai managed services paganti

Vedi → [docs/COSTS.md](docs/COSTS.md) per dettagli + lista nera Appendice B del Prompt Master v4.0.

---

## Prossima azione richiesta — APPROVAZIONE UTENTE

Per procedere alle fasi successive del Prompt Master v4.0 (Milestone 1.1 systemd hardening):

1. **Rispondi alle 8 domande aperte** di [SOLEM_AUDIT_REPORT.md § 3](SOLEM_AUDIT_REPORT.md)
2. **Rispondi alle 10 domande aperte** di [GAVIO_INTEGRATION_AUDIT.md § 4](GAVIO_INTEGRATION_AUDIT.md)
3. **Approva questa roadmap** (o richiedi modifiche)
4. **Indica priorità relative** se le tempistiche 3-6-12-36 mesi non corrispondono al tuo ritmo reale

**Non procedo a sviluppare codice nuovo finché Gate M0 non è chiuso.**
