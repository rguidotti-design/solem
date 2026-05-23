# SOLEM — Gap Competitivo vs Colossi & Roadmap FOSS

> **Confronto brutale e onesto**: dove SOLEM perde oggi vs macOS / Windows / ChromeOS / Ubuntu /
> Steam Deck OS, e cosa fare per chiudere il gap restando **100 % FOSS / gratis**.

Aggiornato: 2026-05-23. Versione: 1.

---

## 0. Score comparativo (brutale)

| Categoria                          | macOS | Windows | ChromeOS | Ubuntu | **SOLEM oggi** | Target |
|------------------------------------|:-----:|:-------:|:--------:|:------:|:--------------:|:------:|
| Hardware OOTB (Wi-Fi/BT/sensori)   |  10   |   10    |    9     |   7    |     **6**      |   8    |
| Installer + Setup primo boot       |  10   |   9     |    10    |   7    |     **4**      |   9    |
| Onboarding zero-knowledge          |  10   |   8     |    10    |   5    |     **3**      |   9    |
| App store one-click                |  9    |   8     |    9     |   7    |     **6**      |   9    |
| Update UX + rollback               |  9    |   7     |    10    |   6    |     **8**      |   9    |
| Sync multi-device nativo           |  10   |   8     |    10    |   4    |     **5**      |   9    |
| Notification center / quick toggle |  10   |   9     |    9     |   6    |     **5**      |   8    |
| AI integrazione context-aware      |  9    |   8     |    7     |   3    |     **7**      |   9    |
| Energy mgmt laptop                 |  10   |   8     |    9     |   6    |     **5**      |   9    |
| Display HiDPI + multi-monitor       |  10   |   8     |    8     |   6    |     **5**      |   8    |
| Touchpad gesture multi-touch       |  10   |   7     |    8     |   5    |     **4**      |   8    |
| Boot speed (cold)                  |  9    |   7     |    10    |   7    |     **7**      |   9    |
| Suspend/resume reliability         |  10   |   8     |    9     |   6    |     **6**      |   9    |
| Family/parental control            |  9    |   8     |    9     |   3    |     **2**      |   7    |
| Cloud backup E2EE built-in         |  9    |   8     |    9     |   4    |     **6**      |   9    |
| Photo memories ML                  |  9    |   7     |    7     |   3    |     **5**      |   8    |
| Spotlight / global search          |  10   |   7     |    8     |   5    |     **3**      |   9    |
| Runtime permissions UI             |  10   |   8     |    9     |   5    |     **4**      |   8    |
| AirDrop / file-share mobile        |  10   |   6     |    8     |   3    |     **5**      |   9    |
| Privacy / FOSS-ness                |  3    |   2     |    4     |   8    |    **10**      |   10   |
| **Media (10 = top)**               | **9.05** | **7.55** | **8.40** | **5.40** | **5.30** | **8.65** |

**Conclusione**: SOLEM domina su privacy + AI native, perde 3-4 punti su UX / Hardware /
Onboarding. Roadmap sotto chiude i gap **senza un euro di spesa**.

---

## 1. Cose da fare — Priorità P0 (chiusura gap critico)

Ogni voce = un modulo Nix nuovo o capability concreta. Tutto FOSS.

### P0 — UX / Onboarding (le perdiamo qui)

- [ ] **`solem-onboarding-wizard`** — primo-boot TUI con `gum` + GTK4: tour 5 step (locale → utenti → mesh pair → GAVIO chiave → backup)
- [ ] **`solem-spotlight`** — global search Spotlight-style su `albert` o `kupfer` o `anyrun`: file + app + comandi + GAVIO query + impostazioni; tasto `Super+Space`
- [ ] **`solem-quick-settings`** — pannello rapido waybar (eww popover): Wi-Fi / VPN / BT / volume / brightness / focus / GAVIO toggle
- [ ] **`solem-permissions-panel`** — UI GTK4 per gestire xdg-portal permission: camera/mic/location/screenshare per ogni Flatpak/app
- [ ] **`solem-notification-center`** — mako + history viewer (`dunst-history` style)
- [ ] **`solem-airdrop`** — `localsend` + `nautilus-share` + KDE Connect: file → smartphone in 1 tap, niente cloud
- [ ] **`solem-keychain`** — `gnome-keyring` o `pass` + Bitwarden self-host integration → SSO E2EE per app
- [ ] **`solem-multi-monitor`** — `kanshi` profile manager: laptop chiuso → automatico monitor esterno
- [ ] **`solem-touchpad-pro`** — `fusuma` + libinput-gestures: 3-finger swipe = workspace switch, 4-finger = launcher
- [ ] **`solem-battery-pro`** — `tlp` + `cpupower` + charge limit 80 % BAT0 + prediction TUI/GUI

