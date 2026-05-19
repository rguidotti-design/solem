# Changelog SOLEM

Tutte le modifiche significative al progetto.
Versionato secondo [SemVer](https://semver.org/).

## [Unreleased] — Single Responsibility Modules (2026-05-19)

### Aggiunto — 10 moduli atomici Single Responsibility

Refactoring secondo principio "il pizzaiolo non fa i dolci". Ogni modulo NixOS = una sola responsabilità ben definita.

- **`solem-double-vpn.nix`** — VPN doppia: layer 1 mesh interno (da `solem-mesh.nix`) + layer 2 tunnel esterno verso peer self-host. Incapsulamento traffico Internet a 2 livelli. Assertion peer obbligatorio.
- **`solem-dns-private.nix`** — DoT/DoH via stubby (:5353) + unbound (:53). Upstream Cloudflare + Quad9 (free, no carta). qname-minimisation + aggressive-nsec. Override `services.resolved`.
- **`solem-kernel-hardening.nix`** — KSPP boot cmdline esteso: `slab_nomerge`, `init_on_alloc=1`, `init_on_free=1`, `page_alloc.shuffle=1`, `pti=on`, `vsyscall=none`, `debugfs=off`, `kaslr`, `lockdown=integrity`. Blacklist 25 filesystem/protocolli legacy. Default ON.
- **`solem-memory.nix`** — zram 50% RAM zstd + earlyoom (free<5%) protect gavio/ollama/solem-api + systemd-oomd su user_slices + huge pages opt-in. `gavio.service.MemoryHigh=3G`. Default ON.
- **`solem-sandbox.nix`** — bubblewrap + firejail + nsjail + Landlock LSM. Boot cmdline `lsm=landlock,lockdown,yama,integrity,apparmor,bpf`. Default ON.
- **`solem-tpm.nix`** — TPM 2.0 abrmd + tpm2-tools + PKCS#11. User `gavio` in gruppo `tss`. Per measured boot + LUKS unseal + zero-trust attestation. Opt-in.
- **`solem-usbguard.nix`** — USB allowlist via D-Bus IPC. `presentControllerPolicy=allow` (no lockout tastiera). Approvazione runtime device nuovi. Opt-in.
- **`solem-tor.nix`** — Tor client SOCKS 9050 + control socket + opzionale onion service per esporre dashboard SOLEM via `.onion`. Opt-in.
- **`solem-secrets.nix`** — sops-nix scaffold (richiede flake input). Age key + secrets cifrati in repo, decifrati al boot in `/run/secrets/`. Assertion bloccante se input mancante.
- **`solem-secure-boot.nix`** — Lanzaboote scaffold + `sbctl` CLI. Chiavi UEFI utente custom. Step 1+ bare-metal. Assertion bloccante se input mancante.

### Totali aggiornati
- Moduli NixOS: 26 → **36**
- Voci STATUS.html "FUNZIONA": 42 → **52**

### Filosofia applicata
Ogni modulo nuovo:
- Ha **una sola opzione `enable`** (single responsibility entry point)
- Emette **`environment.etc."solem/<modulo>-config.json"`** per introspezione da SOLEM API
- Documenta **default ON/OFF** + uso esplicito
- **Non sconfina** in altri domini (es. `solem-tpm.nix` non tocca LUKS o secure boot, sono moduli separati)

---

## [0.1.0-step0] — 2026-05-17

Prima implementazione completa di **SOLEM Step 0**: OS NixOS AI-native che ospita GAVIO,
backend Python con layer L1-L5 reali, dashboard web in palette navy, CLI dedicati,
mesh + zero-trust opt-in, multi-profilo dichiarativo, auto-update OTA.

### Aggiunto — Infrastruttura OS (NixOS)

- **`flake.nix`** entry point con `nixosConfigurations.solem-vm` testabile via `nix run .#vm`
- **`solem-core.nix`** utente `gavio` (UID 1000, gruppi wheel/docker/video/audio/dialout/input/plugdev/networkmanager), Nix flakes, GC settimanale, journald 500MB persistente, `mutableUsers=false` + `hashedPassword`
- **`networking.nix`** firewall, SSH, mDNS Avahi, porte 22/8000/8001/8443/11434/51820
- **`security.nix`** audit kernel, fail2ban, PAM nofile limits
- **`ai-freedom.nix`** sudo NOPASSWD, polkit aperto, accesso device totale, porte privilegiate sotto 1024
- **`gavio.nix`** systemd service GAVIO con bootstrap venv automatico via `uv`, Ollama nativo, Docker, Tesseract/FFmpeg/Chromium, health check
- **`solem-api.nix`** systemd service SOLEM API porta 8001 con `nix-env`/`systemctl`/`sudo`/`nixos-rebuild`/`coreutils` nel PATH
- **`solem-backup.nix`** systemd timer giornaliero zstd snapshot di `/var/lib/gavio` + `/var/lib/solem` + `/etc/gavio` in `/var/backups/solem/`, retention 14
- **`solem-mesh.nix`** WireGuard mesh tra device SOLEM (opt-in), subnet 10.42.0.0/24, keygen automatico, pairing via PIN
- **`solem-zero-trust.nix`** Caddy mTLS proxy porta 8443 (opt-in), CA interna auto-bootstrap (RSA 4096 root + RSA 2048 server, rotazione 30gg)
- **`solem-desktop.nix`** Hyprland + Pipewire + Bluetooth + Firefox/Alacritty/Nautilus (opt-in, ~2GB)
- **`solem-boot.nix`** Plymouth splash theme `solar` (sole-themed, coerente con SOLEM = sole in latino), quiet boot, GRUB timeout 3s
- **`solem-secure.nix`** 5 layer sicurezza opt-in granulari (LUKS, secure boot, sops-nix, kernel hardening default-on, AppArmor selettivo solo per L7 extensions)
- **`solem-creator.nix`** 4 toolkit opt-in (dev/ai/data/creative): linguaggi (Python/Node/Go/Rust/Zig/Deno/Lua/Ruby/Java), kubectl/terraform, Jupyter+ML libs, PostgreSQL/DuckDB/Polars, Blender/GIMP/Inkscape
- **`solem-profiles.nix`** 5 preset dichiarativi (minimal/developer/creator/server/desktop) che configurano coerentemente moduli
- **`solem-update.nix`** auto-update OTA settimanale (`nixos-rebuild boot --refresh`), boot rollback automatico via systemd-boot tries, GC generations 30gg
- **`solem-motd.nix`** banner ASCII SOLEM (no Theory Holding) + MOTD dinamica via `programs.bash.interactiveShellInit`
- **`solem-cli.nix`** comando `solem` (subcomandi: status/layers/caps/identity/pair/devices/version, ANSI colorato, `--json` per AI)
- **`solem-shell.nix`** TUI `solem-shell` full-screen palette navy (4 pannelli: STATO/LAYER/MODULI/COMANDI), opt-in come login shell
- **`solem-doctor.nix`** comando `solem-doctor` con 30+ check su sistema/servizi/network/database/filesystem/security/user/mesh/zero-trust
- **`solem-keep.nix`** watchdog daemon Python (default-on): monitora gavio/solem-api/ollama/docker, restart automatico, pubblica eventi `system.service_down`/`system.service_recovered` sul bus L3
- **`solem-layers.nix`** manifest JSON L1-L7 in `/etc/solem/manifest.json` + directory persistenti `/var/lib/solem/`

### Aggiunto — Backend Python (`backend/solem_api/`)

- **`main.py`** FastAPI app con OpenAPI auto-generata, mount static dashboard, manifest dinamico con profile + modules
- **`layers/db.py`** SQLite WAL+FK in `/var/lib/solem/solem.db`, schema multi-tenant by design (user_id su ogni tabella)
- **`layers/identity.py`** L1 Identity Engine: 5 sezioni standard (roles/values/goals/routine/persone) + custom_*, versioning automatico, bootstrap default user
- **`layers/context.py`** L2 Context Engine: push/get/history snapshot, timer systemd 5min
- **`layers/events.py`** L3 Event Bus: pub/sub asyncio in-memory + persistenza SQLite, SSE streaming `/events/stream` con heartbeat 15s
- **`layers/capabilities.py`** L4 Capabilities Pool: registry dichiarativo 17 capability native SOLEM + auto-discovery GAVIO via OpenAPI, filtri source/tag/q, endpoint `/invoke` proxy con audit
- **`layers/memory.py`** L5 Memory 3 livelli: solem_memory + user_universe_memory (privacy `public/work/personal/sacred`), search LIKE (Step 3+: cosine vector embedding)
- **`layers/users.py`** Multi-utente + auth: users/sessions schema, login/logout, token Bearer TTL 7gg, role `owner/user/readonly`
- **`layers/system.py`** Control runtime: `/system/info`, `/generations`, `/profile` (cambia + rebuild), `/rebuild`, `/rollback`, `/update/{status,now}`

### Aggiunto — Dashboard web (`backend/solem_api/static/`)

- Palette **navy navy** (#060a14 bg / #1e3a5f navy / #c9a961 gold / #e8edf5 ghiaccio)
- Logo SVG con sun orb gradient + serif wordmark "SOLEM" + sottotitolo "AI-NATIVE OS"
- 6 tab: Overview / Layers / Services / Capabilities / Mesh / Identity / Settings
- Polling 5s su `/solem/manifest` e `/capabilities`
- Generatore PIN pairing integrato (tab Mesh)
- Filtri chip-based per capabilities (solem/gavio/extension)
- Settings tab con profilo attivo + lista moduli runtime + guida personalizzazione

### Aggiunto — Tools e Scripts

- `Makefile` shortcut: `make vm/ssh/logs/health/setup-env/restart-gavio/clean`
- `scripts/run-vm.{sh,ps1}` lancio VM da WSL/Windows
- `scripts/ssh.ps1` + `scripts/logs.ps1` + `scripts/setup-env.ps1` accesso VM da host
- `scripts/build-vm.sh` build esplicito
- `scripts/setup-in-vm.sh` applica config in VM NixOS standalone

### Aggiunto — Test e CI

- `backend/tests/` 7 file pytest (~40 test): meta, identity, context, memory, events, pairing, users, capabilities
- `backend/pytest.ini` config + filterwarnings
- `backend/tests/conftest.py` fixture con SQLite in-memory e reset tra test
- `.github/workflows/build.yml` CI su push/PR: flake-check + python-tests + ruff lint
- `.github/workflows/release.yml` build qcow2 release automatico su tag `v*`

### Aggiunto — Documentazione (`docs/`)

- `ARCHITECTURE.md` — 7 layer + stack + roadmap step 0→5
- `TESTING.md` — 3 metodi VM test + troubleshooting
- `POST_BOOT.md` — checklist primi 5 minuti
- `AI_FREEDOM.md` — filosofia + dettagli permessi AI
- `MESH.md` — VPN WireGuard tra device SOLEM
- `ZERO_TRUST.md` — mTLS + CA + audit log
- `COMPETITIVE.md` — SOLEM vs Ubuntu/Windows/macOS/ChromeOS/NixOS/Tailscale/Headscale/GrapheneOS
- `api/solem-api.openapi.yaml` — OpenAPI 3.1 spec

### Sicurezza — fix dopo bug noti

- **Bug PAM hijack**: `security.pam.services.<n>.text` sovrascrive INTERO file PAM → bloccava il login. Risolto spostando MOTD dinamica in `programs.bash.interactiveShellInit`.
- **Bug FastAPI status 204**: assert FastAPI vieta response body con status 204 + `-> None`. Risolto con ritorno `dict {"deleted": True}`.
- **Bug `users.users.<n>.password` con `mutableUsers=true`**: password plaintext non sempre applicata. Risolto con `hashedPassword` SHA-512 + `mutableUsers=false`.
- **Bug `services.pulseaudio` non esiste in NixOS 24.11**: rinominato a `hardware.pulseaudio`.
- **Bug `xorg.libxkbcommon` rinominato a `libxkbcommon` top-level**: rimossa lista manuale shared libs (Chromium NixOS è self-contained, rpath patchato).
- **Bug nix writer flake8 strict**: aggiunto `flakeIgnore` per E501/E741/W291/W293 sui CLI Python.

### Branding

- Palette **navy + oro** (precedente bordeaux deprecata)
- Tagline solo "AI-native OS", **nessun riferimento "Theory Holding"** nel branding UI/banner/logo/cert
- Logo SVG sun orb + Cormorant Garamond serif wordmark
- Plymouth `solar` theme (animazione sole, coerente con SOLEM = sole in latino)
- **Nessuna emoji** nell'UI (rispetta spec founder)

### Roadmap successiva

- **Step 1 (estate 2026)**: Beelink mini-PC bare-metal, secure-boot Lanzaboote, sops-nix secret, LUKS, mesh attiva con primo device esterno, Plymouth theme CUSTOM con logo SVG renderizzato in PNG
- **Step 2 (autunno 2026)**: estrazione L1+L2+L3 come moduli dedicati Supabase-backed, messaging E2E AES-256-GCM, multi-AI registry
- **Step 3 (2027)**: memoria 3 livelli con embedding (Jetson locale), device targeting, prima AI specialista oltre GAVIO
- **Step 4 (2028)**: multi-tenant pubblico, Extensions Marketplace v1, OAuth providers, RBAC granulare
- **Step 5 (2029+)**: linea hardware, distro custom, prodotto consolidato
