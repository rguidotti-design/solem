# SOLEM — Guida installazione

SOLEM è un OS basato su NixOS. Tre modi per installarlo, dal più semplice al più impegnativo.

## Opzione A — VM (test rapido, ~5 min)

Richiede: Linux/WSL2 con `nix` installato e KVM.

```bash
git clone https://github.com/rguidotti-design/solem
cd solem
nix run .#vm
```

Apre una finestra QEMU con SOLEM. Username: `gavio`, password: `gavio` (cambia subito).

## Opzione B — USB live + install su disco (consigliato per primo deploy reale)

### B.1 Build ISO

Richiede: Linux/WSL2 con `nix` (>= 2.18). Tempo: 3–8 min. Spazio: ~2 GB.

```bash
git clone https://github.com/rguidotti-design/solem
cd solem
./scripts/build-iso.sh
# → result/iso/nixos-*.iso
```

### B.2 Scrivi su USB stick

> Attenzione: `/dev/sdX` cancella tutto. Verifica con `lsblk` prima.

```bash
lsblk                                    # individua la chiavetta (es. /dev/sdb)
sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

### B.3 Boot dal USB

1. Inserisci la chiavetta nel PC target.
2. Entra nel BIOS (F2/F12/Del a seconda del firmware).
3. Disabilita Secure Boot (per ora; lanzaboote arriverà Step 2).
4. Imposta USB come primary boot.
5. Salva e riavvia.

### B.4 Install permanente

Una volta nel live system (login `gavio`/`gavio`):

```bash
# 1. Partiziona il disco target (esempio: /dev/nvme0n1)
sudo parted /dev/nvme0n1 -- mklabel gpt
sudo parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 512MiB
sudo parted /dev/nvme0n1 -- set 1 esp on
sudo parted /dev/nvme0n1 -- mkpart primary 512MiB 100%

# 2. Format
sudo mkfs.fat -F 32 -n boot /dev/nvme0n1p1
sudo mkfs.ext4 -L nixos /dev/nvme0n1p2     # o btrfs/zfs per snapshot

# 3. Mount
sudo mount /dev/disk/by-label/nixos /mnt
sudo mkdir -p /mnt/boot
sudo mount /dev/disk/by-label/boot /mnt/boot

# 4. Genera hardware config + clona repo SOLEM in /mnt/etc/nixos
sudo nixos-generate-config --root /mnt
cd /mnt/etc/nixos
sudo git clone https://github.com/rguidotti-design/solem .

# 5. Install
sudo nixos-install --flake .#solem-vm  # o .#solem-bare quando definito

# 6. Reboot + togli USB
sudo reboot
```

## Opzione C — Aggiungi SOLEM a un NixOS già installato

Richiede: NixOS già funzionante con flakes abilitati.

```bash
git clone https://github.com/rguidotti-design/solem
cd solem
sudo nixos-rebuild switch --flake .#solem-vm
```

## Post-install: primo boot

```bash
# 1. Crea account SOLEM (un solo account vale per TUTTI i device della mesh)
sudo solem-init

# 2. Verifica stato
solem status

# 3. (Opzionale) Aggiungi questo device al cluster
sudo systemctl enable --now solem-cluster-worker

# 4. (Opzionale) Avvia GAVIO
sudo systemctl enable --now gavio
```

## Profili

Durante `solem-init` scegli il profilo:

| Profilo    | Per cosa                             |
|------------|--------------------------------------|
| `minimal`  | server headless, niente desktop      |
| `developer`| toolchain Python/Rust/Go/Node/C++    |
| `creator`  | GIMP, Blender, Kdenlive, Audacity    |
| `server`   | datacenter, monitoring, mesh         |
| `desktop`  | Hyprland navy + Cormorant + waybar   |

## Troubleshooting

- **L'ISO non parte**: disabilita Secure Boot, riprova.
- **`solem status` dice "API offline"**: `sudo systemctl status solem-api`.
- **GAVIO non risponde**: serve GAVIO in `/opt/gavio` (vedi repo separato).
- **Mesh non si forma**: porta UDP 51820 aperta + chiavi WireGuard scambiate.

## Disinstallazione

NixOS è atomico: torni indietro con `nixos-rebuild --rollback` o scegli una generation precedente da GRUB.

## Cosa scaricare il primo boot (opzionale)

```bash
ollama pull qwen2.5-coder:7b      # code assistant
ollama pull nomic-embed-text      # embedding
ollama pull llava:7b              # vision
# Totale: ~10 GB
```

## Aggiornamenti

```bash
cd /etc/nixos
sudo git pull
sudo nixos-rebuild switch --flake .#solem-vm
```

oppure via API:
```bash
curl -X POST http://localhost:8001/solem/updates/apply
```

## Supporto

- Issue: https://github.com/rguidotti-design/solem/issues
- ADR (decisioni architetturali): [`docs/adr/`](docs/adr/)
- Memoria progetto: vedi `MEMORY.md`