### P0 — Hardware OOTB (Linux pain points)

- [ ] **`solem-fingerprint`** — `fprintd` + `pam_fprintd` auto: login + sudo + GUI enrollment
- [ ] **`solem-wifi-modern`** — `iwd` (backend Intel moderno) + WPA3 / 6E / 7
- [ ] **`solem-webcam-fix`** — fallback `v4l2loopback` + GUI per scegliere webcam preferita
- [ ] **`solem-audio-pro`** — PipeWire low-latency + EasyEffects preset + noise-suppression RNN (`rnnoise-plugin`)
- [ ] **`solem-printer-zero-config`** — CUPS + Avahi + `cups-filters` + driverless IPP auto-discovery
- [ ] **`solem-gpu-power`** — NVIDIA optimus offload + AMD `corectrl` + Intel `gpu-tools`
- [ ] **`solem-thermal-profile`** — `thermald` + `power-profiles-daemon` profili AC/BAT
- [ ] **`solem-suspend-fix`** — hooks pre/post-suspend per Wi-Fi/USB/audio (i bug ricorrenti Linux)
- [ ] **`solem-sensor-hub`** — accelerometer auto-rotate (`iio-sensor-proxy`), ambient light → brightness
- [ ] **`solem-keyboard-rgb`** — `openrgb` + `polychromatic` per gaming keyboard FOSS

### P0 — Cloud personale FOSS (rimpiazza iCloud)

- [ ] **`solem-cloud-personal`** — Nextcloud auto-setup primo-boot, end-to-end E2EE, cartelle foto/desktop/documenti sync automatico
- [ ] **`solem-photos-memories`** — Immich + ML auto-tag + "Memories" album mensile/annuale (clone Photos)
- [ ] **`solem-notes-sync`** — Joplin Server self-host + sync E2EE
- [ ] **`solem-calendar-sync`** — Radicale CalDAV + CardDAV sync con Thunderbird/DAVx5 mobile
- [ ] **`solem-keychain-sync`** — Vaultwarden (Bitwarden CE) sync E2EE multi-device
- [ ] **`solem-family-sharing`** — multi-utente Nextcloud + Vaultwarden org + shared folders foto
- [ ] **`solem-parental-control`** — DNS family-safe + screen-time per utente (logind + cron)

---

## 2. Priorità P1 (competitive feature parity)

### P1 — Sicurezza & Privacy avanzata

- [ ] **`solem-app-firewall-ui`** — Opensnitch GUI per gestire connessioni outbound app-per-app
- [ ] **`solem-screen-time-foss`** — telemetria local-only su uso app/sito; clone Screen Time Apple senza cloud
- [ ] **`solem-camera-mic-LED`** — LED hardware o overlay schermo che indica camera/mic in uso
- [ ] **`solem-privacy-vault`** — cartella veracrypt mounted on-demand con biometric unlock
- [ ] **`solem-shred-on-trash`** — Cestino con shred automatico (3-pass) per file SSD
- [ ] **`solem-network-isolation`** — VLAN guest Wi-Fi per smart home isolata da workstation

### P1 — Produttività AI native (vantaggio competitivo SOLEM)

- [ ] **`solem-gavio-context`** — context-aware: GAVIO riceve automaticamente app attiva + selezione testo (xdg-portal)
- [ ] **`solem-gavio-clipboard`** — clipboard "smart": GAVIO post-process (riassunto, traduzione, format)
- [ ] **`solem-gavio-screenshot`** — screenshot OCR + GAVIO query "spiega questa schermata"
- [ ] **`solem-gavio-meeting`** — auto-transcribe Jitsi/Meet (whisper.cpp) + GAVIO sommario meeting
- [ ] **`solem-gavio-action`** — comandi naturali → systemd unit / shell (es. "compila il progetto")
- [ ] **`solem-gavio-memory-ui`** — GUI per vedere/editare cosa ricorda GAVIO di te (trasparenza memoria)

### P1 — App ecosystem

