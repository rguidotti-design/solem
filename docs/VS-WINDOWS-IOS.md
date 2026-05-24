# SOLEM vs Windows + iOS — Gap reale per competere

> Aggiornato 2026-05-24. Onestà brutale.
> SOLEM è desktop-Linux (NixOS-based). Confronto:
> - **Windows 11** (desktop, 75% market share)
> - **iOS** (mobile, 28% globale; SOLEM mobile = PinePhone/PWA limitato)

---

## 🚨 Gap GRAVI con WINDOWS (impedisce migrazione massa)

### 1. App proprietarie native (no Wine, no Flatpak)

| App | Mercato | SOLEM oggi |
|---|---|---|
| **Microsoft Office 365** | aziende+studenti | ⚠️ LibreOffice (compat 80%); Office web/PWA OK; desktop via Wine instabile |
| **Adobe Photoshop CC** | designer | ⚠️ Krita+GIMP (alternative ottime); Wine CC limitato |
| **Adobe Illustrator/InDesign** | designer pro | ❌ Inkscape+Scribus alt; no Wine reale |
| **Adobe Premiere Pro / After Effects** | video pro | ❌ Kdenlive+DaVinci Resolve (DR free OK Linux!) |
| **AutoCAD** | architetti/ingegneri | ❌ FreeCAD/LibreCAD alt; AutoCAD Wine 2013-2018 |
| **SolidWorks** | meccanica | ❌ FreeCAD+OpenSCAD alt; SolidWorks NO |
| **Visual Studio** (non Code) | C#/.NET dev | ❌ Rider Linux (closed JetBrains); VSCodium open |
| **AutoCAD/MATLAB/SAP** | enterprise | ❌ alt FOSS limitate |
| **Affinity Designer/Photo** | designer mid-tier | ❌ no Wine, no native |

**Cosa serve**: campagna integrazione Wine + creazione preset Bottles per le top 20 app Windows. Già parziale in `solem-wine-presets.nix`.

### 2. Gaming AAA con anti-cheat

| Gioco | SOLEM oggi |
|---|---|
| **Fortnite** | ❌ Easy Anti-Cheat kernel-level non-Linux |
| **Valorant** | ❌ Vanguard kernel anti-cheat |
| **Call of Duty Warzone** | ❌ Ricochet anti-cheat |
| **Apex Legends** | ⚠️ EAC ha modalità Linux (Steam Deck), funziona via Proton |
| **GTA Online** | ⚠️ BattlEye Proton OK |
| **Steam library** | ✅ Proton-GE FOSS funziona benissimo (80% giochi) |
| **Epic Games** | ✅ Heroic Launcher FOSS |
| **GOG** | ✅ Heroic |
| **Amazon Prime Gaming** | ✅ Heroic |

**Cosa serve**: Niente, anti-cheat kernel-level richiede certificazione vendor che NON arriverà mai per Linux generico. SOLEM perde su 3-4 giochi specifici, vince su tutto il resto.

### 3. Hardware compatibility vendor

| Hardware | Windows | SOLEM oggi |
|---|---|---|
| Stampante Brother low-end | ✅ plug & play | ⚠️ brlaser/brgenml1lpr ok ma setup CUPS manuale |
| Scanner HP/Epson recent | ✅ vendor app | ⚠️ sane-airscan FOSS, alcuni modelli OK |
| Fingerprint Goodix moderno | ✅ Windows Hello | ❌ libfprint manca firmware Goodix recente |
| Webcam laptop integrata | ✅ sempre | ⚠️ Realtek/Mediatek hit-and-miss |
| GPU NVIDIA RTX 5xxx | ✅ driver giorno 1 | ⚠️ Nvidia driver 1-3 mesi delay |
| GPU AMD Radeon 7900 | ✅ | ✅ (driver mainline) |
| Touch tablet 2-in-1 | ✅ palm rejection | ⚠️ libinput migliora, ma rotation/pen-pressure dipende modello |
| Smart-card lettori USB | ✅ vendor driver | ⚠️ pcsc-lite FOSS (alcuni cit. CIE) |

**Cosa serve**: `solem-hardware-firmware.nix` opt-in con `nonFreeFirmware = true` per Broadcom/Realtek (già esiste). Però Goodix fingerprint non-FOSS firmware è bloccante per molti laptop business.

### 4. Onboarding "next-next-next finish"

