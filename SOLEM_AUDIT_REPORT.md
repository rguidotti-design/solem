# SOLEM — Audit Report (Fase 0, Prompt Master v4.0)

**Data**: 2026-05-17
**Auditor**: assistente di sistema (per direttiva utente)
**Repo**: `c:\Users\guido\Desktop\solem\` (locale, non ancora su forge git pubblico)

---

## 1. Inventario quantitativo

### 1.1 Moduli NixOS — 22 file `.nix`

| Modulo | Scopo | Stato | Conformità v4.0 |
|--------|-------|-------|-----------------|
| `flake.nix` | Entry point flake (nixpkgs 24.11) | ✅ funzionante | ✅ FOSS, riproducibile |
| `nixos/configuration.nix` | Compone i 21 moduli | ✅ | ✅ dichiarativo |
| `nixos/hardware-vm.nix` | VM QEMU + 9p shared folders (gavio, solem-backend, solem-flake) | ✅ | ✅ test-only, no costi |
| `modules/solem-core.nix` | Utente `gavio`, Nix flakes, GC, journald, `mutableUsers=false`, `hashedPassword` SHA-512 | ✅ | ✅ |
| `modules/networking.nix` | nftables firewall, SSH, Avahi mDNS | ✅ | ✅ FOSS |
| `modules/security.nix` | fail2ban, auditd, PAM nofile limits | ✅ | parziale (manca KSPP) |
| `modules/ai-freedom.nix` | sudo NOPASSWD, polkit, gruppi hw | ✅ | ⚠️ rivedere per zero-trust |
| `modules/gavio.nix` | systemd service GAVIO + Ollama + Docker + Tesseract/FFmpeg/Chromium, healthcheck | ✅ | ⚠️ Docker → migrare a Podman |
| `modules/solem-api.nix` | systemd service backend Python `:8001` con PATH nix/systemctl/sudo | ✅ | ✅ |
| `modules/solem-backup.nix` | systemd timer giornaliero zstd snapshot stato persistente | ✅ | ✅ locale only |
| `modules/solem-mesh.nix` | WireGuard mesh tra device SOLEM (opt-in) | ✅ scaffold | ⚠️ DNS dnsmasq lib disabled default |
| `modules/solem-zero-trust.nix` | Caddy mTLS proxy + CA bootstrap (opt-in) | ✅ scaffold | ✅ Caddy FOSS |
| `modules/solem-desktop.nix` | Hyprland + Pipewire + Bluetooth + Firefox + assets navy (opt-in) | ✅ | ✅ FOSS |
| `modules/solem-boot.nix` | Plymouth theme `solar` + quiet boot | ✅ | ⚠️ KASLR/lockdown da abilitare |
| `modules/solem-secure.nix` | 5 layer opt-in: LUKS/secure-boot stub/sops-stub/kernel hardening attivo/AppArmor selettivo | ⚠️ parziale | ⚠️ Lanzaboote da integrare |
| `modules/solem-creator.nix` | Toolkit dev/ai/data/creative opt-in (OpenTofu invece di terraform per OSS) | ✅ | ✅ FOSS only |
| `modules/solem-profiles.nix` | 5 preset: minimal/developer/creator/server/desktop | ✅ | ✅ |
| `modules/solem-update.nix` | Auto-update OTA + GC + boot rollback | ✅ scaffold | ✅ usa path locale, no GitHub default |
| `modules/solem-motd.nix` | Banner ASCII + MOTD dinamica via bash interactiveShellInit (NO PAM hack) | ✅ | ✅ |
| `modules/solem-cli.nix` | Comando `solem` Python stdlib | ✅ | ✅ |
| `modules/solem-shell.nix` | TUI `solem-shell` curses, palette navy | ✅ | ✅ |
| `modules/solem-doctor.nix` | 30+ check sistema/servizi/network/db/security/mesh | ✅ | ✅ |
| `modules/solem-keep.nix` | Watchdog daemon → event bus L3 | ✅ | ✅ |
| `modules/solem-layers.nix` | Manifest L1-L7 + dir persistenti | ✅ | ✅ |

### 1.2 Backend Python (`backend/solem_api/`) — 13 moduli + 8 test

| Modulo | Endpoint | Stato |
|--------|----------|-------|
| `main.py` | App FastAPI con OpenAPI auto-generato | ✅ |
| `layers/db.py` | SQLite WAL+FK in `/var/lib/solem/solem.db`, schema multi-tenant `user_id` | ✅ |
| `layers/identity.py` | L1: 5 sezioni standard versionate + custom_* | ✅ |
| `layers/context.py` | L2: snapshot push/history + timer systemd 5min | ✅ |
| `layers/events.py` | L3: pub/sub asyncio + persistenza SQLite + SSE | ✅ |
| `layers/capabilities.py` | L4: registry 17 cap native + auto-discovery GAVIO via OpenAPI + `/invoke` proxy | ✅ |
| `layers/memory.py` | L5: 3 livelli (solem_memory + user_universe_memory + context) + privacy `sacred/personal/work/public` | ✅ scaffold |
| `layers/interop.py` | L6: bridge stub email/calendar/MQTT + **Wake-on-LAN funzionante** | ⚠️ stub |
| `layers/extensions.py` | L7: registry plugin scheletro | ⚠️ stub |
| `layers/agents.py` | Multi-AI: GAVIO primary + 3 specialisti (coder/researcher/writer) su Ollama | ✅ scaffold |
| `layers/users.py` | Multi-utente: users/sessions + login/logout/me/list/create | ✅ |
| `layers/system.py` | Runtime control: info/generations/profile/rebuild/rollback/update | ✅ |
| `layers/metrics.py` | Prometheus text format + audit jsonl tail | ✅ |
| `layers/migrations.py` | DB schema migrations versionate + auto-apply at startup (3 migration) | ✅ |

### 1.3 CLI nativi (3)
- `solem` — status/layers/caps/identity/pair/devices/version + `--json`
- `solem-shell` — TUI 4 pannelli curses palette navy/oro
- `solem-doctor` — 30+ check sistema con output ANSI + `--json`/`--only`/`--quiet`

### 1.4 Dashboard web (`backend/solem_api/static/`)
- HTML+CSS+JS vanilla zero-build, palette **blue navy + oro + ghiaccio**
- Logo SVG sun orb + Cormorant Garamond wordmark
- 7 tab: Overview / Layers / Services / Capabilities / Mesh / Identity / Settings
- Polling 5s, generatore PIN pairing integrato
- **Nessuna emoji** (direttiva utente)

### 1.5 Documentazione — 14 file
README, CHANGELOG, ROADMAP, SECURITY, CONTRIBUTING, SOLEM_AUDIT_REPORT (questo), GAVIO_INTEGRATION_AUDIT, INTEGRATION_ROADMAP +
docs/: ARCHITECTURE, TESTING, POST_BOOT, INSTALL, AI_FREEDOM, MESH, ZERO_TRUST, COSTS, COMPETITIVE, api/openapi.yaml

### 1.6 Tests — 8 file pytest (~40 test)
test_meta, test_identity, test_context, test_memory, test_events, test_pairing, test_users, test_capabilities

### 1.7 Tool e scripts
Makefile (12 target), solem-install.sh (installer bare-metal LUKS+UEFI), run-vm/ssh/logs/setup-env (PS+sh)

### 1.8 CI
`.github/workflows/build.yml` (flake-check + pytest + ruff) + `release.yml` (qcow2 artifact + GitHub release)

---

## 2. Conformità al Prompt Master v4.0 (gap analysis)

### 2.1 Vincoli fondamentali — stato

| Vincolo | Stato | Note |
|---------|-------|------|
| **Solo coding, gratis** | ✅ | Nessun servizio paid nei default |
| **FOSS only** | ✅ | Verificato in `docs/COSTS.md` |
| **Nessuna telemetria monetizzata** | ✅ | Mai presente |
| **NixOS base** | ✅ | flake nixos-24.11 |
| **Gavio cittadino di prima classe** | 🟡 | Servizio systemd dedicato esiste; mancano: namespace dedicato, cgroup avanzati, MCP tool registry, semantic UI hooks |

### 2.2 Fasi v4.0 — copertura per fase

| Fase | Sezione v4.0 | Copertura SOLEM Step 0 | Gap |
|------|-------------|------------------------|-----|
| 1.1 | Kernel hardening KSPP | ⚠️ parziale | manca KSPP cmdline params, KASLR aggressivo, module signing |
| 1.2 | systemd hardening (NoNewPrivileges, ProtectSystem...) | ❌ | `gavio.service` e altri servizi NON hanno hardening esteso |
| 1.3 | Huge pages, mlockall, zram, earlyoom | ❌ | manca tutto |
| 1.4 | Bubblewrap/firejail, landlock | ❌ | AppArmor opt-in stub; landlock non configurato |
| 2.1 | bcachefs default | ❌ | VM usa ext4; bare-metal install usa ext4 con LUKS opt |
| 2.2 | impermanence, sops-nix, agenix | ❌ | sops-nix solo stub in solem-secure.nix |
| 2.3 | `/var/lib/gavio/` dedicato | 🟡 | esiste ma non strutturato (models/memory/cache/audit/state) |
| 2.4 | Filesystem semantico (qdrant/lancedb) | ❌ | manca |
| 2.5 | Syncthing/Iroh/Veilid | ❌ | manca |
| 3 | nftables, WireGuard, DoT/DoH, Headscale, Yggdrasil | 🟡 | nftables sì, WireGuard sì stub, DNS stubby+unbound mancante |
| 4.1 | Gavio Runtime Subsystem (gaviod daemon, IPC ring buffer) | ❌ | servizio systemd `gavio` esiste ma non con IPC shared memory |
| 4.2 | HAL AI (CUDA/ROCm/oneAPI/Vulkan compute) | ❌ | manca |
| 4.3 | Inference backends (llama.cpp/vllm/candle/whisper.cpp/piper) | 🟡 | solo Ollama; manca whisper.cpp/piper |
| 4.4 | Model registry Nix-managed + quantizzazione auto | ❌ | manca |
| 4.5 | Memory hierarchy L0-L3 + KV-cache persistente | 🟡 | DB SQLite c'è, manca vector DB embedded, KV-cache, embedding cache |
| 4.6 | Capability system Nix-declarative `gavio.capabilities = {...}` | ❌ | manca (solo API registry, no Nix bindings) |
| 4.7 | MCP tool calling protocol | ❌ | manca |
| 4.8 | Semantic UI via AT-SPI extensions | ❌ | manca |
| 4.9 | Auto-improvement (LoRA/QLoRA/Federated learning Flower) | ❌ | manca |
| 4.10 | Multi-instance Gavio CRDT sync | ❌ | manca (solem-mesh c'è ma non sync stato Gavio) |
| 4.11 | Kill switch hotkey + constitutional rules | ❌ | manca |
| 4.12 | Prompt injection protection | ❌ | manca |
| 5.1 | KSPP, AppArmor strict, LUKS2 installer, Lanzaboote, TPM2, USBGuard, auditd | 🟡 | LUKS in installer sì; Lanzaboote/TPM2/USBGuard mancano; auditd attivo |
| 5.2 | Sandboxing nested Gavio + anomaly detection | ❌ | manca |
| 5.4 | Memory safety Rust ove possibile | ❌ | tutto Python al momento |
| 6.1 | GNOME / KDE / Hyprland / COSMIC | 🟡 | solo Hyprland opt-in (creator profile) |
| 6.2 | Wayland HDR/VRR multi-monitor 120Hz | 🟡 | Wayland sì, HDR/VRR config no |
| 6.3 | `gavio` shell command + voice (whisper+piper) | ❌ | manca |
| 6.5 | Flatpak FOSS-only + AppImage + Distrobox + NO Snap | ❌ | manca |
| 6.6 | GUI dichiarativa per Nix config | ❌ | manca |
| 6.7 | WCAG AAA + Orca screen reader | ❌ | manca |
| 7 | Multi-device convergente (PinePhone Pro, server, Pi) | ❌ | solo x86_64 VM |
| 8 | direnv, devenv, container Podman/LXC, WASM, rr time-travel | 🟡 | direnv no, devenv no, Podman opt-in via creator |
| 9 | nix-ld, Steam+Proton, Wine+Bottles, Waydroid | ❌ | manca |
| 10 | Governance + RFC + community Discourse/Matrix | ❌ | non ancora |
| 11 | Forgejo self-hosted + Woodpecker CI + Cachix self-host | ❌ | usa GitHub Actions (free tier OK) |
| 12 | Roadmap M0-M6 specifica | 🟡 | ROADMAP.md esistente da rivedere con M0-M6 v4.0 |

### 2.3 Coperture buone (Step 0)
- ✅ Multi-tenant DB schema by design (user_id, RLS-ready)
- ✅ Event bus L3 con persistenza + SSE
- ✅ Capabilities registry L4 dichiarativo con manifest
- ✅ Multi-AI registry agents.py con 4 default agents Ollama
- ✅ Dashboard navy AI-readable (JSON ovunque, OpenAPI completo)
- ✅ CLI `solem` con `--json` per consumption AI
- ✅ Backup automatico locale zstd retention 14
- ✅ Watchdog `solem-keep` con publish event bus
- ✅ Diagnostica `solem-doctor` 30+ check
- ✅ Audit policy chiara (SECURITY.md threat model)

### 2.4 Debiti tecnici evidenti
1. **Hardening systemd assente sui servizi core** — vincolo non negoziabile v4.0 sez. 1.2
2. **Gavio non è veramente "primo classe"** — è solo un servizio Python, manca IPC ring buffer, capability Nix-declarative, MCP tool registry
3. **Niente inference backend nativi oltre Ollama** — manca whisper.cpp, piper, llama.cpp diretto, candle
4. **Memory architecture incompleta** — manca vector DB embedded, KV-cache persistente, hierarchy L0-L3
5. **Niente memory-safe Rust** — tutto Python
6. **No mobile/convergence** — solo x86_64 VM
7. **No DE alternatives** — solo Hyprland; GNOME/KDE/Sway/COSMIC mancanti
8. **Filesystem semantico assente**
9. **Capability concession workflow utente** — manca approval-on-first-use
10. **Constitutional layer + kill switch + prompt injection protection** — completamente mancanti

---

## 3. Domande aperte all'utente (Ruben Guidotti)

Per finalizzare l'audit della parte SOLEM:

1. **NixOS unstable o stable?** Attualmente uso `nixos-24.11`. Prompt v4.0 dice "Linux LTS più recente" → vuoi salire a `nixos-unstable` o restare su stable?
2. **Rust adoption priority?** Riscrivere i daemon Python in Rust (es. `solem-keep`, `solem-doctor`) è priorità Step 1 o Step 2?
3. **bcachefs default?** Sostituire ext4 di default con bcachefs è priorità Step 1 (Beelink bare-metal) o Step 2?
4. **Mobile target Step 6?** PinePhone Pro come hardware reference o aspetti device proprio?
5. **CI self-hosted ora o dopo?** GitHub Actions free tier funziona, ma v4.0 dice Forgejo+Woodpecker self-hosted. Quando migrare?
6. **GUI Nix config (dashboard moderno)?** v4.0 sez. 6.6 — costruire SOLEM Dashboard tab Settings → editor visuale per `configuration.nix`?
7. **Constitutional AI layer**: chi scrive le "regole inviolabili" di Gavio? Sono in GAVIO repo o in SOLEM?
8. **Hardware AI target sviluppo**: lavori principalmente in VM TCG (no GPU)? O hai accesso a GPU per testare HAL?

---

## 4. Sintesi

**SOLEM Step 0 è solido come scaffold ma è ~20% conforme al Prompt Master v4.0.**

Lo Step 0 ha raggiunto: OS NixOS funzionante in VM, multi-tenant by design, 12 router backend, CLI nativi, dashboard, multi-AI registry, zero-trust + mesh opt-in, 100% gratis.

Per essere "OS AI-native production-grade" come richiede v4.0 mancano: **systemd hardening esteso, vero GRS (Gavio Runtime Subsystem), HAL AI, inference backends nativi, MCP, semantic UI, mobile/convergence, Rust adoption, filesystem semantico, capability Nix-declarative**.

Il prossimo lavoro è la **co-evoluzione SOLEM ↔ GAVIO** secondo Milestone M0-M6 del v4.0.

Vedi → [GAVIO_INTEGRATION_AUDIT.md](GAVIO_INTEGRATION_AUDIT.md) e [INTEGRATION_ROADMAP.md](INTEGRATION_ROADMAP.md).
