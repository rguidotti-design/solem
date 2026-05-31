# SOLEM — Cosa manca per essere un VERO OS

Onestà brutale: SOLEM ha 41+ step di sicurezza + Friday mode + 100+ moduli
Nix, ma per essere un **OS sostitutivo di Windows/macOS** per utente
non-tecnico mancano ancora cose serie.

Ultimo aggiornamento: 2026-05-31.
Stato CI: 15/15 VM test verdi, build vm+iso OK.

---

## ✅ Cosa già fatto bene (vs Windows/macOS)

| Area | SOLEM ✅ | Windows / macOS |
|------|--------|-----------------|
| Sicurezza zero-trust | 41+ step | minimi |
| Auto red-team + heal | sì | no |
| Source open audit | tutto FOSS | proprietario |
| Privacy default | tutto locale | telemetria |
| Costo licenze | 0 € | 100-300 € |
| Hardware compat lockdown | TPM + Secure Boot | meglio |
| Update model | rollback-safe NixOS gen | reboot loop |
| Disk encryption + TPM unlock | scaffolding | BitLocker (Win) |

---

## ❌ GAP CRITICI (impediscono adozione mainstream)

### 1. Hardware support automatico
**Stato**: parziale.
**Manca**:
- Auto-detect Wi-Fi proprietario (Broadcom, Realtek closed firmware)
- GPU driver wizard (NVIDIA proprietario, AMD ROCm, Intel)
- Stampanti USB plug-and-play (CUPS + driver vendor)
- Webcam/microfono permission UI (al primo uso app)
- Touchpad gestures fine-tuning (libinput diverso da vendor)
- Sleep/wake/hibernate testato su 10+ laptop model
- Battery management UI con stima ore (non solo CLI)
- Brightness shortcuts via keyboard FN keys
- Multi-monitor hot-plug DPI scaling

**Cosa serve**: hardware-detect module che al boot identifica vendor
+ propone install driver (auto-yes opt-out). NixOS hardware-configuration.nix
e nixos-hardware repo coprono molto MA richiede expertise utente.

### 2. App store visuale
**Stato**: CLI (nix-env, solem-app smart-install).
**Manca**:
- GUI tipo GNOME Software / Discover
- Browse categorie, search, screenshot, ratings
- One-click install + dependency resolution UI
- Update manager visuale (oltre notify-send)

**Cosa serve**: pacchettizzare `gnome-software` + flatpak backend.
Su NixOS funziona MA UX rough vs Windows Store.

### 3. Settings GUI centralizzato
**Stato**: CLI (`solem <area> <action>`) + Web Dashboard (Step 36).
**Manca**:
- Pannello settings tipo GNOME Settings / System Preferences macOS
- Wi-Fi/Bluetooth picker visuale (oltre nm-applet)
- Display arrangement drag-and-drop
- Sound output picker GUI
- Power management plans visuali
- User account management GUI (creare utente, password, foto)

**Cosa serve**: configure `gnome-control-center` o KDE Plasma settings
come default invece di solo Hyprland config files.

### 4. Localization completa
**Stato**: locale it_IT.UTF-8 settato, keymap italiano.
**Manca**:
- Tutti i menu/dialog tradotti (Hyprland config in inglese)
- CLI SOLEM messaggi: parzialmente italiano, parzialmente inglese
- Help docs (`/etc/solem/*.md`): mix italiano/inglese
- Welcome wizard: italiano OK
- Manuale utente non-tecnico

**Cosa serve**: i18n consistency pass su tutti i CLI SOLEM + traduzione
help text completa.

### 5. Mobile companion app
**Stato**: nessuna.
**Manca**:
- PWA mobile per controllo remoto SOLEM
- Notification push real-time (alert IDS, redteam buchi)
- Voice command da phone via WireGuard mesh
- File sync trasparente (oltre Nextcloud manuale)
- Glass/wearable interface

**Cosa serve**: progetto separato — react/svelte PWA che parla con
GAVIO API via mesh WG.

### 6. GAVIO packaging completo
**Stato**: scaffolding (Step 30) — utente deve fornire src.
**Manca**:
- GAVIO pyproject.toml definitivo
- Dependency resolution tutte le 50+ libs Python listate
- Build deterministic con poetry2nix / uv2nix
- Modelli LLM Ollama auto-prepull testato end-to-end
- Voice/STT/TTS pipeline integrato
- Multi-AI registry (gavio core + coder + researcher + writer)

**Cosa serve**: derivare il GAVIO Desktop repo + applicare Step 30
con tutte le dependencies + test boot-to-conversation reale.

### 7. Recovery & maintenance UX
**Stato**: NixOS rollback boot menu (built-in), generation cleanup CLI.
**Manca**:
- Recovery USB builder GUI ("crea USB SOLEM rescue")
- Disk image / restore con timeshift-like UX (oltre borg CLI)
- Health check dashboard reale (CPU/RAM/disk graphs storici)
- Hardware diagnostic tool (test RAM, SMART, network)
- One-click "factory reset" (riporta a stato install)

**Cosa serve**: GUI wrappers su tool che gia' esistono + storage time-series.

### 8. Bug reporting + telemetria opt-in
**Stato**: nessuno (per design FOSS no-telemetry).
**Manca**:
- Anonymous crash reporting opt-in (tipo Mozilla)
- Bug tracker integrato (apri issue GitHub dal sistema)
- Performance regression tracking
- Update success/fail telemetry (per stable channel)

**Cosa serve**: scelta filosofica utente. Se rimaniamo "100% no
telemetry", manca segnale per migliorare. Se opt-in: rispettare privacy
massima (no UUID persistente, ecc.).

