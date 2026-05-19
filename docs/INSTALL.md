# SOLEM — Installazione bare-metal

Guida per installare SOLEM su hardware reale (Beelink mini-PC, laptop, server).

> Per testare prima senza installare: [TESTING.md](TESTING.md) (VM).

---

## Pre-requisiti

- Hardware **x86_64** con ≥ 4 GB RAM, ≥ 40 GB disco
- USB stick ≥ 4 GB (per ISO live)
- Connessione internet (Wi-Fi o Ethernet)
- Backup dei dati esistenti — l'installazione **cancella tutto** sul disco target

---

## Procedura standard (con LUKS encryption)

### 1. Prepara ISO NixOS

```bash
# Scarica ISO minimal (~1 GB)
wget https://channels.nixos.org/nixos-24.11/latest-nixos-minimal-x86_64-linux.iso

# Verifica SHA256 (opzionale)
sha256sum -c latest-nixos-minimal-x86_64-linux.iso.sha256

# Flash USB (sostituisci /dev/sdX con il tuo USB device)
sudo dd if=latest-nixos-minimal-x86_64-linux.iso of=/dev/sdX bs=4M status=progress
sync
```

### 2. Boot da USB sul target hardware

- Inserisci USB, accendi, entra in boot menu (di solito F12 / F11 / Esc / Del a seconda dell'hardware)
- Scegli USB come boot device
- Aspetta boot NixOS live

### 3. Connetti a internet

Se Ethernet → dovrebbe essere automatico, verifica con `ping nixos.org`.

Se Wi-Fi:
```bash
sudo systemctl start wpa_supplicant
sudo wpa_cli
> add_network
> set_network 0 ssid "TuaRete"
> set_network 0 psk "tuapassword"
> enable_network 0
> save_config
> quit
```

### 4. Esegui solem-install

**Opzione A — da repo Git remoto:**
```bash
nix-shell -p git --run "git clone --depth 1 https://github.com/<user>/solem"
cd solem
sudo ./scripts/solem-install.sh
```

**Opzione B — da USB con repo precaricato:**
```bash
# Se hai messo il repo solem/ in /iso/solem sull'USB
sudo SOLEM_SOURCE=/iso/solem ./scripts/solem-install.sh
```

Il wizard chiederà:
- Disco target (`/dev/sda`, `/dev/nvme0n1`, …)
- Conferma cancellazione dati
- Cifrare con LUKS2 (consigliato: **sì**)
- Passphrase LUKS (12+ caratteri, MAI dimenticarla)
- URL repo Git (se non già locale)

Tempo: **10-30 minuti** (dipende da CPU/disco/rete).

### 5. Primo boot

- `reboot` (rimuovi USB)
- Inserisci passphrase LUKS al prompt
- Login `gavio` / password configurata
- Cambia password: `passwd`

---

## Profili consigliati

Dopo install, edita `/etc/nixos/solem/nixos/configuration.nix`:

| Hardware | Profilo consigliato |
|----------|---------------------|
| Beelink mini-PC casa (server primario) | `server` + mesh + zero-trust |
| Laptop developer | `developer` + desktop |
| Workstation creator/ricercatore | `creator` + desktop + AI |
| Raspberry Pi edge node | `minimal` + mesh peer |

```nix
solem.profile = "server";          # o developer/creator/desktop
solem.mesh.enable = true;          # se ha senso nel tuo setup
solem.zeroTrust.enable = true;
solem.update.enable = true;
solem.secure.kernelHardening.enable = true;
```

Applica: `sudo nixos-rebuild switch --flake /etc/nixos/solem#solem-bare`.

---

## Post-install — verifica

```bash
solem-doctor              # diagnostica 30+ check (deve dire 0 fail)
solem status              # quadro sistema
systemctl status gavio    # GAVIO attivo?
curl localhost:8001/health
```

Dashboard accessibile da host LAN:
- `http://<ip>:8001` o `http://solem.local:8001` (mDNS Avahi)

---

## Aggiornamenti

Auto-update settimanale (se `solem.update.enable = true`):
- Timer systemd `solem-update.timer` esegue `nixos-rebuild boot --refresh` settimanalmente
- Applicato al PROSSIMO riavvio (non interrompe sessione corrente)
- Rollback automatico se boot fallisce 3 volte consecutive (`systemd-boot tries`)

Manuale:
```bash
sudo nixos-rebuild switch --flake /etc/nixos/solem#solem-bare --refresh
```

Rollback:
```bash
sudo nixos-rebuild switch --rollback
# oppure dal menu systemd-boot al riavvio
```

---

## Disaster recovery

**Boot fallisce:**
- Al menu systemd-boot scegli generation precedente
- Dopo 3 boot fallimenti consecutivi → rollback automatico

**Password persa:**
- Boot in modalità single-user (kernel param `single`)
- Edita `/etc/nixos/solem/nixos/modules/solem-core.nix` → nuovo `hashedPassword`
- `nixos-rebuild switch`

**LUKS passphrase persa:**
- **Non recuperabile.** Reinstallazione richiesta.
- Mitigazione: tieni copia passphrase in password manager fidato + chiave recovery LUKS (`cryptsetup luksAddKey`).

**Disco fail:**
- Backup automatico in `/var/backups/solem/` (vedi [POST_BOOT.md](POST_BOOT.md))
- Restore: scarica backup, decomprimi, copia su nuovo disco dopo install pulita.

---

## Step 1+ (futuro)

- Secure Boot via Lanzaboote (chiavi UEFI firmate)
- sops-nix per secret cifrati in repo
- Backup remoto verso altro nodo SOLEM (mesh peer) via restic/rsync — niente servizi cloud paganti
- Multi-disco RAID/btrfs subvolumes
