# ADR-010 — Multi-arch: x86_64 (workstation) + aarch64 (Raspberry/Jetson) + PWA (smart glasses)

**Status**: Accepted (2026-05-21)
**Deciders**: Ruben Guidotti
**Tags**: hardware, scalability, cluster

## Contesto

SOLEM è nato per x86_64 (Beelink mini PC), ma Ruben ha esplicitato la roadmap:

> "fai in modo che possa girare ovunque anche su raspberry e jetson nano o smart glass e gestirli tutti al massimo possibile"

Tre classi di device hanno caratteristiche profondamente diverse:

| Classe        | Esempio       | RAM   | GPU   | Storage  | Display |
|---------------|---------------|-------|-------|----------|---------|
| Workstation   | Beelink, NUC  | 16–64 GB | optional dGPU | NVMe | full HD/4K |
| Edge ARM CPU  | Raspberry Pi  | 2–8 GB | iGPU VC | SD card | optional HDMI |
| Edge ARM GPU  | Jetson Nano   | 4–16 GB | Tegra CUDA | SD/NVMe | optional |
| Smart glasses | Vuzix/Xreal   | 2–6 GB | mobile | flash 8–64 GB | OLED HUD micro |

Tre vincoli:
1. **Un solo codebase** mantenibile (no fork per ogni HW).
2. **Free + FOSS** ([[feedback_solem_only_free]]).
3. **GAVIO unica AI**, ma il cluster eterogeneo deve dispatchare ai device giusti ([[solem-gavio-only-ai]]).

## Decisione

### Multi-arch native nel flake

`flake.nix` dichiara:

```nix
systems = [ "x86_64-linux" "aarch64-linux" ];
nixosConfigurations = {
  solem-vm        = ...;   # x86_64 QEMU
  solem-iso       = ...;   # x86_64 USB installable
  solem-raspberry = ...;   # aarch64 Pi 4/5 SD image
  solem-jetson    = ...;   # aarch64 Jetson SD image
};
```

Cross-build da x86_64 host via `binfmt_misc + qemu-user-static`.

### Profili dedicati per device class

- `nixos/configuration-edge.nix`: base ARM headless (no desktop, SSH+mesh, NetworkManager).
- `nixos/modules/solem-edge.nix`: tuning low-power (ZRAM 100%, journal volatile, watchdog 30s, sysctl swappiness=10).
- `nixos/modules/solem-raspberry.nix`: firmware Broadcom + GPIO/I2C/SPI + camera CSI opt.
- `nixos/modules/solem-jetson.nix`: scaffold Tegra CUDA + Ollama GPU acceleration.

### Smart glasses: NON un OS, ma una PWA

Smart glasses commerciali (Vuzix, Xreal, Brilliant, Meta) **girano Android o RTOS proprietari**. Forking il loro OS non è praticabile né necessario.

Decisione: SOLEM offre **`/glass`**, una PWA voice-first servita da `solem-api` (porta 8001). Le glasses la aprono nel browser e diventano "control panel" remoto via mesh:

- Web Speech API → microfono → ask GAVIO via `/solem/ai/route`.
- Speech Synthesis API → risposta TTS nell'auricolare.
- Server-Sent Events → notifiche handoff push.
- Auto-registrazione cluster come `device_class=glass-companion`.

### Cluster eterogeneo device-class-aware

`cluster.py` `_score()` ora considera `device_class`:

| device_class      | Bonus su                         | Penalità su        |
|-------------------|----------------------------------|--------------------|
| workstation       | +10 generico (workload pesanti)  | nessuna            |
| edge-gpu          | +50 vision/embedding small       | -30 task xlarge    |
| edge-cpu          | +40 stt/tts tiny                 | -60 task medium+   |
| iot               | tiny only                        | -200 altro         |
| glass-companion   | +20 stt/tts tiny                 | -100 altro         |
| mobile            | +20 stt/tts tiny                 | -100 altro         |

Garanzia: una richiesta `llm_inference xlarge` **non** finirà mai su un Raspberry o smart glass.

## Alternative considerate

### A. Build separati per arch (forks)
**Rifiutato**: triplica il lavoro di manutenzione, divergono nel tempo.

### B. Containers (Docker/Podman) cross-arch
**Rifiutato come default**: NixOS dà riproducibilità migliore per OS-level. Containers restano disponibili per workload (solem-containers.nix), non come strategia di distribuzione SOLEM.

### C. PostmarketOS / Mobian per glasses
**Rifiutato**: gli smart glass non hanno bootloader Linux sbloccabile in modo affidabile. PWA è universale (qualunque glass con browser moderno) e mantiene-installabile.

### D. Cloud relay per glass (es. server centrale che processa)
**Rifiutato**: viola [[feedback_solem_only_free]] e privacy by design. Mesh-only resta la regola.

## Conseguenze

### Positive
- Un codebase, 4 target build.
- Workstation, Raspberry, Jetson, smart glasses, PWA mobile: tutti membri della stessa mesh con stesso `account SOLEM` (federation).
- Cluster dispatcha automaticamente al device più adatto.
- Smart glasses gratis (no app store, no licenze) via PWA.

### Negative
- Cross-build ARM su x86_64 richiede `binfmt` (overhead 1.5×–3× su host x86_64 first build).
- Jetson scaffold incompleto: serve `jetpack-nixos` overlay esterno per CUDA Tegra reale.
- PWA `/glass` dipende da browser smart-glass-side (Vuzix Blade ha Chromium 49, Xreal Air più recente).

### Mitigazioni
- ISO build x86_64 testato in CI (`build-image.sh iso`).
- SD images aarch64 generate on-demand, non versionate.
- Jetson user deve manualmente integrare jetpack-nixos finché upstream non aggiunge supporto generico.

## Roadmap collegata

- [[project_solem_multiarch]] (memoria progetto)
- [[project_solem_future_scale]] (HPC + quantum + data center: anche multi-arch)
- Step 1+: integrare jetpack-nixos per Jetson CUDA reale
- Step 2+: cross-compile cache CI per ridurre tempi build

## Note implementative

- `solem-cluster-worker` daemon detecta automaticamente `device_class` via:
  - `/proc/cpuinfo` aarch64 → "edge-cpu"
  - `nvidia-smi` esito ok → "edge-gpu" o "workstation" in base a RAM totale
  - User-agent PWA `mobile|ios|android` → "mobile" o "glass-companion"
- Worker invia heartbeat ogni 30s con load reale al gateway.
- Gateway tiene `device_class` per scoring runtime.
