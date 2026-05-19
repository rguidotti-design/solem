# SOLEM Roadmap

Stato attuale: **Step 0** completato. Step 1 in pianificazione.

> Regola d'oro: ogni step si apre **solo dopo 30 giorni di uso reale** del precedente.

---

## Step 0 — Mag-Giu 2026 ✅ COMPLETATO

**Obiettivo**: scheletro OS funzionante in VM testabile, primo backend SOLEM oltre GAVIO.

### Done
- [x] NixOS scaffold flake con 22 moduli (core, network, security, ai-freedom, gavio, api, backup, mesh, zero-trust, desktop, boot, motd, cli, shell, doctor, keep, secure, creator, profiles, update, layers)
- [x] Backend Python `:8001` con 12 router (L1-L5 + agents + interop + extensions + users + system + metrics + migrations) = 45+ endpoint
- [x] Dashboard web palette navy + 6 tab + Settings
- [x] CLI: `solem`, `solem-shell` (TUI), `solem-doctor` (30+ check)
- [x] Multi-utente schema + auth token sessione
- [x] Mesh WireGuard + Zero-trust mTLS (opt-in)
- [x] Desktop Hyprland + wallpaper SVG + waybar config (opt-in)
- [x] Auto-update OTA settimanale + rollback automatico boot
- [x] Test suite pytest (40+ test)
- [x] CI GitHub Actions (build + test + release ISO)
- [x] CLI installer bare-metal `solem-install`
- [x] 12 documenti in `docs/` (architecture, install, testing, post_boot, ai_freedom, mesh, zero_trust, competitive, costs, openapi spec)

---

## Step 1 — Est-Aut 2026 — bare-metal Beelink

**Obiettivo**: SOLEM gira 24/7 su mini-PC fisico, primo device esterno paired.

- [ ] **Hardware**: Beelink Mini S12 Pro (N100, 16GB, 500GB)
- [ ] **Install reale**: ISO live + `solem-install.sh` con LUKS2 + UEFI Secure Boot
- [ ] **Lanzaboote** per Secure Boot con chiavi firmate utente
- [ ] **sops-nix** per secret cifrati in repo (chiavi API LLM)
- [ ] **Backup remoto opzionale** verso un altro nodo SOLEM (mesh peer) via `restic` o `rsync` — niente servizi cloud paganti
- [ ] **mDNS pubblico** `solem.local` raggiungibile da tutti i device LAN
- [ ] **Primo device paired** (telefono o laptop) via WireGuard mesh
- [ ] **Cert mTLS** firmati al pairing per quel device
- [ ] **Reverse proxy Caddy** con Let's Encrypt (dominio opzionale)
- [ ] **Power management** (suspend/hibernate config)
- [ ] **Plymouth tema custom SOLEM** con SVG renderizzato a PNG (logo + animazione orb dorato)
- [ ] **Monitoring**: Prometheus + Grafana dashboard interna su `:8001/metrics`
- [ ] **Migrate VM → bare-metal**: backup VM, restore su Beelink, verifica continuità

---

## Step 2 — Inv 2026/27 — Identity + Context + Memory completi

**Obiettivo**: i Layer L1+L2+L3+L5 escono da GAVIO e diventano servizi SOLEM autonomi.

- [ ] **L1 Identity Engine** completo: multi-user su Supabase con RLS, JWT auth, ruoli dinamici, sezioni "vive" da KAIROS
- [ ] **L2 Context Engine** snapshot persistente 5min su Supabase, predizione comportamentale base
- [ ] **L3 Event Bus** dedicato Redis/NATS (non più in-memory asyncio)
- [ ] **L5 Memory** 3 livelli completi: schema multi-tenant Supabase, embedding `text-embedding-3-large`, ricerca vector cosine
- [ ] **Messaging E2E** AES-256-GCM Day 1 + tabella `messages` cifrate
- [ ] **OAuth providers** (Google/Apple/GitHub) per onboarding senza password
- [ ] **API runtime per rebuild** (`POST /solem/system/profile` funzionante)
- [ ] **CLI `solem-join`** per device esterni che fanno pairing in 30 secondi
- [ ] **Mobile app companion** PWA installable per dashboard + pairing + chat
- [ ] **Policy engine** zero-trust granulare (chi-può-fare-cosa per-AI-per-utente)

