# SOLEM — Installa qualsiasi app

> Risposta concreta al WEAKNESSES.md sezione 🔴 GRAVI #3 "App ecosystem reale".
> Tutti i layer sono FOSS, gli utenti scelgono cosa installare.

## TL;DR — un comando, qualsiasi app

```bash
solem-install flatpak <id>           # Linux moderna (Flathub)
solem-install appimage <file>        # Linux portable
solem-install windows <installer.exe>  # App Windows via Wine
solem-install bottles                # GUI Wine prefix manager
solem-install android <file.apk>     # App Android (richiede Waydroid)
solem-install distro ubuntu          # Container Ubuntu (apt, ecc.)
solem-install distro fedora          # Container Fedora (dnf, ecc.)
solem-install distro arch            # Container Arch (pacman, AUR)
solem-install list                   # vedi tutto l'installato
```

Abilita una sola volta:
```nix
solem.appCompat.enable = true;
```

---

## Matrix: cosa runna su SOLEM

| Origine app | Runtime SOLEM | Esempi | Limiti |
|---|---|---|---|
| Linux moderna | Flatpak (Flathub) | Firefox, VS Code, OBS, Blender, GIMP, Krita, Inkscape, Discord… | Nessuno, prima scelta |
| Linux portable | AppImage | Cura, FreeCAD, Joplin, KeePassXC | Nessuno, no install |
| Linux ogni distro | Distrobox | App da Ubuntu / Fedora / Arch / Debian | Container, leggero |
| Windows desktop | Wine + Bottles | Notepad++, 7-Zip, VLC, IrfanView, foobar2000, Office 2010-2016 | Office 365 / Adobe = limitato |
| Windows giochi | Wine + DXVK + Proton-GE | Steam giochi (con Steam opt-in), Lutris catalog | Anti-cheat AAA bloccato |
| Android FOSS | Waydroid | F-Droid app, alcune Google Play apk-free | No Google Services, no Netflix |
| macOS app | **NON disponibile FOSS** | — | Darling è experimental, esclusa per FOSS purity |
| iOS app | **NON disponibile** | — | Impossibile su qualsiasi non-Apple OS |

---

## Confronto con altri OS

| Capability | SOLEM | macOS | Windows | Ubuntu | ChromeOS |
|---|---|---|---|---|---|
| Native Linux | ✅ via Flatpak/AppImage | ❌ | WSL2 | ✅ apt | ✅ Crostini |
| App Windows (Wine) | ✅ default | ⚠️ CrossOver $ | ✅ nativo | ✅ Wine | ❌ |
| App Android | ✅ Waydroid (opt-in) | ❌ | ⚠️ WSA deprecato | ⚠️ Anbox | ✅ nativo |
| Multi-distro Linux | ✅ Distrobox | ❌ | ❌ | ⚠️ Snap | ❌ |
| App macOS | ❌ | ✅ | ❌ | ❌ | ❌ |

SOLEM vince per **flessibilità** (4 mondi out-of-box), perde per **app macOS** (impossibile FOSS-only).

---

## Quick start per ogni caso d'uso

### Caso 1 — "Voglio installare Firefox / VS Code / Discord"

```bash
solem-install flatpak org.mozilla.firefox
solem-install flatpak com.visualstudio.code
solem-install flatpak com.discordapp.Discord
```

Tutte le app moderne sono su Flathub: https://flathub.org

### Caso 2 — "Devo aprire un .exe Windows"

```bash
solem-install windows installer.exe
# Tutto va in ~/.wine-solem/

# Per Office 2016, Adobe Reader, ecc. usa Bottles (GUI):
solem-install bottles
# Crea "bottle" isolato → installa → run
```

### Caso 3 — "Mi serve un comando che esiste solo in Ubuntu"

```bash
solem-install distro ubuntu
distrobox enter solem-ubuntu
# Dentro hai bash Ubuntu 22.04 con apt funzionante
sudo apt install <pacchetto-che-non-c'è-su-nixos>
```

### Caso 4 — "App Android con apk diretto"

