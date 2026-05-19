# SOLEM — Guida test VM

Tre metodi per testare SOLEM senza intaccare il PC. Scegli quello che
preferisci in base agli strumenti che hai già installato.

---

## Metodo A — `nix run` da WSL (raccomandato)

Più rapido e pulito: NixOS compila la VM in modo dichiarativo, la lancia in
QEMU, e monta automaticamente la cartella GAVIO via 9p.

### Setup una tantum

1. Installa **WSL2** (PowerShell admin):
   ```powershell
   wsl --install
   ```
   Riavvia. Apri Ubuntu, crea utente.

2. Installa **Nix** dentro WSL Ubuntu:
   ```bash
   sh <(curl -L https://nixos.org/nix/install) --daemon
   ```
   Chiudi/riapri il terminale.

3. Abilita **flakes**:
   ```bash
   mkdir -p ~/.config/nix
   echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
   ```

### Lancio VM

Da PowerShell (Windows):
```powershell
cd C:\Users\guido\Desktop\solem
.\scripts\run-vm.ps1
```

Oppure direttamente da WSL:
```bash
cd /mnt/c/Users/guido/Desktop/solem
nix run .#vm
```

**Prima esecuzione:** scarica nixpkgs (~500 MB), 5-15 minuti.
**Successive:** boot in ~30 secondi.

### Dopo il boot

```bash
# Login console: gavio / gavio
# Cambia password subito
passwd

# Crea env file con le tue API key
sudo cp /etc/gavio/env.example /etc/gavio/env
sudo vim /etc/gavio/env
# (compila almeno GROQ_API_KEY o SUPABASE_*)

# Avvia GAVIO
sudo systemctl start gavio

# Guarda log in tempo reale
journalctl -u gavio -f

# Da host: verifica che risponde
# (Browser): http://localhost:8000
# (curl):    curl http://localhost:8000/health
```

### Uscita VM

`Ctrl-A`, poi `X` (sequenza QEMU monitor). La VM si spegne.

---

## Metodo B — VirtualBox (no WSL, no Nix)

Se non vuoi installare WSL/Nix, parti da una VM NixOS standard.

### Setup

1. Installa **VirtualBox** (https://www.virtualbox.org)
2. Scarica **NixOS minimal ISO** (https://nixos.org/download → "Minimal ISO image")
3. Crea VM:
   - Type: Linux / Other Linux (64-bit)
   - RAM: 4096 MB
   - Disco: VDI dynamic, 20 GB
   - Boot: monta la ISO scaricata
4. Configura **port forwarding** (Settings → Network → Adapter 1 → Port Forwarding):
   - SSH:    host 2222 → guest 22
   - GAVIO:  host 8000 → guest 8000
5. Configura **shared folder** per GAVIO:
   - Settings → Shared Folders → +
   - Path: `C:\Users\guido\Desktop\gavio`
   - Name: `gavio`
   - Auto-mount: ON, Mount point: `/opt/gavio`

### Installa NixOS

Boot dalla ISO, segui il manuale ufficiale
(https://nixos.org/manual/nixos/stable/#sec-installation).

Versione veloce:
```bash
# Partizionamento (GPT singola partizione)
parted /dev/sda -- mklabel gpt
parted /dev/sda -- mkpart primary ext4 1MiB 100%
mkfs.ext4 -L nixos /dev/sda1
mount /dev/disk/by-label/nixos /mnt

# Genera config e installa
nixos-generate-config --root /mnt
nixos-install --no-root-passwd
reboot
```

### Applica SOLEM

Dopo reboot, login come utente creato durante install:
```bash
# Trasferisci il repo solem/ nella VM (scp da host)
# Es. da host: scp -P 2222 -r C:\Users\guido\Desktop\solem gavio@localhost:/tmp/

# Sposta in posizione standard
sudo mv /tmp/solem /etc/nixos/solem

# Applica
cd /etc/nixos/solem
sudo SOLEM_DIR=/etc/nixos/solem ./scripts/setup-in-vm.sh

# Reboot, SOLEM attivo
sudo reboot
```

---

## Metodo C — Hyper-V (Windows 11 Pro)

Identico a VirtualBox ma con manager Hyper-V. Configura shared folder via SMB
(Hyper-V non ha shared folder native come VBox):

```powershell
# Su host: condividi cartella GAVIO via SMB
New-SmbShare -Name "gavio" -Path "C:\Users\guido\Desktop\gavio" -FullAccess "Everyone"
```

Dentro VM (dopo install NixOS):
```bash
# Aggiungi a configuration.nix
sudo mkdir /opt/gavio
sudo mount -t cifs //10.0.2.2/gavio /opt/gavio -o guest,uid=gavio,gid=users
```

---

## Troubleshooting

### "Permission denied" su /opt/gavio

```bash
sudo chown -R gavio:users /opt/gavio
```

### GAVIO non parte: deps Python mancanti

```bash
# Ricrea il venv
sudo rm -rf /var/lib/gavio/venv
sudo systemctl restart gavio
journalctl -u gavio -f
```

### Ollama non risponde

```bash
sudo systemctl status ollama
# Se serve scaricare un modello:
sudo -u gavio ollama pull llama3.2:3b
```

### Porte non raggiungibili da host

Verifica port forwarding (VirtualBox/Hyper-V) o la riga `forwardPorts` in
`nixos/hardware-vm.nix`.

### "Nix not found" su WSL

```bash
# Verifica install
which nix
# Se manca, ricarica shell o reinstalla con il comando "Setup una tantum"
```

---

## Spegnere / pulire la VM

| Metodo | Spegni | Reset stato |
|--------|--------|-------------|
| A (nix run) | `Ctrl-A X` | `rm result` (il disco è in /tmp dell'hypervisor) |
| B (VBox)    | Power off da menu | "Discard saved state" o ricrea VM |
| C (HyperV)  | Power off da manager | "Delete VM" |
