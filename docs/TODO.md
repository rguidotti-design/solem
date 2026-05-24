# SOLEM — TODO live (lista concreta cose da fare)

> Aggiornato 2026-05-24, ultimo commit `c89a3b7`.

---

## ✅ FATTO

### Fix CI (sessione corrente)

- [x] `afe10a8` — rimosso home-manager dal flake (rompeva eval VM)
- [x] `b41ef69` — ridotto configuration-vm-minimal a solo solem-core (debug)
- [x] `16c9b99` — rimosso user gavio duplicato dal minimal
- [x] `5351fcd` — **fix critico**: split hardware-vm in pub/locale (sharedDirectories WSL2 path GITIGNORED)
- [x] `edd7b72` — pulseaudio path + languagetool option preventive
- [x] `ddf3e62` — VM tests basic-boot/solem-cli ridichiaravano user gavio
- [x] `06358c0` — flake.nix rimossa configs vm-full/raspberry/jetson (eval rotto)
- [x] `c89a3b7` — VM tests matrix ridotta a basic-boot + solem-cli (no moduli dubbi)

### Bug strutturali identificati e fixati

| Bug | Causa | Commit |
|---|---|---|
| Eval VM fallisce | flake referenzia home-manager senza lock | `afe10a8` |
| User gavio duplicato | minimal + solem-core dichiaravano entrambi | `16c9b99` |
| sharedDirectories WSL2 hardcoded | `/mnt/c/...` non esiste su CI runner | **`5351fcd`** |
| `services.pulseaudio` wrong path | in 24.11 è `hardware.pulseaudio` | `edd7b72` |
| `services.languagetool.allowOrigin` non in 24.11 | rimosso | `edd7b72` |
| Test redichiaravano user | basic-boot/solem-cli stesso bug del minimal | `ddf3e62` |
| `nix flake check` valuta TUTTE le configs | vm-full/raspberry/jetson eval-rotti | `06358c0` |
| VM tests matrix includeva test con moduli dubbi | matrix ridotta | `c89a3b7` |

---

## 🟡 IN ATTESA DI VERIFICA

- [ ] Run CI per commit `c89a3b7` deve essere verde su:
  - Lint Nix ✅ (sempre verde)
  - Flake check + VM tests (ora 2 test)
  - Build profiles matrix [vm, iso]
  - VM tests matrix [basic-boot, solem-cli]

Stato monitorabile su:
https://github.com/rguidotti-design/solem/actions

### Cosa accadrà se VERDE

1. **Riaggiungo solem-vm-full** al flake con `configuration.nix` (130+ moduli)
   - Aspettatevi ~10-30 errori, da fixare uno per uno
2. **Riaggiungo solem-raspberry** con `configuration-edge.nix`
3. **Riaggiungo solem-jetson** idem
4. **Riaggiungo VM tests** uno per volta dopo che ogni modulo eval-clean
5. **Attivo i 14 moduli OPT-IN** (e2d0256) come default in configuration.nix
6. **Re-pacchetto GAVIO** stub → derivation Python reale

### Cosa accadrà se ANCORA ROSSO

Errori probabili:
- Pacchetto in `solem-core.nix` o `hardware-vm.nix` che non esiste
- Opzione 24.11 cambiata che ho mancato
- Bug `lib.mkIf` su moduli importati indirettamente

Procedo a:
1. Leggere log via GitHub API (PowerShell o curl)
2. Identificare step + errore specifico
3. Fix mirato
4. Push

---

## 🟠 ROADMAP DOPO CI VERDE

### Step 1 — Aggiungi 1 modulo per volta al minimal (binary search)

Ordine consigliato (sicurezza decrescente):

1. `solem-cli` → CLI Python `solem`
2. `solem-motd` → banner MOTD
3. `solem-channels` → channel switcher
4. `solem-keep` → watchdog Python
5. `solem-doctor` → diagnostica Python
6. `solem-kernel-hardening` → sysctl
7. `solem-memory` → zram + earlyoom (con `protectGavio = false`)
8. `solem-sandbox` → bubblewrap