### 9. Distribuzione
**Stato**: ISO buildabile via CI, no canale download.
**Manca**:
- Sito web ufficiale solem.so (o simile)
- Mirror CDN per ISO download
- Verifica signature ISO (GPG signed releases)
- Update channel: stable / beta / nightly
- Documentation site (mdbook / docusaurus)
- Community Discord/Matrix/forum
- Onboarding "Try SOLEM" senza install (live USB)

**Cosa serve**: progetto separato (web + ops) per release engineering.

### 10. Software ecosystem
**Stato**: NixOS nixpkgs (~80k packages disponibili).
**Manca**:
- Sviluppatori che pacchettizzano per SOLEM specifically (non NixOS)
- Vendor app vendor partnership (Adobe, Autodesk, ecc.) → improbabile
- Game support testato (Steam/Proton): NixOS lo supporta MA UX rough
- Wine/Bottles preset per Win app comuni

**Cosa serve**: questo è il gap più grosso e meno controllabile. NixOS
ha tutto, ma l'utente deve sapere usare Nix. SOLEM dovrebbe nascondere
il Nix dietro UX semplice.

### 11. Performance baseline
**Stato**: pochi benchmark.
**Manca**:
- Boot time misurato vs Win/mac (target: < 10s)
- Idle RAM footprint comparison
- First-app-launch latency
- Battery life testato su laptop (target: parity con vendor OS)
- Suspend resume time
- Display latency / input lag

**Cosa serve**: benchmark suite + ottimizzazione mirata.

### 12. Multi-tenant / family
**Stato**: single-tenant (utente "gavio").
**Manca**:
- Multi-user con permission separation runtime
- Family account / parental controls
- Guest session ephemeral (login automatic, no persist)
- User switcher GUI
- Shared family device flow

**Cosa serve**: rilassare assunzioni single-tenant di vari moduli.

---

## ⚠️ GAP MEDI (utente tecnico vive senza)

- Voice interface (Step 41 fatto MA richiede setup + modelli download)
- Self-update automatic (Step 14 fatto MA serve test long-term)
- TPM measured boot (Step 35 scaffolding, no boot integration)
- dm-verity readonly /nix/store (Step 28 scaffolding)
- Secure Boot lanzaboote (Step 32 esiste, no auto-enroll)
- Tor onion (Step 29 fatto, no metric su quanti lo usano)
- Backup encrypted (Step 17 fatto, dipende da utente init)

---

## ⚠️ GAP MINORI (cosmetici / polish)

- Wallpaper picker GUI
- Icon theme picker
- Font picker GUI
- Cursor theme
- Animation speed setting
- Window decorations alternative
- Login screen branding (greetd config già navy/gold)
- Splash screen custom (Plymouth già navy/gold)

---

## 📊 SOMMARIO: quanto manca

| Area | % completato | Effort restante |
|------|--------------|-----------------|
| Security core | **95%** | minimo |
| Network management | 90% | piccolo |
| AI integration (GAVIO) | 60% | medio (packaging) |
| Hardware support | 50% | grande (driver wizard) |
| User-facing apps | 40% | medio (UX polish) |
| Settings GUI | 30% | grande (porting GNOME) |
| Installer UX | 60% | piccolo (test boot-install) |
| Localization | 50% | medio (i18n pass) |
| Mobile companion | 0% | grande (progetto nuovo) |
| Distribution/community | 5% | enorme (ops + marketing) |
| **MEDIA** | **~55%** | **~12-18 mesi full-time** |

---

## 🎯 ROADMAP REALISTICA (in ordine di impatto)

### Fase 1 — 3 mesi (rendere usable per power user)
1. GAVIO packaging completo (Step 30 reale, no scaffolding)
2. Hardware-detect wizard + driver auto-install
3. ISO test boot-to-desktop reale (VirtualBox + 3 laptop fisici)
4. User-facing localization complete italiano
5. Recovery USB builder GUI

### Fase 2 — 3 mesi (rendere usable per utente medio)
1. Settings GUI (GNOME Control Center integrato)
2. App store visuale (GNOME Software)
3. Voice interface end-to-end testato
4. Performance optimization (boot time, idle RAM)
5. Multi-user / family support

### Fase 3 — 6+ mesi (mass adoption)
1. Sito web + download CDN
2. Documentation site mdbook
3. Community Discord/forum
4. Mobile PWA companion
5. Vendor partnerships (Lenovo? Framework?)

---

## CONCLUSIONE ONESTA

**SOLEM oggi è**:
- Un sistema NixOS hardenato eccezionalmente con 41+ step security
- Un container zero-trust dimostrato e testato per GAVIO
- UN OS PER UTENTE TECNICO che sa usare Nix / linea di comando
- L'**INFRASTRUTTURA SOLIDA** per costruire un OS user-facing

**SOLEM NON è ancora**:
- Un sostituto di Windows/macOS per utente normale
- Un prodotto pronto da distribuire mass-market
- Una soluzione one-click per chi non sa cosa è una shell

**Tempo onesto per "vero OS" mass-market**: 12-18 mesi full-time per
1-2 sviluppatori. Solo per la PARTE UX/polish (la core security è
fatta).

**Cosa SOLEM fa MEGLIO di qualsiasi mainstream OS**: sicurezza
zero-trust per AI ospitata. Quello è il nicho. Se l'OS rimane
per "developer/researcher AI-paranoid", e' GIA' MOLTO BUONO.
Se aspira a essere Windows-killer, ~1 anno di lavoro UX/polish.
