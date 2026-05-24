# SOLEM — Realtà BRUTALE (cosa manca davvero)

> 2026-05-24. **Niente marketing self-congratulatory.**
> Lo score 8.8/10 vs colossi era falso. Ecco la verità.

---

## ❌ La verità su quello che abbiamo "fatto"

I 21 moduli che ho aggiunto sono **file `.nix` con script bash**. Quello che **NON è successo**:

- **Mai bootato SOLEM su un computer reale.** Solo VM teorica, mai testata.
- **Mai compilato l'ISO funzionante.** Build vm passa, build iso fail.
- **Mai un utente vero ha usato SOLEM.** Zero utenti.
- **GAVIO è uno STUB.** Risponde `{"status":"stub"}`. Nessun LLM reale.
- **CI verde solo su Quick Validate**, non sui VM tests veri.

I 21 moduli sono **dichiarazioni**, non **prova esecutiva**. Tra "dichiarare in NixOS" e "funziona davvero" c'è un abisso testato in ZERO casi.

---

## ❌ Gap REALI che mancano (lista lunga)

### App native (impossibile chiudere completamente)

| App | Mercato | Stato SOLEM | Realtà |
|---|---|---|---|
| Adobe Creative Cloud (Photoshop/Illustrator/Premiere) | 30M user | ❌ | Wine CS6 instabile, CC zero |
| Microsoft Office 365 desktop | 400M user | ⚠️ | LibreOffice/web, Wine 2016 fragile |
| iMessage / FaceTime | 1.5 miliardi Apple users | ❌ | Impossibile FOSS |
| Apple Music HiFi lossless | 100M sub | ❌ | Spotify Linux ok, no HiFi |
| Netflix 4K HDR | 270M sub | ❌ | Widevine L1 vendor-only |
| Disney+ / HBO Max / Prime 4K | 300M+ | ❌ | Stesso problema |
| Spotify HiFi | premium tier | ❌ | requires account+device cert |
| AutoCAD / SolidWorks | architetti/ingegneri | ❌ | Wine 2013-2018 only, no recent |
| Final Cut Pro / Logic Pro | creator pro Apple | ❌ | macOS-only |
| Steam AAA con anti-cheat (Valorant/Fortnite/CoD) | 50M+ player | ❌ | Kernel anti-cheat blocca Linux |
| App banche italiane (Intesa, Unicredit, PostePay) | 30M IT | ❌ | Solo iOS/Android native |
| App PA italiane (IO, PosteID, FastPay) | 20M IT | ❌ | Solo iOS/Android |

**Cosa serve**: niente è chiudibile per principio FOSS. Wine non basta. Web app sì ma esperienza degradata.

### Hardware vendor (driver delay reali)

| Hardware | Stato Linux mainline |
|---|---|
| Wi-Fi 7 (Intel BE200/BE201) | Driver kernel 6.6+, alcuni laptop ancora rotti |
| Wi-Fi 6E (recente) | OK in 6.5+ |
| Broadcom Wi-Fi (MacBook) | wl-driver non-FOSS opt-in |
| NVIDIA RTX 5xxx 2025+ | Delay 1-3 mesi vs Windows |
| AMD GPU recenti | Mainline OK |
| Fingerprint Goodix 5xx/6xx (Lenovo recent) | libfprint manca firmware Goodix |
| Fingerprint Synaptics (Dell) | OK |
| Webcam Realtek HD (ThinkPad) | Hit/miss per modello |
| Lettori CIE 3.0 (Italia) | pcsc-lite + workaround vendor closed |
| Smart card NFC bancarie | Spesso closed driver vendor |
| Stampante Brother low-end | brlaser FOSS funziona ma setup CUPS manuale |
| Scanner Epson recent | sane-airscan FOSS, ok ~ 70% |
| Touch palm rejection convertibili 2-in-1 | libinput migliora ma instabile su molti laptop |
| Speaker laptop con DSP custom (Dell XPS, ThinkPad) | EQ/profilo audio assente, suono peggiore Windows |

**Cosa serve**: niente fixabile da SOLEM solo. Serve cooperazione vendor con kernel mainline. Non succederà per tutti i modelli mai.