| Step | Windows | SOLEM oggi |
|---|---|---|
| Boot ISO | grafico, mouse | ✅ Calamares (già brand SOLEM) |
| Auto-detect HW | sempre | ⚠️ NixOS hardware detection limitata |
| Migrazione da PC vecchio | Migration Assistant | ⚠️ `solem-migrate` esiste ma manuale |
| Account creation | Microsoft account 1-click | ⚠️ utente UNIX + GPG/SSH/mesh (3-4 step) |
| App store con login | Microsoft Store | ⚠️ Flathub OK ma niente account integrato |
| Activation key | "Windows is activated" | ✅ Open-source non serve |

**Cosa serve**: `solem-onboarding-wizard` esiste, ma serve UI grafica più amichevole (GTK4) invece di TUI gum.

### 5. Streaming 4K (DRM Widevine L1)

| Servizio | Windows | SOLEM |
|---|---|---|
| Netflix 4K HDR | ✅ Edge/app | ❌ Widevine L3 = max 720p |
| Disney+ 4K | ✅ | ❌ 720p |
| HBO Max 4K | ✅ | ❌ 720p |
| Amazon Prime 4K | ✅ | ❌ 720p |
| YouTube Premium 4K | ✅ | ✅ (no Widevine richiesto) |
| Twitch | ✅ | ✅ |
| Spotify | ✅ | ⚠️ Spotify Linux native sì, no Spotify HiFi |

**Cosa serve**: Widevine L1 richiede certificazione hardware vendor. Apple/Microsoft hanno. Linux NO.

### 6. UI desktop polished

| Feature | Windows 11 | SOLEM oggi |
|---|---|---|
| Snap Layouts (4 finestre auto) | ✅ | ⚠️ Hyprland tiling è diverso, più tecnico |
| Notification Center | ✅ | ✅ mako (CLI/Wayland) |
| Quick Settings panel | ✅ | ⚠️ eww popover scritto da utente |
| Taskbar widgets | ✅ | ⚠️ waybar minimal |
| Start menu search universal | ✅ con Bing/Copilot | ⚠️ `solem-find` CLI |
| Dark/Light mode system-wide | ✅ instant | ⚠️ GTK+Qt theme manuale |
| HiDPI 200% multi-monitor | ✅ perfetto | ⚠️ Wayland scaling OK ma X11 broken |
| Touch UX 2-in-1 | ✅ Tablet mode | ⚠️ Wayland ok, gesture limitate |

### 7. Cloud sync trasparente

| Servizio | Windows | SOLEM oggi |
|---|---|---|
| OneDrive (Files trasparente) | ✅ integrato Explorer | ❌ Nextcloud sync ok, ma 'OneDrive feeling' assente |
| Edge sync favoriti/password | ✅ Microsoft account | ⚠️ Firefox sync (FOSS), Vaultwarden self-host |
| Clipboard sync cross-device | ✅ Microsoft Account | ⚠️ `solem-clip` esiste (LAN HTTP) |
| Phone Link Android | ✅ KDE Connect-alt | ✅ KDE Connect FOSS! |

---

## 🚨 Gap GRAVI con iOS (impedisce parity mobile)

### 1. Ecosistema device Apple

Tutto questo è chiuso e impossibile da replicare:

- **iMessage** (RCS aiuta ma non sostituisce)
- **FaceTime** (Jami/Jitsi alt aperte)
- **AirDrop** (LocalSend è equivalente FOSS)
- **Apple Watch** (PineTime/Bangle.js alt FOSS)
- **AirPlay** (uxplay/shairport-sync RX OK, TX no)
- **CarPlay** (no Linux car integration)
- **Apple Pay** (no NFC + Secure Enclave senza Apple)
- **Find My** (no rete BLE crowd-sourced)

### 2. App quality

- iOS App Store: 4M+ app **curate**, NESSUNA malware reale
- Flathub: 2k app FOSS, qualità variabile (alcune obsolete)
- F-Droid (Android FOSS): ~3k app, qualità variabile

### 3. Hardware integrato

- iOS gira solo su iPhone: CPU + GPU + sensori + camera tutti ottimizzati Apple
- SOLEM mobile = PinePhone (CPU debole, fotocamera mediocre, GPS lento)
- Smartwatch Linux FOSS: in via di sviluppo

### 4. Privacy marketing

- Apple ha campagne miliardarie "Privacy" (cinico ma efficace)
- SOLEM ha 0 € marketing budget

### 5. Continuity / handoff

