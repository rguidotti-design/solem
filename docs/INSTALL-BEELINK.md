# Installazione SOLEM su Beelink (o qualsiasi mini-PC x86_64)

Guida step-by-step per installare SOLEM sul tuo Beelink (o equivalente:
Intel NUC, Minisforum, GMKtec, qualsiasi x86_64 UEFI).

Tutto FOSS, 0 €. Tempo stimato: **45-90 min** (la prima volta).

---

## 0. Hardware verificato

| Hardware | RAM min | Disco min | Note |
|---|---:|---:|---|
| Beelink S12 / SER5 / SER7 | 8 GB | 256 GB SSD | Verified su SER5 6600H |
| Intel NUC 11+ | 8 GB | 256 GB | Verified su NUC11ATK |
| Minisforum UM560 / UM690 | 8 GB | 256 GB | Verified su UM560 |
| Qualsiasi x86_64 UEFI 2018+ | 4 GB | 64 GB | Funziona ma lento |

> **Wi-Fi**: chip Intel (AX200/AX210) e MediaTek (MT7921) supportati out-of-box (firmware FOSS redistribuibile).
> Chip Realtek RTL8852 richiede `hardware.enableAllFirmware = true` (non FOSS pure).

---

## 1. Prepara la chiavetta USB live

### Su Windows (più semplice)

1. Scarica l'ISO SOLEM ufficiale:
   ```
   https://github.com/rguidotti-design/solem/releases/latest
   → solem-24.11-x86_64.iso (~ 1.5 GB)
   ```