### Sleep / Resume reliability (bug ricorrenti)

| Bug | Frequenza Linux | Windows |
|---|---|---|
| Wi-Fi non riconnette dopo wake | comune (rtw_8821ce, btusb) | raro |
| Audio muto dopo resume | medio | raro |
| Display nero permanente dopo resume | medio | raro |
| Battery drain in s2idle | comune (vs S3) | raro |
| Suspend then-hibernate (battery save) | manuale | builtin |

**Cosa serve**: hook script per-modello (`solem-suspend-fix` ha framework, ma serve testing su 100+ laptop reali).

### UX desktop polished

| Feature | macOS/Win 11 | SOLEM |
|---|---|---|
| HiDPI 200% perfetto multi-monitor | ✅ | ⚠️ Wayland migliora, X11 broken |
| Touch tablet mode polished | ✅ | ⚠️ Hyprland touch limitato |
| Dark mode instant tutta UI | ✅ | ⚠️ `solem-theme` esiste, alcuni app non rispettano |
| Notification center con history clickable | ✅ | ⚠️ mako CLI, history sì ma UI plain |
| Quick Settings panel native | ✅ | ⚠️ eww config script, non integrato |
| Snap Layouts 4 finestre snap | ✅ | ✅ binds Super+freccia (richiede config user) |
| Boot 8s, wake 1s | ✅ | ❓ mai misurato |
| Animazioni 60fps | ✅ | ✅ Hyprland sì (con GPU adeguata) |
| Help center in-system | ✅ | ❌ zero |
| Setup wizard grafico (GTK) | ✅ | ⚠️ solo TUI gum |
| Onboarding tutorial video | ✅ | ❌ zero |
| App store con login | ✅ | ⚠️ `solem-app` CLI, no GUI |

### Cloud sync seamless ("feel" iCloud/OneDrive)

| Feature | macOS+iOS | Windows+M365 | SOLEM |
|---|---|---|---|
| Backup automatico foto telefono | iCloud Photos | OneDrive Camera | ⚠️ Immich opt-in |
| Sync trasparente file in Explorer | ✅ | ✅ | ❌ rclone mount manuale |
| Sync password keychain | ✅ | ✅ Edge | ⚠️ Vaultwarden self-host |
| Sync clipboard Mac↔iPhone | ✅ | ✅ Cloud Clipboard | ⚠️ LAN only, no internet |
| Find My device (laptop perso) | ✅ | Find My Device | ❌ zero |
| Family Sharing trasparente | ✅ | ✅ | ⚠️ shell-based |
| Photo memories ML auto-album | ✅ | OneDrive AI | ⚠️ digiKam manuale |
| Sync notes/calendar/contatti | ✅ | ✅ | ⚠️ CalDAV/khal richiede config |

### AI native vs Copilot / Apple Intelligence

| Feature | Win Copilot | Apple Intelligence | SOLEM |
|---|---|---|---|
| LLM locale always-on | Copilot+ AI 16GB RAM | Apple silicon 8GB | ❌ GAVIO STUB |
| Wake word always listening | Cortana (limitato) | Hey Siri (sempre) | ❌ zero |
| Email auto-summary | Outlook | Apple Mail | ❌ zero |
| Meeting transcript live | Teams/Recall | macOS Notes | ⚠️ solem-caption manuale |
| Image generation in-app | Designer | Image Playground | ❌ zero |
| Smart compose | Word | Mail | ❌ zero |
| Context-aware overlay (selezione) | Copilot | Writing Tools | ⚠️ Super+G chiama STUB |
| Notification triage | Copilot+ | Apple Intel | ❌ zero |
| Photo cleanup ML | OneDrive | Clean Up | ❌ zero |

### Mobile (gap enorme)

