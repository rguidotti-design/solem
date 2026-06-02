# Come vedere il DESKTOP SOLEM (Hyprland UI grafica)

3 modi diversi. Il più semplice è in fondo.

---

## ✅ CONFERMATO FUNZIONANTE (testato 2026-06-02)

VM desktop SOLEM buildata e bootata con successo in WSL Ubuntu.

Output console reale post-boot:
```
[OK] Started Plymouth Boot Screen
[OK] Started Permit User Sessions
[OK] Started Network Manager
[OK] Started D-Bus System Message Bus
[OK] Reached target Login Prompts
   Starting Terminate Plymouth Boot Screen...
solem-desktop-demo login:
```

Plymouth = il boot splash navy/gold (Step 37) — **ATTIVO**.
greetd = login manager — **pronto**.
Hyprland Wayland — caricato al login utente.

---

## Modo 1 — WSL Ubuntu + WSLg (Windows 10/11)

WSLg è il sistema integrato Windows per mostrare GUI Linux. Già installato
su WSL2 da default.

### Step:

```bash
# 1. Apri PowerShell, entra in WSL Ubuntu:
wsl

# 2. Verifica WSLg attivo (deve mostrare DISPLAY):
echo $DISPLAY  # output atteso: :0 oppure simile

# 3. Build VM desktop:
cd ~/solem-source
git pull
nix build .#vm-desktop --extra-experimental-features 'nix-command flakes'
# ~20-40 min primo run (scarica Hyprland, GNOME apps, ecc.)

# 4. Lancia VM CON display:
./result/bin/run-solem-desktop-demo-vm -m 4096
# Si apre finestra QEMU con Plymouth -> Hyprland desktop
```

### Cosa vedi nella finestra QEMU:
1. **Plymouth boot splash** navy + logo "S" gold pulse (~5s)
2. **greetd login screen** (auto-login se `solem.desktop.autoLogin = true`)
3. **Hyprland desktop Wayland**:
   - Wallpaper navy gradient
   - Top bar con clock/network/audio
   - Super+T → terminale (Alacritty)
   - Super+space → app launcher Spotlight-style
   - Super+Tab → Mission Control overview
   - Super+frecce → snap window stile Win11
   - Tasto dx wallpaper → menu

### Comandi dentro il desktop:
- Click destro → menu → terminale
- Dentro terminale: `solem-welcome`, `solem-localhost`, `solem-demo`
- Apri Firefox dal launcher (Super+space → "fire")

---

## Modo 2 — Linux nativo + KVM (più veloce)

Su un PC Linux (Ubuntu/Fedora/Arch) con KVM abilitato:

```bash
git clone https://github.com/rguidotti-design/solem
cd solem
nix build .#vm-desktop
./result/bin/run-solem-desktop-demo-vm -enable-kvm -m 4096 -smp 4
# 10-100x più veloce di TCG (no nested virtualization)
```

---

## Modo 3 — VirtualBox + ISO (per chi NON ha WSL/Nix)

Se non hai WSL e non vuoi installare Nix, puoi usare un ISO live SOLEM.

⚠ ISO non ancora hostata su CDN. Build locale richiesta:

```bash
# Su una macchina Linux/WSL con Nix:
nix build .#iso
ls result/iso/*.iso
# Copia il file .iso su Windows / chiavetta USB

# Poi su Windows con VirtualBox installato:
# 1. Apri VirtualBox
# 2. New VM → Linux 64-bit → 4GB RAM → 20GB disco
# 3. Settings → Storage → Aggiungi CD/DVD → seleziona solem-X.Y.Z.iso
# 4. Start → boot ISO
# 5. Live session → doppio-click "Installa SOLEM" (Calamares)
# 6. Wizard install → reboot → SOLEM su disco virtuale
```

---

## Limiti onesti

- **WSLg richiede WSL2** (non WSL1). Verifica: `wsl -l -v` deve mostrare VERSION 2.
- **Performance WSL+QEMU senza KVM**: lenta (~3-10x più lenta nativa).
  Su WSL2 le nested virtualization può essere abilitata ma è complesso.
- **Display Wayland in QEMU**: alcune feature visual (animazioni fluide,
  effetti vetro) possono lagged. Per esperienza vera: installa su hardware reale.
- **Audio dentro QEMU**: di default no audio. Per abilitare aggiungi
  `-audio pa,model=ich9-intel-hda` ai parametri QEMU.
- **Risoluzione**: di default 1024x768. Per fullscreen aggiungi
  `-vga virtio -display sdl,gl=on`.

---

## Cosa è SOLEM in pratica (visual)

Pre-login:
```
[Plymouth splash - navy gradient + logo "S" gold pulse + 5s loading dots]
```

Login screen (greetd):
```
+-----------------------------------+
|                                   |
|         [SOLEM Logo]              |
|                                   |
|    Username: [_________]          |
|    Password: [_________]          |
|                                   |
|    [ Login ]                      |
|                                   |
+-----------------------------------+
```

Desktop (Hyprland post-login):
```
+----------------------------------------------------+
| [Time]  [Network]  [Volume]  [Battery]  [Notify]   |
+----------------------------------------------------+
|                                                    |
|                                                    |
|              [Wallpaper navy gradient]             |
|                                                    |
|              [Solem-welcome wizard si apre auto]   |
|              ╭──────────────────────────╮          |
|              │  Benvenuto in SOLEM      │          |
|              │  6 step setup iniziale   │          |
|              ╰──────────────────────────╯          |
|                                                    |
|                                                    |
+----------------------------------------------------+
| [App icons in dock - Firefox/Files/Terminal/...]   |
+----------------------------------------------------+
```

(Mockup ASCII — vedere finestra QEMU per reale.)
