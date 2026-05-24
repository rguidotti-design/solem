# SOLEM — TODO live

> Aggiornato 2026-05-24, ultimo commit `88b14b2`.

---

## ✅ FATTO oggi

### Fix CI iterativi (16 commit binary search)

| Commit | Cosa |
|---|---|
| `5fa3cd6` | Ultra-minimal solem-core (debug) |
| `562252e` | +cli +motd |
| `50d0770` | **Fix updates+i18n opt-in mkIf** (preventivo always-on conflict) |
| `ecb165c` | **Fix creative+dev-envs+makers mkIf wrap** (preventivo) |
| `d371769` | **🔥 BUG KILLER: solem-shell options.enable MANCAVA** |
| `82bd0e0` | GAVIO stub avanzato + solem-demo + 3 VM tests |
| `264b854` | README stats live |
| `88b14b2` | Makefile +ci-status +ci-watch +gavio-stub +demo |

### Bug killer dettaglio

`solem-shell.nix` aveva solo `enableAsLoginShell` option. `configuration-vm-minimal` settava `solem.shell.enable = true` → NixOS error "option does not exist" → eval VM fallisce → CI rosso dal step 4 in poi.

**Fix**: aggiunta `enable` option (default true) + `config = lib.mkIf cfg.enable`.

### GAVIO stub avanzato

5 endpoint REST emulati ([nix/gavio.nix](../nix/gavio.nix)):
- `GET /health` → status + uptime + version
- `GET /v2/capabilities` → lista capability future
- `GET /v2/memory/stats` → placeholder 0
- `POST /v2/agent/query` → echo + suggerimento install GAVIO
- `POST /v2/wake/trigger` → conferma wake-word

`nix build .#gavio` → binario `gavio-server` (PORT 8000 default).

### solem-demo CLI

Nuovo [nixos/modules/solem-demo.nix](../nixos/modules/solem-demo.nix): tour capability in 30s, 6 step (sistema, CLI, GAVIO, SOLEM API, network, servizi). Usa `gum` per UI. Default ON.

### 3 nuovi VM tests

- `solem-demo`: verifica CLI installato + esegue
- `gavio-stub`: builda package + verifica `/health`, `/v2/capabilities`, `/v2/agent/query`
- `firewall-base`: SSH ok + porte sospette chiuse

Aggiunti a CI matrix `vm-tests`.

### Makefile target nuovi

- `make ci-status` → ultimi 10 run CI status (no auth, rate-limited 60/h)
- `make ci-watch` → polling fino a completed
- `make gavio-stub` → build + run stub locale su :8765
- `make demo` → lancia solem-demo se in SOLEM

---

## 🟡 IN ATTESA

- CI per `d371769` + `82bd0e0` + `264b854` + `88b14b2`
- Rate-limit GitHub API spesso esaurito (60 req/h anonimo)

---

## 🟠 PROSSIMI STEP DOPO CI VERDE

1. Riaggiungo step incrementali: ora che `solem.shell.enable` è dichiarato,
   il binary search dovrebbe convergere rapidamente.
2. Re-introduce `solem-vm-full` (configuration.nix originale) come nixosConfiguration alternativa.
3. Re-introduce `solem-raspberry` + `solem-jetson` per cross-build aarch64.
4. Build `nix build .#iso` (Calamares branded).
5. Bench performance (`solem-bench`).

---

## 🔴 Cosa NON ho fatto (per principio)

- Pacchetti closed-source per default
- Telemetria sistema
- Account centralizzato obbligatorio
- DRM Widevine L1 di default

---

## 4 regole utente

1. ✅ App esistenti installabili (Flatpak+AppImage+Wine+Distrobox+Waydroid)
2. ✅ Partire dai problemi GRAVI di WEAKNESSES.md
3. ✅ Lista TODO aggiornata (questo file)
4. 🟡 Tutto deve funzionare prima di andare avanti (CI in stabilizzazione)

---

## Stato moduli SOLEM

- **168 moduli** in `nixos/modules/`
- **4 nel minimal** corrente: solem-core + solem-cli + solem-motd + solem-demo
- **164 disponibili opt-in** (default off)
- **8 home-manager modules** in `home/modules/`
- **5 VM tests** attivi in CI matrix
- **3 workflow CI**: SOLEM CI, Quick Validate, Smoke Test