| Categoria | iOS / Android | SOLEM |
|---|---|---|
| App quality | 4M+ curate | F-Droid 3k variabili |
| Banca / Wallet | Apple/Google Pay | ❌ |
| Smartphone | iPhone / Pixel hardware ottimizzato | PinePhone CPU debole |
| Smartwatch | Apple Watch / Wear OS | PineTime base |
| Auto integration | CarPlay / Android Auto | ❌ |
| Family Sharing | trasparente | ⚠️ shell |
| Photo cloud | iCloud Photos / Google Photos AI | ⚠️ Immich opt-in |
| AirDrop / Quick Share | ✅ zero setup | ⚠️ LocalSend con setup |
| Notifiche unificate | ✅ | ⚠️ KDE Connect parziale |

### Performance / benchmark (mai misurato)

| Metric | Windows 11 | macOS | SOLEM |
|---|---|---|---|
| Boot cold start | 12s media | 10s | ❓ mai testato |
| Wake from sleep | 1-2s | < 1s | ❓ |
| Idle RAM | 2 GB | 1.5 GB | ❓ |
| Battery laptop tipico | 8h | 18h | ❓ |
| Audio latency PipeWire/CoreAudio | 8ms | 5ms | ❓ |
| Boot to desktop | 15s | 12s | ❓ |
| First Chrome window | 1-2s | 1s | ❓ |
| Gaming FPS overhead | baseline | +5-15% via Proton | ❓ |

**Score "performance 8/10" che ho scritto era inventato. Realtà: ZERO numeri.**

### Brand / community / awareness

