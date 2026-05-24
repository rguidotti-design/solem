# SOLEM — TODO live (lista concreta cose da fare)

> Aggiornata 2026-05-24 dopo commit `28ba44e` + batch app-compat/hw-firmware/installer.
> Le 4 regole utente:
> 1. App esistenti installabili (Linux/Windows/Android/multi-distro)
> 2. Risolvere problemi GRAVI per primi (vedi WEAKNESSES.md)
> 3. Lista TODO sempre aggiornata (questa)
> 4. **Tutto deve funzionare prima di andare avanti**

---

## ✅ FATTO oggi (questo turno)

- [x] `solem-app-compat.nix` — Flatpak + AppImage + Distrobox + Wine + Bottles + Waydroid + CLI `solem-install`
- [x] `solem-hardware-firmware.nix` — firmware OOTB + microcode + Bluetooth + sensors + fwupd + NVIDIA opt-in
- [x] `solem-installer-graphical.nix` — Calamares con branding navy/gold + slideshow QML 4 schermate
- [x] `docs/APP-COMPAT.md` — matrix completa app per OS d'origine + 5 quick start
- [x] `docs/TODO.md` (questo file)

---

## 🔴 BLOCCANTE — Aspetta verifica CI

Prima di continuare ad aggiungere capability, devo verificare che il commit corrente (`28ba44e`) compili.

### Cosa fare TU adesso

1. Vai su https://github.com/rguidotti-design/solem/actions
2. Apri l'ultimo run "SOLEM CI" → controlla:
   - 🟢 `Lint Nix` (warnings ok)
   - 🟢 `Flake check + VM tests`
   - 🟢 `Build vm` (matrix profili)
   - 🟢 `Build iso` (matrix profili)
   - 🟢/🟠 `vm-tests` (8 matrix)
3. **Se rosso**: copia in chat il **primo errore Nix** (cerca `error: ...` nei log)
4. **Se verde**: dimmelo e proseguo

### Cosa farò IO quando rosso

Pattern di errore → fix:
- `attribute 'X' missing` → `X` non esiste in nixpkgs-24.11 → rimuovo o sostituisco
- `option 'services.X' does not exist` → API cambiata → guard con mkIf o rimuovo
- `infinite recursion` → conflitto due moduli → mkDefault/mkForce
- `cannot coerce a function to a string` → typo sintassi
- `error: undefined variable X` → manca un `import`/let

---

## 🟠 PROSSIMI BATCH (in ordine di priorità WEAKNESSES.md)

### Batch A — Onboarding zero-knowledge (GRAVE #2)

- [ ] `solem-migration-tool` — wizard "trasferisci dati da Windows/Mac PC vecchio"
  - Source: USB / Samba SMB / SSH rsync
  - Estrae: `~/Documents` + `~/Pictures` + browser bookmarks + DA contatti