- iOS+macOS: copia su Mac → incolla su iPhone, **zero setup**
- SOLEM: serve LocalSend + KDE Connect + impostare pairing

---

## ✅ Dove SOLEM VINCE già

| Vantaggio | Windows | iOS | SOLEM |
|---|---|---|---|
| **Costo licenza** | $139 Pro | $999+ device | **0 €** |
| **Privacy** | telemetria heavy | privacy marketing | **zero telemetria** |
| **Vendor lock-in** | Microsoft | Apple | **zero** |
| **Hardware libero** | OEM-specifico | Apple-only | **qualsiasi x86_64/ARM64** |
| **FOSS-purity** | closed | closed | **100% FOSS default** |
| **Customization** | limitata | quasi zero | **totale (Nix dichiarativo)** |
| **Rollback aggiornamenti** | difficile | Time Machine | **NixOS generation rollback 1-click** |
| **AI native** | Copilot (cloud) | Apple Intelligence (cloud+device) | **GAVIO local-first (in costruzione)** |
| **Reproducible builds** | ❌ | ❌ | **✅ Nix garantito** |
| **Multi-device same OS** | desktop only | mobile only | **workstation/server/laptop/edge/glass** |
| **Self-host nativo** | richiede 3rd party | impossibile | **integrato (Nextcloud/Vaultwarden/...)** |

---

## 🎯 Roadmap 12 mesi per competere

### Q1 — Hardware OOTB

- Risolvere fingerprint Goodix (workaround userspace o supporto custom firmware redistribuibile)
- Audio "just works" (PipeWire low-latency preset)
- Wi-Fi 6E/7 driver mainline (Intel BE200/BE201)
- Webcam Realtek HD firmware

### Q2 — Onboarding GUI

- Calamares branding completo screenshot (oggi solo testo)
- GTK4 onboarding wizard (anziché TUI gum)
- Migration tool reale (Windows USB → SOLEM home)

### Q3 — App ecosystem polish

- Bottles preset Office 2016/2019, Photoshop CS6, AutoCAD 2013-2018
- Proton-GE custom autoupdate
- DaVinci Resolve helper script (~ ok su Linux)
- Steam Deck-like preset gaming

### Q4 — AI native

- GAVIO reale impacchettato come Nix derivation
- Wake-word "Hey GAVIO" funzionante con model FOSS
- Context-aware overlay (Super+G chiama AI con clipboard/selezione)
- Mobile: PWA glass + smartphone con sync conversation

### Always — Marketing/Community

- Video YouTube "SOLEM in 2 minuti"
- Sito statico GitHub Pages
- Subreddit r/solemos
- Matrix #solem:matrix.org

---

## 🤔 Cosa NON proveremo a fare (per principio)

- **iMessage / FaceTime / AirPlay TX**: impossibile FOSS, lasciamo perdere
- **Anti-cheat AAA games**: vendor decision, non OS
- **Adobe CC nativo**: Adobe non porterà mai su Linux/SOLEM
- **Widevine L1 4K streaming**: serve hardware Apple/Microsoft cert
- **Microsoft Office 365 desktop full**: SOLEM userà OnlyOffice/LibreOffice + web
- **Walled garden app store**: lo store SOLEM resta aperto

---

## Numeri reali (oggi)

| Categoria | Windows score | iOS score | SOLEM score |
|---|:---:|:---:|:---:|
| Hardware OOTB | 9/10 | 10/10 | **6/10** |
| Onboarding | 9/10 | 10/10 | **4/10** |
| App ecosystem | 10/10 | 10/10 | **6/10** |
| Performance | 7/10 | 9/10 | **? (mai misurato)** |
| Privacy | 2/10 | 6/10 | **10/10** |
| Costo | 3/10 ($139+) | 1/10 ($999+) | **10/10 (0 €)** |
| Customization | 5/10 | 1/10 | **10/10** |
| Reproducible | 0/10 | 0/10 | **10/10** |
| AI native | 7/10 (Copilot) | 8/10 (Apple Intel) | **5/10 (GAVIO stub)** |
| **Media** | **6.4/10** | **6.1/10** | **7.4/10** |

**Sintesi**: SOLEM PERDE su hardware/onboarding/app proprietarie, **VINCE complessivamente** grazie a privacy+costo+customization+reproducible.

**Per la maggior parte degli utenti home + dev + tech-savvy**, SOLEM è già la scelta migliore. Per **utenti generic + designer Adobe + gamer AAA + enterprise**, mancano feature critiche difficili da chiudere.
