# SOLEM vs altri OS — analisi competitiva

> Cosa rende SOLEM diverso e dove deve ancora rincorrere.

---

## TL;DR

SOLEM **non compete** con macOS/Windows sull'ecosistema app. Compete come
**OS-per-l'AI-personale**, segmento dove **non esistono concorrenti diretti**.

Vincere significa essere la scelta ovvia per: makers, founder, ricercatori,
professionisti con AI personale, chiunque voglia uscire dal recinto big tech
senza rinunciare alle capabilities moderne.

---

## Matrice comparativa

| Capability | macOS | Windows 11 | Ubuntu | ChromeOS | NixOS | **SOLEM** |
|------------|:-----:|:----------:|:------:|:--------:|:-----:|:---------:|
| AI native (no add-on) | ❌ | 🟡 Copilot | ❌ | 🟡 | ❌ | ✅ |
| AI con system-wide access | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| Multi-device mesh built-in | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| Dichiarativo + rollback atomico | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ |
| Zero-Trust built-in | ❌ | 🟡 | ❌ | 🟡 | ❌ | ✅ |
| Data sovereignty | ❌ | ❌ | 🟡 | ❌ | ✅ | ✅ |
| E2E messaging built-in | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| Memoria assoluta utente | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| Extensions marketplace | ✅ | ✅ | 🟡 | ✅ | ❌ | 🟡 Step 4 |
| Ecosystem app desktop | ✅ | ✅ | 🟡 | 🟡 | 🟡 | ❌ Step 5+ |
| Hardware enablement | ✅ | ✅ | 🟡 | ✅ | 🟡 | 🟡 |
| Office suite native | ✅ | ✅ | 🟡 | 🟡 | 🟡 | ❌ |
| Gaming | 🟡 | ✅ | 🟡 | ❌ | 🟡 | ❌ |

Legenda: ✅ nativo · 🟡 parziale/add-on · ❌ assente

---

## Confronti puntuali

### vs **NixOS vanilla**
- SOLEM **è** NixOS, ma con: AI primaria, mesh, zero-trust, memoria, capabilities
- Per chi vuole nudo NixOS: usa NixOS. Per chi vuole l'AI personale + multi-device: SOLEM
- Nessun lock-in: la base resta NixOS standard

### vs **Tailscale / Headscale**
- Tailscale fa solo mesh. SOLEM include mesh come una feature tra molte
- Headscale self-host: SOLEM mesh è già self-host nativo
- Vince Tailscale su: facilità setup multi-piattaforma (oggi). SOLEM colmerà in Step 2

### vs **GrapheneOS** (privacy-first Android)
- GrapheneOS è la cosa più simile filosoficamente. Ma è solo mobile
- SOLEM è server + desktop futuri + mobile (Step 4+)
- Si possono integrare: GrapheneOS come device-client che parla con SOLEM via mesh

### vs **HomeAssistantOS / CasaOS / Umbrel**
- Quelli sono "home server OS" focus IoT/media
- SOLEM è "personal AI OS" — IoT è uno dei tanti integrations (L6)
- HA può essere integrato come capability sotto GAVIO (già pattern usato in GAVIO)

### vs **Fedora Silverblue / GNOME OS / Endless**
- OS immutable atomici come NixOS
- Manca AI integration nativa
- SOLEM eredita immutability di NixOS + aggiunge AI layer

### vs **macOS** (l'unico veramente comparabile su UX)
- macOS = ecosistema chiuso, UI premium, AI in Apple Intelligence (limitato a iCloud)
- SOLEM = ecosistema aperto, UI ancora primitiva, AI illimitata
- Step 5+ vendiamo hardware/distro = clone "Apple per founder"

---

## Roadmap per chiudere i gap

### Gap 1: **Desktop UI** (priority Step 2-3)
- Wayland + Hyprland (compositor minimal) o KDE Plasma 6
- Shell custom "SOLEM Shell": ogni elemento UI è una capability invocabile dall'AI
- Niente desktop tradizionale — paradigma "conversazione + denso info layout"

### Gap 2: **Hardware enablement** (priority Step 1)
- Mobile: Pi/Beelink ARM future
- Display: HDR + multi-monitor
- Suono: Pipewire (già standard NixOS)
- Bluetooth: BlueZ
- Stampa: CUPS
- WiFi roaming: NetworkManager (già attivo)

### Gap 3: **App ecosystem** (priority Step 4+)
- Flatpak runtime per app GUI standard (LibreOffice, Firefox, ecc.)
- Nix overlay per pacchetti AI-aware (extension marketplace)
- WebApps PWA come citizens di prima classe (GAVIO frontend lo è già)

### Gap 4: **Onboarding nuovi utenti** (priority Step 4)
- Live ISO con wizard: scegli hardware → genera config NixOS → installa
- Self-host first: installer su PC tuo, Pi, Beelink — niente cloud paganti
- Mobile companion PWA per joinare mesh in 30 secondi (installazione diretta browser)

### Gap 5: **Updates OTA** (priority Step 2)
- NixOS auto-rebuild da Git remote (canonical flake URL → `nixos-rebuild switch --refresh`)
- Channel "stable" / "beta" / "edge"
- Rollback automatico se boot fallisce 3 volte (`systemd-boot` + NixOS generations)

### Gap 6: **Recovery & resilienza** (priority Step 2)
- Boot recovery menu (generations NixOS già lo dà)
- Auto-recovery: timer health-check, restart automatico servizi giù
- Offline degradation graceful (già nella spec)

### Gap 7: **Performance percepita** (priority Step 1-2)
- GAVIO < 3s su comandi diretti (target spec)
- SOLEM API < 100ms su /manifest e /capabilities
- Streaming SSE su output AI lunghi (spec dice nativo)

---

## Posizionamento

### Target utenti (sempre self-host, sempre gratis)

- Founders / makers / hacker che vogliono AI personale ma odiano lock-in
- Sviluppatori privacy-conscious
- Researcher con dati sensibili
- Chiunque voglia indipendenza tech, non clienti che pagano

### Modello: 100% gratis, sempre self-host

SOLEM non è un prodotto. È un OS open source.

- **Distribuzione**: gratuita, sempre, per tutti
- **Hardware**: l'utente compra da fornitori suoi (Beelink/Pi/PC standard)
- **Hosting**: sul tuo hardware, nessuna nostra infrastruttura
- **Estensioni**: gratuite, comunità libera
- **Nessun managed**, **nessun cloud paid**, **nessun bundle commerciale**

### Asset difensivi (non-monetari)

- Memoria assoluta utente: switching cost reale (la tua AI ti conosce)
- Mesh self-host: ogni device aggiunto rinforza la rete personale
- Dichiarativo: l'utente può portarsi via tutto in 1 file (anti-lock-in by design)
- Community open-source

---

## Cose che NON vogliamo fare

- **Competere su gaming/creativi**: macOS/Windows vincono, non rincorriamo
- **Fare un altro distro general-purpose**: NixOS lo fa già
- **App store con revenue share**: estensioni libere, mai monetizzate
- **Tracking utente**: vietato per principio (vedi [AI_FREEDOM.md](AI_FREEDOM.md))
- **Cloud lock-in**: ogni feature deve avere modalità self-host
- **Managed services paganti**: nessun abbonamento, mai
- **Vendita hardware**: l'utente compra dove vuole

---

## Misure di successo

- **Step 3 (2027)**: 3-5 utenti beta self-host attivi 30+ giorni
- **Step 4 (2028)**: utenti reali che self-hostano SOLEM 30+ giorni — no metriche di revenue
- **Step 5 (2029+)**: comunità di self-hoster sostenibile