- [ ] **`solem-app-discovery`** — GAVIO suggerisce app FOSS in base a uso ("vuoi alternativa a Photoshop?" → Krita)
- [ ] **`solem-app-uninstall-clean`** — uninstall + GC residui config + cache (tipo CleanMyMac FOSS)
- [ ] **`solem-flatpak-curated`** — sub-catalogo FOSS curato (solo licenze approvate FSF/OSI)
- [ ] **`solem-appstream-extension`** — meta-tag "100% FOSS" sui pacchetti nel catalogo

### P1 — Performance & boot

- [ ] **`solem-boot-budget`** — `systemd-analyze` + alert se boot > 15 s
- [ ] **`solem-zram-tuned`** — preset memory pressure ottimizzato per <4 GB RAM
- [ ] **`solem-kernel-bore`** — opt-in BORE/EEVDF scheduler per gaming + low-latency
- [ ] **`solem-prelink-aggressive`** — `prelink` opt-in per startup app ridotto

### P1 — Display & multimedia

- [ ] **`solem-color-management`** — `displaycal` + ICC profiles per fotografi
- [ ] **`solem-night-light-smart`** — `gammastep` + override automatico in base a contenuto
- [ ] **`solem-screen-recorder`** — `obs-studio` preset + 1-click + auto-upload Owncast self-host

---

## 3. Priorità P2 (nice-to-have / future scale)

### P2 — Mobile & wearable

- [ ] **`solem-pinephone-launcher`** — phosh / sxmo / lomiri integrazione completa
- [ ] **`solem-android-bridge`** — `scrcpy` + KDE Connect + Heimdall flash + Android Studio FOSS
- [ ] **`solem-wearable-companion`** — Bangle.js / PineTime / Asteroid sync FOSS

### P2 — Sviluppatore avanzato

- [ ] **`solem-devbox-templates`** — `devbox` / `flox` template per stack (web, ML, embedded)
- [ ] **`solem-gpu-cluster`** — `slurm` + `pyxis` per ML cluster casa (es. 2× workstation)
- [ ] **`solem-mlops-foss`** — MLflow + DVC + Weights & Biases-alt (Aim) self-host

### P2 — Datacenter / HPC

- [ ] **`solem-k3s`** — Kubernetes embedded (single-node first, multi-node future)
- [ ] **`solem-ceph`** — storage cluster casa con 3 mini-PC
- [ ] **`solem-grafana-stack`** — Prometheus + Loki + Tempo + Grafana out-of-box

### P2 — Compatibilità

- [ ] **`solem-macos-vm`** — `osx-kvm` per testing (avvio macOS in VM, dichiarativo)
- [ ] **`solem-windows-vm`** — VirGL + Looking Glass per Windows 11 VM full-speed
- [ ] **`solem-distrobox-templates`** — Arch/Ubuntu/Fedora con un comando

---

## 4. Quick wins immediati (P0 fast)

Implemento subito (questo batch):

1. ✅ **`solem-spotlight`** — global search Super+Space (in arrivo)
2. ✅ **`solem-quick-settings`** — eww quick toggle waybar (in arrivo)
3. ✅ **`solem-airdrop`** — localsend + warpinator (in arrivo)
4. ✅ **`solem-battery-pro`** — TLP + charge limit + GUI (in arrivo)
5. ✅ **`solem-multi-monitor`** — kanshi profile (in arrivo)
6. ✅ **`solem-touchpad-pro`** — fusuma gestures (in arrivo)
7. ✅ **`solem-fingerprint`** — fprintd auto (in arrivo)
8. ✅ **`solem-cloud-personal`** — Nextcloud auto-setup (in arrivo)

---

## 5. Cosa NON faremo (per principio)

- ❌ Apple ID-alt centralizzato → preferenza federation/P2P (matrix, syncthing, mesh)
- ❌ Telemetria opt-out (è opt-in se mai sarà introdotta)
- ❌ App store con paywall, anche FOSS — solo donazioni esplicite
- ❌ "GAVIO Premium" o tier paganti — un solo livello, gratis sempre
- ❌ DRM / Widevine di default — l'utente lo abilita se vuole Netflix in browser

---

## 6. Misuriamo

Ogni "P0 done" alza il **media score** della tabella. Target 8.65 = SOLEM > ChromeOS, vicino macOS.
Aggiorneremo la tabella mensilmente con `solem score` (CLI che gira benchmark + survey UX).

---

## Riferimenti

- [Cookies su come scrivere moduli SOLEM](./ARCHITECTURE.md#modules)
- [Lista app FOSS curate](../nixos/modules/solem-appstore.nix)
- [Direttiva FOSS-only](../CLAUDE.md) (preferenza utente)
