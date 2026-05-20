# SOLEM — Guida installazione

SOLEM gira su 3 form factor con un solo codebase:

| Form factor              | Architettura | Target build               | Tempo build |
|--------------------------|--------------|----------------------------|-------------|
| Workstation / Server     | x86_64       | `nix build .#iso`          | 3–8 min     |
| Raspberry Pi 4/5         | aarch64      | `nix build .#raspberry`    | 10–20 min   |
| Jetson Nano / Orin       | aarch64      | `nix build .#jetson`       | 10–25 min   |
| VM (test rapido)         | x86_64       | `nix run .#vm`             | < 5 min     |
| Smart glasses (companion)| browser PWA  | apri `http://solem.local:8001/glass` su smart glass | — |

Le opzioni di installazione qui sotto, dal più semplice al più impegnativo.

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

## Opzione D — Raspberry Pi 4/5 (edge ARM64)

SOLEM gira su Raspberry Pi come worker cluster, IoT controller o mini-NAS.

### D.1 Build SD image (richiede Linux/WSL2 + binfmt aarch64)

```bash
# Su NixOS host abilita prima cross-build aarch64:
#   boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
git clone https://github.com/rguidotti-design/solem
cd solem
./scripts/build-image.sh raspberry
# → result/sd-image/*.img (~2 GB, 10-20 min)
```

### D.2 Scrivi su microSD

```bash
lsblk  # individua la SD (es. /dev/sdb)
sudo dd if=result/sd-image/*.img of=/dev/sdX bs=4M status=progress conv=fsync
```

### D.3 Boot Pi headless

1. Inserisci la SD nel Pi 4/5, collega ethernet (o configura WiFi via `wpa_supplicant.conf`).
2. Boot → si registra al cluster come worker `edge-cpu` automaticamente.
3. SSH: `ssh gavio@solem-pi-pi4.local` (password iniziale `gavio`, **cambia subito**).

Il Pi appare come device della mesh con `device_class=edge-cpu`. Il cluster lo userà per task STT/TTS/IoT tiny, mai inference grandi.

## Opzione E — Jetson Nano / Orin (edge GPU CUDA)

```bash
./scripts/build-image.sh jetson
# → result/sd-image/*.img
```

> ⚠️ Lo scaffold attuale **non include il BSP NVIDIA L4T completo**.
> Per CUDA Tegra funzionante, integra [`jetpack-nixos`](https://github.com/anduril/jetpack-nixos):
>
> ```nix
> inputs.jetpack-nixos.url = "github:anduril/jetpack-nixos";
> # ...
> modules = [ jetpack-nixos.nixosModules.default ];
> hardware.nvidia-jetpack.enable = true;
> ```

Il Jetson appare nel cluster come `edge-gpu` → riceve task vision/embedding small/medium.

## Opzione F — Smart Glasses (PWA companion)

Smart glasses **non eseguono SOLEM nativamente** (Android/RTOS proprietari). SOLEM fornisce una webapp dedicata:

1. Sul tuo smart glass apri il browser → `http://solem.local:8001/glass` (sostituisci con IP del gateway).
2. Premi il bottone "PARLA" o usa la voce → richiesta passa a GAVIO via mesh.
3. TTS risponde nell'auricolare/altoparlante del glass.
4. Notifiche handoff arrivano via Server-Sent Events.

Supportato su qualunque smart glass con browser moderno (Chromium/WebKit) e Web Speech API: Vuzix Blade, Xreal Air, Brilliant Frame, Meta Ray-Ban con browser, ecc.

Il glass si auto-registra al cluster come `device_class=glass-companion` (riceve solo task voce brevi).

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