---

## Step 3 — 2027 — Multi-AI + Jetson + beta privata

**Obiettivo**: prima AI specialista oltre GAVIO, LLM locale veloce, 3-5 utenti beta.

- [ ] **Hardware**: NVIDIA Jetson Orin Nano (LLM 8B locale, ~50 tok/s)
- [ ] **Prima AI specialista**: AI legale italiana addestrata su Codice Civile/Penale
- [ ] **AI-to-AI protocol**: GAVIO invoca specialiste con payload Pydantic + audit event bus
- [ ] **Memoria Livello B** ingest automatico: email IMAP + calendar CalDAV + file watcher
- [ ] **Memoria Livello C** snapshot context con deduzioni (location pattern, mood, task switching)
- [ ] **Device targeting**: Wake-on-LAN, remote shutdown, file send tra device mesh
- [ ] **Edge nodes Pi**: Raspberry Pi 5 in casa come bridge IoT (MQTT broker)
- [ ] **Privacy `sacred` enforcement**: filter automatico per LLM esterni
- [ ] **Beta privata 3-5 utenti**: onboarding via invito + feedback strutturato
- [ ] **Plymouth final**: theme custom completo + boot animation

---

## Step 4 — 2028 — Multi-tenant pubblico (self-host gratis)

**Obiettivo**: aprire SOLEM al pubblico — sempre 100% self-host, 100% gratis.

- [ ] **Multi-tenancy attiva** (RLS Supabase free tier o Postgres self-host, JWT per-user)
- [ ] **Self-host only** — niente servizi managed paganti
- [ ] **Brand assets** completi (sito vetrina, logo PNG/SVG varianti, social images)
- [ ] **Extensions Marketplace v1**: registry pubblico + manifest + sandboxing AppArmor (tutte le extension gratuite)
- [ ] **Auto-update OTA** robusto con canale stable/beta/edge
- [ ] **Onboarding self-host**: ISO live con wizard `solem-install` + supporto Pi/Beelink/x86 standard
- [ ] **Documentation site** statico (mkdocs material theme navy)
- [ ] **Community**: GitHub Discussions + Matrix (entrambi gratuiti)

Target: **utenti reali che self-hostano SOLEM 30+ giorni** (no metriche paganti).

---

## Step 5+ — 2029+ — Distro consolidata

**Obiettivo**: SOLEM come distro Linux completa, sempre 100% gratuita self-host.

- [ ] **Guide hardware**: documentazione dettagliata per Beelink/Pi/x86 standard (no vendita, solo guide)
- [ ] **Distro custom**: nome alternativo a NixOS per branding identitario
- [ ] **Mobile companion** PWA installable (no app store paganti — installazione diretta da browser)
- [ ] **Fine-tuning locale**: pipeline per fine-tune LLM su tuo hardware (Jetson o GPU)

---

## Cross-cutting (sempre attivo)

- **Sicurezza**: audit trimestrale codebase, pentesting Step 3+, bug bounty Step 4+
- **Performance**: target latency `/health < 50ms`, `/manifest < 200ms`, `solem-doctor < 5s`
- **Test coverage**: > 70% per backend Step 1, > 85% Step 2+
- **Documentation**: ogni feature ha .md + esempio + test
- **Accessibilità**: dashboard ARIA-compliant + screen reader friendly Step 2+
- **i18n**: italiano + inglese da Step 4 pubblico

---

Aggiornato: 2026-05-17 (Step 0 complete)