| Asset | macOS/Win | SOLEM |
|---|---|---|
| Utenti | 1 miliardo+ | **0** (a parte l'autore) |
| Riconoscimento brand | universale | zero |
| Tutorial YouTube | milioni | **0** |
| Subreddit | r/Windows11 (200k+) | r/solemos **non esiste** |
| Stack Overflow tag | migliaia di Q&A | **0** |
| Discord/Matrix community | grandi | **0** |
| Recensioni stampa | costanti | **0** |
| Case study aziende | enterprise | **0** |
| Stelle GitHub | n/a | < 10 stelle |
| Documentazione utente non-tech | curata | **solo doc tecnici** |
| Search engine results | dominante | **0 risultati Google** |

### Enterprise / business

| Feature | Windows enterprise | macOS business | SOLEM |
|---|---|---|---|
| Active Directory | nativo | ⚠️ | ❌ |
| Group Policy | nativo | ⚠️ Profile Manager | ❌ |
| MDM mobile | Intune | Apple Business Manager | ❌ |
| Single Sign-On corporate | Azure AD | ✅ | ⚠️ Keycloak self-host |
| VPN Cisco AnyConnect | nativo | nativo | ⚠️ OpenConnect workaround |
| Compliance certifications | FedRAMP, ISO | ISO 27001 | **zero** |
| Vendor support 24/7 | $$$ | $$$ | community Discord (zero ad oggi) |
| Long-term support (LTS) | 10 anni | 7 anni | NixOS 24.11 5 anni |

### Italia / EU specifico

| Feature | Realtà |
|---|---|
| SPID native app (PosteID/Aruba) | ❌ solo Android/iOS native |
| CIE 3.0 lettore desktop | ⚠️ workaround complesso |
| F24 Agenzia Entrate desktop | ❌ solo web |
| Fatturazione elettronica | solo web (no SDI desktop integration) |
| App banche italiane (Intesa, Unicredit, BPER, Mediolanum) | ❌ solo mobile native |
| Documento Sanitario Elettronico | ❌ solo regionale web |
| TS-CNS smart card | ⚠️ workaround |
| App INPS / INAIL | ❌ solo mobile |

---

## 📊 Score onesto (no marketing)

| Categoria | Windows | macOS/iOS | SOLEM **REALE** |
|---|:---:|:---:|:---:|
| App ecosystem | 10 | 10 | **3** (no Adobe/Office native/iMessage/streaming 4K) |
| Hardware OOTB | 9 | 10 | **5** (driver delay, fingerprint, NFC, GPU recente) |
| UX polished | 9 | 10 | **4** (TUI wizards, no help center, HiDPI imperfetto) |
| Performance reale (testata) | 8 | 9 | **? non misurata** |
| AI native funzionante | 8 | 9 | **2** (GAVIO STUB, no wake-word) |
| Cloud sync seamless | 9 | 10 | **4** (richiede setup manuale) |
| Mobile ecosistema | n/a | 10 | **2** (PinePhone limitato, no app store mobile reale) |
| Brand / community | 10 | 10 | **0** (zero utenti, zero presenza) |
| Enterprise readiness | 9 | 7 | **1** (no AD, no MDM, no compliance) |
| Italia / PA italiana | 8 | 8 | **2** (no app banche/IO/SPID native) |
| **MEDIA** | **8.8** | **9.3** | **2.7** |

**Realtà brutale**: SOLEM oggi è **a 2.7/10** vs colossi a 8.8-9.3, NON 8.8/10 come avevo scritto.

Dove vince ancora:
| Categoria | Score |
|---|:---:|
| Privacy zero telemetria | **10/10** |
| FOSS-purity 100% | **10/10** |
| Costo licenze | **10/10** (0 €) |
| Customization Nix dichiarativo | **10/10** |
| Reproducible builds | **10/10** |
| Auditability codice | **10/10** |

Ma **vincere su valori ≠ essere usabile da utente normale.**

---

## 🎯 Roadmap REALISTICA per arrivare a 5/10

| Mese | Goal | Effort |
|---|---|---|
| Mese 1 | CI verde end-to-end + ISO bootable + boot test su Beelink | **1 mese** sviluppatore esperto Nix |
| Mese 2 | 10 utenti beta tester volontari + telemetria minima opt-in per bug | **1 mese** community building |
| Mese 3 | GAVIO reale impacchettato + AI funzionante (no più stub) | **1-3 mesi** AI eng |
| Mese 4-6 | Hardware OOTB testing su 20 laptop diversi (donati o volontari) | **3 mesi** testing |
| Mese 6-9 | Cloud sync seamless GUI (nautilus extension) | **3 mesi** dev |
| Mese 9-12 | Setup wizard GTK4 + tutorial video + sito web | **3 mesi** UX dev |
| Anno 2 | Subreddit, Matrix, YouTube channel, conference presence | **continuous** |
| Anno 3+ | Vendor partnership hardware (System76/Framework/Tuxedo) | **multi-anno** |

**Solo a fine anno 2-3 SOLEM raggiunge ~ 5/10** che è il livello "usable da utente non-tech motivato".

Per arrivare a **7/10** servono **5+ anni** di lavoro continuo + community + vendor partnerships.

Per **10/10**: impossibile, alcuni gap (iMessage, Widevine, anti-cheat) sono per principio non chiudibili.

---

## 🤔 Cosa SOLEM **può davvero essere** oggi

**Non**: sostituto Windows/macOS per utente generico.

**Sì**:
- Workstation dev personale (Nix dichiarativo, reproducible)
- Server home self-host (Nextcloud, Immich, Vaultwarden)
- VM educational per imparare NixOS + AI native
- Base per spin-off (Beelink AI box, smart-home hub)
- Showcase principi FOSS + privacy

**Pubblico realistico**:
- Sviluppatori Nix-curious (~ 50k al mondo)
- Privacy-advocate hardcore (~ 100k)
- Self-hosters ((Fediverse community ~ 500k)
- FOSS-believer ideologici

**Pubblico NON realistico oggi**:
- Mamme di 50 anni
- Designer Adobe
- Gamer AAA
- Enterprise IT (no AD/MDM)
- Utenti italiani che usano app banca

---

## Take-away

1. **Lo score 8.8 era falso. Realtà ~ 2.7.**
2. **21 moduli scritti ≠ 21 capability funzionanti.**
3. **Zero utenti reali oggi.**
4. **Distanza enorme da product Windows/macOS.**
5. **Vincere su valori (privacy/FOSS/costo) non basta a "competere" in mainstream.**

Per "competere davvero" servono:
- 2-3 anni di sviluppo continuo
- Community attiva (Discord, Matrix, Reddit, YouTube)
- Hardware partner (laptop preinstall SOLEM)
- AI funzionante (GAVIO reale, no stub)
- Marketing budget non-zero

Senza, SOLEM resta **progetto di nicchia per smanettoni** — utile per loro, irrilevante per mass market.
