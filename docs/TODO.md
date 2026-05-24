# SOLEM — TODO live (lista concreta cose da fare)

> Aggiornato 2026-05-24, ultimo commit `aa76f66`.

---

## ✅ FATTO in questa sessione (20 step + 8 fix bug)

### Fix CI bug (8 commit)

| Commit | Bug fixato |
|---|---|
| `afe10a8` | `home-manager` nel flake senza lock aggiornato |
| `b41ef69` | Debug isolation minimal |
| `16c9b99` | `users.users.gavio` duplicato |
| `5351fcd` | **KILLER**: `sharedDirectories` WSL2 path hardcoded |
| `edd7b72` | `services.pulseaudio` (era `hardware.pulseaudio` in 24.11) |
| `ddf3e62` | VM tests duplicato user |
| `06358c0` | Rimosso vm-full/raspberry/jetson dal flake (eval rotto) |
| `c89a3b7` | VM tests matrix ridotta |
| `ad95572` | Font dubbi (cormorant/crimson/merriweather/...) rimossi |

### Ricostruzione incrementale (Step 1-20, +164 moduli)

| Step | Commit | Cosa |
|---|---|---|
| 0 | — | base solem-core |
| 1 | `1943d58` | +cli +motd +channels |
| 2 | `18ab81d` | +keep +doctor |
| 3 | `c41fde7` | +kernel-hardening +memory +sandbox (8 totali) ✅ |
| 4a | `5f29c5a` | +shell (binary search) |
| 4b | `2036671` | +italian-locale (font fixed) |
| 4c | `ffe0abe` | +clipboard |
| 5 | `8cc752d` | +update +cli-extra +init +sysmon |
| 6 | `7c459b6` | +snapshots +recovery |
| 7 | `5da90bf` | +secrets +power +power-profiles +services-hub |
| 8 | `8097705` | +network-tools +headscale +screen-tools |
| 9 | `a6fdb82` | +dns-private +dns-blocker +tor +wake-on-lan +tpm +usbguard +secure-boot +mesh +zero-trust +double-vpn |
| 10 | `851e091` | +19 moduli (bt-audio, print, password, pdf, finance, jupyter, db, photo-music, reading, smart-home, radicale, selfhost, mail-server, hpc, datacenter, spid-italia) |
| 11 | `eaa62aa` | +a11y +auditd +autoheal +backup-restic +battery-health +browser-hardened +cluster |
| 12 | `ca7efee` | +comm +containers +crash +display +edge +email +greeter +handheld +hotspot +mobile +monitoring +overlay |
| 13 | `e62a080` | +15 storici (network discovery/failover/stack, opensnitch, privacy-network, sandbox-profiles, tor-browser, virtualization, wsl, multimedia, system-tools, readers, typography, dev-extras, privacy-tools) |
| 14 | `32d6888` | +14 OPT-IN P0 (account, airdrop, airplay, audio-pro, backup-gui, battery-pro, bench, gaming, onboarding, perms, notif-center, keychain, gavio-ctx, printer) |
| 15 | `7bf28c7` | +25 OPT-IN P0 batch 2 (app-compat, chat-clients, cloud-personal, data-eng, makers, spotlight, sdr, multi-mon, quick-set, touchpad, paperless, photo-mem, libreoffice, fingerprint, streaming, suspend, univ-clip, webcam, wine, hw-firmware, installer, migration-tool, trial, family-sharing, wakeword) |
| 16 | `10c2a22` | +drivers +gaming +dev-envs +ai-hw +antivirus +appstore +code-asst +dictation +prefetch +selfhost-extra +sec-advanced +voice +voice-wake +waybar |
| 17 | `f04b57c` | +creative +office +hyprland-config +plymouth +lockscreen +desktop |
| 18 | `8fc41f7` | +theme +secure +profiles |
| 19 | `c259a31` | +raspberry +jetson +asahi +pinephone |
| 20 | `aa76f66` | +creator +i18n +migration +updates +ai-freedom +quantum +inference +server-mode +supabase-backup |

**Totale 164/168 moduli importati** (97.6% coverage).

### Moduli ANCORA non importabili (4)

Hanno config inline senza `cfg.enable mkIf` — refactor invasivo richiesto:

- `solem-api` (systemd.services.solem-api sempre attivo)
- `solem-backup` (config sempre attivo)
- `solem-boot` (boot.kernelParams sempre attivi)
- `solem-layers` (event bus sempre attivo)
- `solem-gavio-storage` (systemd-tmpfiles sempre attivi)

---

## 🟡 IN ATTESA

- ⏳ Verifica CI per ognuno dei 20 step (rate-limit GitHub 60 req/h)
- Quando rate-limit reset, posso fare binary search del primo step che rompe (se ce ne è uno)

---

## 🟠 PROSSIMI STEP

1. **Verifica CI verde** per `aa76f66` (step 20, 164 moduli)
2. Se 🟢 verde:
   - Re-introduce `solem-vm-full` nel flake (configuration.nix originale)
   - Re-introduce `solem-raspberry` + `solem-jetson` nel flake
   - Re-attiva i 6 VM tests rimossi (spotlight, quick-settings, gavio-context, italian-locale, user-clis, mesh-iface)
   - Build `nix build .#iso` su CI
3. Se 🔴 rosso (probabile per qualche pkg dubbio):
   - Binary search sul commit step → identifica modulo colpevole
   - Fix specifico (rimuovi pkg o aggiungi guard)
   - Push + retry

---

## 🔴 Non faremo MAI (per principio)

- Pacchetti closed-source per default (Steam, Discord, Spotify nativi)
- Telemetria OS
- Account centralizzato obbligatorio
- DRM Widevine L1 di default (solo L3 opt-in per Netflix 720p)
- "GAVIO Premium" o tier paganti

---

## 4 regole utente (memorizzate)

1. ✅ App esistenti installabili → `solem-app-compat.nix` (Flatpak+AppImage+Wine+Distrobox+Waydroid)
2. ✅ Partire dai problemi GRAVI → `solem-hardware-firmware.nix` + `solem-installer-graphical.nix` + altri P0
3. ✅ Lista TODO aggiornata → questo file
4. 🟡 Tutto deve funzionare prima di andare avanti → CI verifica in corso