```nix
# Abilita una volta:
solem.appCompat.waydroid = true;
# Reboot
```
```bash
solem-install android my-app.apk
waydroid show-full-ui
```

### Caso 5 — "App AppImage scaricata dal sito ufficiale"

```bash
chmod +x SuperApp.AppImage
solem-install appimage SuperApp.AppImage
# Oppure direttamente: ./SuperApp.AppImage
```

---

## Configurazione completa

Aggiungi in `/etc/nixos/configuration.nix`:

```nix
{
  imports = [ ./modules/solem-app-compat.nix ];

  solem.appCompat = {
    enable    = true;
    flatpak   = true;    # Flathub repo + portals
    appimage  = true;    # libfuse + appimage-run
    distrobox = true;    # podman + distrobox
    wine      = true;    # wine + winetricks + bottles + dxvk + mono
    waydroid  = false;   # opt-in (~ 2 GB)
  };
}
```

Poi `sudo nixos-rebuild switch`.

---

## Limiti dichiarati

### Funziona benissimo
- **App Linux** native moderne (Firefox, Chromium, OBS, Blender, GIMP, ecc.)
- **Office 2010-2016** via Wine (con `winetricks office2016`)
- **App Windows freeware** old-school (Notepad++, 7-Zip, IrfanView, foobar2000, MPC-HC)
- **Tool dev cross-platform** (VS Code, IntelliJ, Sublime Text, Postman → ma usa Flatpak)
- **Giochi Steam** old (Half-Life, Portal, indie games via Proton)
- **App Android FOSS** (F-Droid catalog)
- **CLI tool da ogni distro** via Distrobox

### Funziona ma con limiti
- **Office 365** moderno: solo web/PWA (la versione desktop richiede C2R installer, non sempre va su Wine)
- **Adobe Photoshop CS6**: funziona via Wine; versioni CC più recenti no
- **AutoCAD 2013-2018**: parziale su Wine
- **Discord / Zoom / Teams**: meglio via Flatpak (Wine fa problemi audio)
- **Anti-cheat games** (Fortnite, Valorant, CoD): bloccati al runtime kernel-level

### NON funziona (e niente lo farà su SOLEM)
- **iMessage / FaceTime** (Apple-only, server-side)
- **App iOS** native (impossibile su non-Apple)
- **App macOS** native (Darling alpha, non-FOSS dependency)
- **Netflix 4K HDR** (Widevine L1 closed)
- **App con Hardware Security Module specifico** (CIE 3.0 Italia richiede driver vendor)

---

## Storage / pulizia

```bash
# Spazio occupato
solem-install list

# Pulizia Flatpak (rimuovi app)
flatpak uninstall <id>
flatpak uninstall --unused

# Pulizia Wine prefix
rm -rf ~/.wine-solem    # ATTENZIONE: cancella tutte le app Windows

# Pulizia distrobox
distrobox rm solem-ubuntu
podman image prune
```

---

## Sicurezza

- **Flatpak**: sandboxed per default (filesystem limitato, no rete senza permessi). Vedi `solem.permissionsPanel` per gestire i permessi runtime.
- **AppImage**: NO sandbox (full FS access). Usa solo da sorgenti fidate.
- **Wine**: NO sandbox. Le app Windows hanno accesso al `~/.wine-solem/`. Per isolarle, usa **Bottles** che gestisce prefix separati.
- **Distrobox**: container rootless ma con `~/` montato (utile per dev, attenzione per app non-trusted).
- **Waydroid**: container LXC, isolato dal sistema.

---

## Roadmap app-compat futura

- [ ] **Steam** opt-in (closed-source) tramite `programs.steam.enable = true` documentato
- [ ] **Proton-GE-custom** preinstallato per giochi
- [ ] **Heroic Games Launcher** (Epic/GOG/Amazon Prime FOSS launcher)
- [ ] **MoonRay** (alt-iCloud Photos via Immich) configurazione 1-click
- [ ] **Wine prefix templates** per Office/Photoshop/AutoCAD pre-configurati
- [ ] **Universal install** rilevamento automatico (passa `.exe` / `.AppImage` / `.flatpakref` → sceglie da solo)