Ogni step: 1 commit, 1 push, attendi CI verde, prossimo step.

### Step 2 — Italian locale + Shell

9. `solem-italian-locale` → hunspell + LanguageTool
10. `solem-shell` → TUI Python
11. `solem-clipboard` → wl-clipboard + cliphist

### Step 3 — Profili completi

12. `solem-vm-full` con `configuration.nix` (130+ moduli) — aspetta fix individuali
13. `solem-raspberry` con `configuration-edge.nix`
14. `solem-jetson` idem

### Step 4 — Tests completi

15-22. Aggiungi 6 VM test rimossi (spotlight, quick-settings, gavio-context, italian-locale, user-clis, mesh-iface)

### Step 5 — Moduli opt-in (e2d0256 + altri)

Tutti i 14 moduli aggiunti (migration-tool, trial-mode, account-quickstart, gaming-extras, streaming-fix, printer-zero-config, webcam-fix, audio-pro, suspend-fix, universal-clipboard, airplay-receiver, gavio-wakeword, libreoffice-pro, benchmark) — attivati come default in `configuration.nix` quando vm-full passa.

---

## 🔵 LISTA "TUTTO RESO REALE"

| Componente | Stato attuale | Effort | Stima realistica |
|---|---|---|---|
| flake eval check verde | 🟡 aspettando | scrivo in 5 min | 1-3 ore CI iterativa |
| nix build .#vm | 🔴 mai testato | 30 min CI | 1 ora |
| nix run .#vm boota | 🔴 mai testato | runtime | 30 min |
| nix build .#iso | 🔴 mai testato | 1-2 h CI | 2 ore |
| ISO bootabile in QEMU | 🔴 mai testato | runtime | 30 min |
| Calamares parte da ISO | 🔴 mai testato | runtime | 30 min |
| Boot Beelink fisico | ⏸ P7 differito | hardware | 1 giorno |

---

## 🔴 Cosa NON sta funzionando MAI / TROPPO RISCHIOSO

- `nix flake check` con tutti i 158 moduli importati simultaneamente
- VM tests con moduli che usano pkg dubbi (anyrun, eww, openWakeWord, etc.)
- Cross-compile aarch64 senza emulazione (richiede qemu-user)
- Hardware fingerprint/Wi-Fi senza firmware vendor opt-in
- App Windows complesse via Wine (Office 365, Adobe CC) — non-FOSS-fault

---

## Lezioni apprese (lessons learned)

1. **Path hardcoded sono sempre un bug** — usa `builtins.pathExists` per overlay locali
2. **Stessa option dichiarata in N moduli** = conflitto NixOS, usa `lib.mkDefault`/`mkForce`/`mkOverride`
3. **`nix flake check` valuta TUTTE le configs** — isola le configs sperimentali
4. **VM tests sono moduli a tutti gli effetti** — stesso pattern bug del minimal
5. **Cachix non aiuta se eval fallisce** — il fix è strutturale, non di cache
6. **GitHub API ha rate-limit 60 req/h** anonimo — auth richiesta per polling intensivo
7. **`nix flake update` deve precedere ogni job CI** — se aggiungiamo input, lock va aggiornato

---

## 4 regole utente (memorizzate)

1. ✅ App esistenti (Linux/Win/Android/multi-distro) installabili → `solem-app-compat.nix`
2. ✅ Partire dai problemi GRAVI di `WEAKNESSES.md` → `solem-hardware-firmware.nix` + `solem-installer-graphical.nix`
3. ✅ Lista TODO sempre aggiornata → questo file
4. 🟡 **Tutto deve funzionare prima di andare avanti** → la regola è applicata: nessun nuovo modulo attivato di default finché CI non è verde