- [ ] `solem-trial-mode` — boot ISO live e dichiari "Voglio solo provare" → niente install, persistenza opzionale su USB
- [ ] `solem-account-quickstart` — al primo boot crea automaticamente:
  - GPG key (con email scelta dall'utente)
  - SSH key Ed25519
  - Vaultwarden master account
  - Nextcloud account (se cloud-personal attivo)

### Batch B — App ecosystem (GRAVE #3) — già parzialmente fatto

- [x] Flatpak + AppImage + Wine + Distrobox + Waydroid (questo turno)
- [ ] `solem-wine-presets` — Office 2016, Photoshop CS6, AutoCAD 2013 pre-configurati 1-click
- [ ] `solem-proton-ge` — Proton custom per Steam gaming (opt-in)
- [ ] `solem-heroic-launcher` — Epic/GOG/Amazon Prime launcher FOSS
- [ ] `solem-streaming-fix` — workaround Widevine L3 per Netflix/Disney+ 720p
- [ ] `solem-darling-experimental` — provare Darling (macOS emul) come opt-in sperimentale

### Batch C — Hardware OOTB completo (GRAVE #1)

- [x] firmware + microcode + Bluetooth + sensors + fwupd + NVIDIA (questo turno)
- [ ] `solem-printer-zero-config` — CUPS + Avahi + driverless IPP + sane-airscan
- [ ] `solem-webcam-fix` — v4l2loopback + GUI sceglie webcam preferita + virtual cam
- [ ] `solem-audio-pro` — PipeWire low-latency + EasyEffects + RNNoise noise-suppression
- [ ] `solem-suspend-fix` — hooks pre/post-suspend per Wi-Fi/USB/audio (bug ricorrenti Linux)
- [ ] `solem-keyboard-rgb` — openrgb + polychromatic gaming keyboard

### Batch D — UX/AI/Sync (SERI 4-7)

- [ ] `solem-mission-control` — overview workspace stile macOS Mission Control via Hyprland plugin
- [ ] `solem-spotlight-ml` — Spotlight con vector search semantico (whoosh + sentence-transformers locale)
- [ ] `solem-quick-look` — anteprima file con spazio (preview-handler GTK)
- [ ] `solem-universal-clipboard` — clip Windows/Mac → SOLEM via mesh KDE Connect
- [ ] `solem-airplay-receiver` — ricevi mirror schermo Mac/iPhone via Shairport-sync + uxplay (FOSS)
- [ ] `solem-gavio-wakeword` — "Hey GAVIO" sempre attivo via openWakeWord + LED privacy

### Batch E — Office/produttività (MEDIO #8)

- [ ] `solem-libreoffice-pro` — LibreOffice + estensioni IT + LanguageTool + Zotero connector + grammalecte
- [ ] `solem-collabora-online` — LibreOffice in browser + collaborazione realtime
- [ ] `solem-onlyoffice` — alternativa LibreOffice con compat MS Office migliore (AGPL)

### Batch F — Performance + bench (SERI #4 + LIEVE #15)

- [ ] `solem-benchmark` — script che esegue Phoronix Test Suite + boot-time + idle-RAM
- [ ] `solem-boot-budget` — `systemd-analyze` con target < 15s, alert se sfora
- [ ] `solem-zram-tuned` — preset memory per RAM 2/4/8/16 GB

### Batch G — Documentazione (LIEVE #13)

- [ ] Video YouTube 2 min "SOLEM in 120 secondi" (script + recording)
- [ ] subreddit r/solemos (creazione + 10 post seed)
- [ ] Matrix #solem:matrix.org community channel
- [ ] Sito statico GitHub Pages (solem-os.com? subdomain gh)

---

## 🟢 P1 — Validazione (sempre prima di P2/P3)

Ogni nuovo modulo aggiunto al **minimal** (`configuration-vm-minimal.nix`) richiede:

- [ ] CI verde per `Build vm` matrix
- [ ] CI verde per `Build iso` matrix
- [ ] Almeno 1 VM test che lo copre (`nixos/tests/<name>.nix`)
- [ ] CI verde per quel VM test

Ogni nuovo modulo opt-in (default off in `configuration.nix`) richiede:

- [ ] Pacchetti elencati esistono in nixpkgs-24.11 (verifica con `nix search nixpkgs#<pkg>`)
- [ ] `nix flake check --no-build` non logga errori sintassi
- [ ] Nessun pattern bug noto (vedi sotto)

### Pattern bug noti (lessons learned)

| Bug | Fix |
|---|---|
| `systemd.services.X.serviceConfig = {...}` senza guard | Wrappa in `lib.mkIf cfg.X.enabled` |
| `imports = [...]` duplicato in stesso file | Unico blocco imports |
| `services.X` con opzioni nuove non in 24.11 | Cerca `services.X` su https://search.nixos.org/options?channel=24.11 |
| `pkgs.NAME` package non esiste | Verifica https://search.nixos.org/packages?channel=24.11 |
| `kdePackages.X` vs `kdeFrameworks.X` vs `plasma5Packages.X` | Cambiati in 24.11, controlla namespace corretto |
| `lib.fakeSha256` | Sostituire con sha vera tramite `nix-prefetch-github` |

---

## 📊 Avanzamento percentuale

```
Modules totali:        145  (era 140 + 5 nuovi)
Modules nel minimal:   13   (era 11, +shell +clipboard +app-compat opt-in)
Home modules:          8
VM tests:              8
Workflow CI:           3   (build.yml + quick-validate.yml + release.yml)
Docs:                  27  (era 24 + APP-COMPAT + TODO + WEAKNESSES)
ADR:                   10
```

```
% reale stimato:           60-70%   (era 55-65, +5 con fix mkIf + app-compat docs)
% CI verde end-to-end:     0-50%    (dipende dal run corrente, dimmi tu)
% installabile su Beelink:  ~40%    (manca solo CI verde + USB ISO test)
% utente non-tecnico:        ~25%   (manca migration + trial-mode + UX P0)
```

---

## Come usare questo file

Ad ogni richiesta dell'utente:
1. **Marco le task in corso come `[in_progress]`**
2. **Aggiungo nuove task scoperte**
3. **Sposto in ✅ FATTO quando completate**
4. **Aggiorno % avanzamento**
5. **Mai sforare ai prossimi batch senza CI verde**