2. Scarica [Rufus](https://rufus.ie) (FOSS, 3 MB)
3. Inserisci una chiavetta USB ≥ 4 GB (verrà cancellata!)
4. Rufus: seleziona la chiavetta + ISO SOLEM → "Start" → "DD Image" mode
5. Aspetta ~ 5 minuti

### Su Linux/macOS

```bash
# Trova la chiavetta (es. /dev/sdX)
lsblk        # Linux
diskutil list # macOS

# Scrivi ISO
sudo dd if=solem-24.11-x86_64.iso of=/dev/sdX bs=4M status=progress conv=fdatasync
sync
```

### Costruisci l'ISO tu stesso (opzionale)

Se vuoi l'ultima HEAD:

```bash
git clone https://github.com/rguidotti-design/solem.git
cd solem
nix build .#iso     # ~ 30 min se Cachix attivo, altrimenti 2-4 ore
# ISO in result/iso/solem-24.11-x86_64.iso
sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress
```

---

## 2. Boot da USB sul Beelink

1. Spegni il Beelink completamente
2. Inserisci la chiavetta USB nella porta posteriore (USB 3.0 blu)
3. Accendi → premi ripetutamente **F7** (Beelink) o **F12** (NUC) per il boot menu
4. Seleziona la chiavetta USB UEFI

Vedrai il banner SOLEM:
```
╔════════════════════════════════════════════════════╗
║          SOLEM — AI-native OS · live ISO           ║
║                                                    ║
║  user: gavio · pass: gavio                         ║
╚════════════════════════════════════════════════════╝
```

Login:
- **user**: `gavio`
- **pass**: `gavio`

---

## 3. Verifica hardware (prima dell'install)

```bash
# Stato Wi-Fi
nmcli device wifi list

# CPU + RAM
lscpu | head -10
free -h

# Disk
lsblk

# GPU (Intel/AMD/NVIDIA)
lspci | grep -i vga

# Audio
pactl list short sinks
```

Se Wi-Fi appare, audio risponde e disco è visibile: **sei pronto**.

Se qualcosa manca:
- Wi-Fi mancante → kernel non ha firmware, vedi sotto "Troubleshooting firmware"
- Audio muto → `pactl list sources` per vedere i dispositivi disponibili
- GPU lenta → `nvidia-smi` (se NVIDIA) o `radeontop` (AMD); driver mainline FOSS in uso

---

## 4. Connetti a Internet

```bash
# Wi-Fi
nmcli device wifi connect "NomeRete" password "ciao123"

# Ethernet (auto via DHCP se cavo collegato)
ip addr show
ping -c 2 8.8.8.8

# Verifica DNS
resolvectl query github.com
```

---

## 5. Installa con Calamares (GUI)

```bash
sudo calamares
```

Si apre l'installer con branding navy/gold SOLEM:

1. **Welcome** → "Next"
2. **Location** → Europa/Rome (di default)
3. **Keyboard** → IT (di default)
4. **Partitions** →
   - "Erase disk" se vuoi SOLEM unico OS
   - "Manual" se hai dual-boot (esperti)
5. **Users** →
   - Nome: il tuo nome
   - Username: come preferisci (consiglio `ruben`)
   - Password: scegli forte
   - Hostname: `solem` (default)
6. **Summary** → revisione, "Install"

L'install dura **8-20 minuti** in base alla velocità del SSD.

Al termine: **"Reboot now"** + togli la chiavetta USB.

---

## 6. Primo boot dopo install

Al login GRUB scegli "SOLEM" (default).

Login col tuo utente. Apparirà automaticamente:

```bash
solem-welcome
```

Wizard interattivo (5 minuti):
1. **Locale** → it_IT (default)
2. **Identità** → conferma username/email
3. **Mesh** → genera chiave Ed25519 per pair multi-device
4. **GAVIO backend** → scegli ollama locale / groq cloud / vLLM
5. **Backup** → locale o nodo cloud-personal

---

## 7. Verifica che tutto funzioni

```bash
# Stato SOLEM
solem status

# Health check completo
solem-doctor

# Lista servizi attivi
systemctl list-units --type=service --state=active | head -20

# GAVIO risponde?
curl http://localhost:8000/health
# → {"status":"stub","message":"GAVIO not packaged"}  (default)
# → o {"status":"ok"}  se hai pacchettizzato GAVIO reale
```

---

## 8. Connetti GAVIO reale (opzionale)

Default: GAVIO è uno stub (risponde "non impacchettato"). Per usare GAVIO reale:

```bash
git clone https://github.com/rguidotti-design/gavio /opt/gavio
cd /opt/gavio
python -m venv venv
source venv/bin/activate
pip install -r solem_api/requirements.txt

# Test
uvicorn solem_api.app:app --host 127.0.0.1 --port 8000

# Auto-start (modifica gavio.service)
sudo systemctl edit gavio
# [Service]
# ExecStart=/opt/gavio/venv/bin/uvicorn solem_api.app:app --host 127.0.0.1 --port 8000
sudo systemctl restart gavio
```

---

## Troubleshooting

### Wi-Fi non disponibile

Il firmware Wi-Fi vendor è proprietario non-FOSS. SOLEM lo include solo come opt-in:

```bash
# In /etc/nixos/configuration.nix aggiungi:
hardware.enableAllFirmware = true;

# Poi:
sudo nixos-rebuild switch
```

### Audio muto

PipeWire potrebbe essere configurato male. Reset:

```bash
systemctl --user restart pipewire pipewire-pulse wireplumber
```

### GPU NVIDIA non riconosciuta

```bash
# Aggiungi in configuration.nix:
services.xserver.videoDrivers = [ "nvidia" ];
hardware.nvidia.modesetting.enable = true;

sudo nixos-rebuild switch
```

### Build update fallisce

```bash
solem update apply
# Se fallisce, log dice quale modulo:
journalctl -u nixos-rebuild

# Rollback se rotto:
solem update rollback
# Oppure dal GRUB scegli "configuration N-1"
```

### Voglio tornare indietro a Windows

Boot da chiavetta USB di Windows → installa Windows → cancella partizioni SOLEM nel partition manager.

---

## Manutenzione

```bash
# Aggiorna sistema (settimanale auto, manuale on-demand)
solem update apply

# Backup ora (le notti alle 03:00 è automatico)
solem backup

# Spazio disco
solem-clean summary
solem-clean gc-old   # rimuovi generation vecchie

# Performance
btop          # tutto-in-uno
solem-doctor  # health check 30+ punti
```

---

## Next steps

- [USER-GUIDE.md](USER-GUIDE.md) — guida utente "primo giorno"
- [COMPETITIVE-GAP.md](COMPETITIVE-GAP.md) — feature confronto con macOS/Win
- [OPERATIVE.md](OPERATIVE.md) — cosa manca all'OS per essere 100% operativo

Buon uso 🌱
