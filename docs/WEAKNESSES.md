# SOLEM — Dove è scarso (brutalmente onesto)

> Aggiornato 2026-05-24. **Niente vendere fumo.**
> Lista di tutte le aree dove SOLEM oggi perde nettamente vs colossi.
> Serve a chi vuole capire dove investire prossimi sforzi (o decidere se
> SOLEM è adatto al proprio caso d'uso).

---

## 🔴 GRAVI — Bloccano l'adozione di utenti normali

### 1. Hardware out-of-box

| Cosa manca | Concorrente che lo ha |
|---|---|
| Driver fingerprint Goodix 5xxx/6xxx senza firmware proprietario | macOS/Windows |
| Wi-Fi BCM (Broadcom) chip vecchi su MacBook | macOS, Ubuntu (firmware non-FOSS) |
| Webcam Realtek HD (ThinkPad) richiede patch kernel | Windows, Fedora |
| Lettori NFC USB consumer | Windows |
| Stampanti USB low-cost (HP/Brother base) plug&play | macOS perfect |
| Touchscreen palm rejection laptop convertibili | Windows tablet mode |
| Suspend-then-hibernate (s2idle bug) | macOS impeccabile |

**Conseguenza**: se il tuo hardware ha 1 di questi, install fallisce o feature non parte. ChromeOS / macOS / Windows funzionano sempre.

### 2. Onboarding zero-knowledge

| Cosa manca | Concorrente |
|---|---|
| Installer 1-click (premi "Avanti" 3 volte e basta) | Windows, macOS, ChromeOS |
| Setup wizard con video tutorial integrati | macOS Migration Assistant |
| Trasferimento dati da PC vecchio (Windows/Mac) | Migration Assistant Mac, Windows 11 |
| Account auto-creato con SSO Google/Apple | tutti |
| Modalità demo "prova SOLEM senza installare" 5 minuti | macOS Sonoma demo store |

**Conseguenza**: non-techy non riesce a installare. Adesso serve `sudo calamares` da terminale. Demo path zero.

### 3. App ecosystem reale

| Cosa manca | Concorrente |
|---|---|
| Microsoft Office 365 funzionante | Windows nativo, web ok ovunque |
| Adobe Creative Cloud (Photoshop, Illustrator, Premiere) | Mac/Win nativo |
| AutoCAD, SolidWorks, Revit | Win nativo, Mac alcuni |
| App bancarie con OTP USB token specifico | Win nativo |
| TeamViewer/AnyDesk con consenso UAC | Win/Mac perfetto |
| Streaming Netflix/Disney+ 4K HDR | Win/Mac nativo (Widevine L1) |
| Giochi AAA recenti con anti-cheat | Windows |
| iMessage / FaceTime | macOS exclusive |
| Find My iPhone (cerca dispositivi Apple) | macOS |

**Conseguenza**: chi dipende da queste app non può migrare. Periodo.

---

## 🟠 SERI — Limitano produttività quotidiana

### 4. Performance percepita

| Cosa manca | Stato SOLEM | Stato macOS/Win |
|---|---|---|
| Boot < 10 secondi cold start | 🔴 Mai misurato | macOS 8s, Win 12s |
| Wake from sleep < 1s | 🔴 Mai testato | macOS perfetto |
| Apri Chrome < 2s primo avvio | ❓ | macOS 1s |
| Idle RAM < 800 MB | ❓ | macOS 1.5GB, Win 2GB |
| Battery life laptop 8+ ore | 🔴 TLP solo dichiarativo | macOS 18h, Win 8-12h |
| Audio latency < 10ms | PipeWire OK | macOS CoreAudio nativo |
| HiDPI 200%+ multi-monitor mixed-DPI | 🟠 Wayland fragile | macOS perfetto |

### 5. UX desktop avanzata

| Cosa manca | Concorrente |
|---|---|
| Mission Control / Task View animato | macOS Mission Control |
| Spotlight con accuracy ML | macOS Spotlight |
| Quick Look (preview spazio = anteprima) | macOS |
| Stage Manager / Snap Layouts 4-finestre | macOS Ventura, Win 11 |
| Spaces orizzontali con anteprima live | macOS |
| Continuity Camera (telefono = webcam OS) | macOS+iOS |
| Universal Control (mouse single tra Mac/iPad) | macOS+iPadOS |
| Sidecar (iPad come secondo monitor wireless) | macOS+iPadOS |
| Handoff app (apri Mail Mac → continua iPhone) | macOS+iOS |
| AirPlay (mirror schermo a TV/sound system) | macOS, parziale Linux |

### 6. AI native sempre attiva

| Cosa manca | Concorrente |
|---|---|
| Wake-word "Hey GAVIO" attivo sempre con LED privacy | Siri, Alexa |
| AI scrive bozza email mentre scrivi | Apple Intelligence iOS 18, Win Copilot |
| AI summarize notifica appena arriva | Apple Intelligence |
| AI Image Playground genera immagine in-app | Apple Intelligence |
| AI risponde con voce naturale realtime (no latency) | ChatGPT Voice mode |
| Copilot integrato in ogni text field | Windows Copilot |
| AI con context su Files/Foto/Mail tue locali | Apple Intelligence (semantic search foto) |

**Stato SOLEM**: GAVIO è uno stub (`gavio-server` placeholder). Anche quando pacchettizzato, l'integrazione context-aware è solo via tasti rapidi (Super+G), non automatica.

### 7. Sync cross-device seamless

| Cosa manca | Concorrente |
|---|---|
| AirDrop nativo Mac↔iPhone (zero setup) | macOS+iOS |
| iCloud Photos auto-upload da iPhone | macOS+iOS |
| Universal Clipboard (copia Mac, incolla iPhone) | macOS+iOS |
| Cross-device tab Safari sync | macOS+iOS |
| Find My (laptop perso → localizza da iPhone) | Apple ecosystem |
| Microsoft Account auto-sync impostazioni multi-device | Windows |
| Google Account sync Chrome | Chrome ovunque |

**Stato SOLEM**: ha LocalSend + Syncthing + Vaultwarden. Sono comparable ma richiedono setup manuale, niente "appendi telefono al PC e parte".

---

## 🟡 MEDI — Convenience features mancanti

### 8. Office / produttività ufficio

- **LibreOffice** è OK ma non al pari di MS Office 365 (compatibilità DOCX complessi, macro VBA, real-time collab)
- **Niente equivalente Notion locale** (Joplin/Logseq sono ottimi ma diverso UX)
- **Niente equivalente Trello/Asana embedded** (Vikunja c'è ma UX scarna)
- **Niente PowerPoint reale** (Impress c'è, ma animazioni avanzate compatibilità zero)
- **Niente Acrobat Pro features** (firma digitale CAdES, redazione, forms avanzati)
- **Niente OneDrive sync nativo** (Nextcloud sync OK ma serve setup)

### 9. Media / streaming consumer

- **Niente Spotify** (curated app store FOSS-only → Quod Libet, Strawberry, ma il catalogo del cloud è altro)
- **Niente Apple Music HiFi lossless** (Tidal-alt FOSS = niente)
- **Netflix limitato** a 720p (Widevine L3 only)
- **Disney+/Hulu/HBO Max stessa storia**
- **Niente Steam** (default rimosso per FOSS purity; opt-in disponibile)
- **Niente NVIDIA GeForce Now / Xbox Cloud** (browser ok ma latency alta)

### 10. Identità / pagamenti / smart card

- **Niente Apple Pay / Google Pay tap-to-pay** su NFC laptop
- **Niente CIE 3.0 Bridge ufficiale** (workaround con `cie-middleware` non-FOSS)
- **Niente SPID app Aruba/PosteID nativa** (web only)
- **Niente Smart Card Microsoft S/MIME enterprise** (workaround `pkcs15-tool` complesso)
- **Niente Apple Wallet / Google Wallet pass biglietti**

### 11. Comunicazione professional

- **Niente Slack Calls audio enterprise quality** (electron app sì, ma esperienza limitata)
- **Niente Microsoft Teams enterprise feature complete** (mtdocs alt FOSS)
- **Niente Zoom virtual background ML** (Jitsi sì ma background plain)
- **Niente FaceTime cross-platform** (macOS exclusive)
- **Niente WhatsApp Desktop ufficiale** (web app via electron sì)

### 12. Mobile (PinePhone / Android bridge)

- **PinePhone funziona ma**: fotocamera bassa qualità, GPS lento, no app banche
- **Android bridge KDE Connect**: pairing fragile, notifiche perdute, file transfer slow
- **Niente Apple ecosystem** sui non-Apple device (period)

---

## 🟢 LIEVI — Polish missing ma non bloccanti

### 13. Documentazione / community

- **Niente videocorsi YouTube** (zero presenza)
- **Niente subreddit attivo** (zero presenza r/solemos)
- **Niente Discord/Matrix community ufficiale** (zero membri)
- **Niente Stack Overflow tag attivo** ("solem-os" inesistente)
- **Niente influencer review** (Linus Tech Tips, MKBHD, ecc.)
- **Niente caso studio aziende che usano SOLEM** (zero)
- **Niente certificazione vendor** (es. RHEL training)

### 14. Brand / awareness

- **Logo non riconosciuto** in nessun contesto
- **Nessun font specifico custom** (uso Cormorant Garamond / Inter, già diffusi)
- **Nessun sito web pubblico** (solo GitHub)
- **Nessun newsletter / blog ufficiale**
- **Niente Wikipedia entry**

### 15. Performance benchmark pubblici

- **Niente Geekbench score pubblicato** (mai testato vs macOS/Win/Ubuntu)
- **Niente Phoronix Test Suite confronto** (FOSS, gratis, mai eseguito)
- **Niente power consumption W misurati** (TLP dichiarativo, mai validato)
- **Niente boot-time profiling** (`systemd-analyze blame`)

---

## ⚪ DIFFERIRE (Punto 7+) — Hardware reale

- Test su Beelink fisico
- Test su Raspberry Pi 4/5 con SD card flash
- Test su Jetson Nano
- Test su PinePhone
- Test su smart glass PWA
- Test consumi reali con power meter
- Test stress 7 giorni uptime
- Test rete: 50 device mesh + cluster

---

## Sintesi numerica

| Area | Score 1-10 vs colossi |
|---|:---:|
| Hardware OOTB | **4** |
| Installer / Onboarding | **3** |
| App ecosystem reale | **3** |
| Performance | **?** (non misurata) |
| UX desktop avanzata | **4** |
| AI native | **5** (GAVIO stub) |
| Sync cross-device | **5** |
| Office/produttività | **5** |
| Media/streaming | **4** |
| Identità/pagamenti | **3** |
| Comunicazione | **5** |
| Mobile | **3** |
| Documentazione/community | **2** |
| Brand awareness | **1** |
| Performance benchmark | **?** |

**Media: 3.5/10** in punti dove SOLEM è confrontato direttamente con macOS/Windows.
**Media: 8/10** in punti dove vince (privacy, FOSS-ness, costo, customization, no telemetry, no vendor lock-in).

---

## Cosa NON vogliamo migliorare (per principio)

- **Telemetria/analytics OS** (zero, per sempre)
- **Account centralizzato obbligatorio** (preferiamo P2P/federation)
- **DRM Widevine L1** (non-FOSS, l'utente abilita se vuole)
- **App store con pagamenti** (donazioni esplicite, non paywall)
- **AI cloud-only** (GAVIO sempre con fallback locale)
- **Bloatware preinstallato** (toolkit FOSS opt-in, nessun banner)

---

## Cosa fare per migliorare lo score

Vedi [OPERATIVE.md](OPERATIVE.md) per la roadmap concreta P0-P3 e [COMPETITIVE-GAP.md](COMPETITIVE-GAP.md) per i ~80 item con effort stimato.

Le 3 mosse a impatto maggiore (e zero costo):
1. **Far passare la CI verde** → almeno SOLEM è dimostratamente installabile (oggi è "probabilmente")
2. **Misurare performance reale** su una VM (Phoronix gratis, 1 ora) → numeri concreti vs Ubuntu
3. **Video di 2 minuti su YouTube** che mostra SOLEM bootare + GAVIO che risponde → unlock community
