# SOLEM

**SOLEM** è un OS AI-native basato su NixOS, progettato dalle fondamenta per
ospitare AI come cittadini di prima classe.

In **Step 0** (oggi), SOLEM è il **corpo** che ospita **GAVIO** (l'AI personale
di Ruben Guidotti) come servizio nativo del sistema, con tutte le dipendenze
preinstallate e libertà operativa totale.

> GAVIO è il cervello. SOLEM è il corpo.

---

## Stato

- **Versione:** 0.1.0-step0
- **Roadmap:** vedi [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) (sezione Layer)
- **Target hardware finale:** Beelink mini-PC (Step 1, estate 2026)
- **Form factor supportati:** x86_64 workstation/server · ARM64 Raspberry Pi 4/5 · ARM64 Jetson Nano/Orin · PWA smart glasses (browser)
- **Cost:** 0 € (100% FOSS, niente cloud paid services)

### Artifacts buildati (al 2026-05-21, commit `a9cdcfd`)
- ✅ **ISO x86_64** bootable (5.5 GB) — `nix build .#iso`
- ✅ **Eval verde** per Raspberry, Jetson, VM, ISO
- ⏳ SD-image ARM64 da buildare on-demand (`nix build .#raspberry` / `.#jetson`)

### Stats
- 89 moduli NixOS opt-in
- 56 layer Python (FastAPI single-responsibility, GAVIO è l'unica AI)
- 240+ endpoint API
- 98 test in 18 file
- 10 ADR architetturali

---

## Quick start

Tre modi:

| Cosa | Comando | Per chi |
|---|---|---|
| VM rapida (test) | `nix run .#vm` | Sviluppatori, esplorare |
| ISO USB installabile | `nix build .#iso` → `dd` su USB | Install permanente |
| Preview browser cliccabile | `python tools/progress-server/server.py` → `http://localhost:9000/preview` | Vedere com'è SOLEM senza installarlo |
| PWA mobile/glass | `http://solem.local:8001/mobile` o `/glass` | Smartphone, smart glass |

Guida completa: **[INSTALL.md](INSTALL.md)**

### Opzione A — Con WSL2 + Nix (raccomandato, più rapido)

Da PowerShell:

```powershell
.\scripts\run-vm.ps1
```

Equivalente da WSL:

```bash
cd /mnt/c/Users/guido/Desktop/solem
nix run .#vm
```

QEMU si avvia, GAVIO parte come servizio systemd, raggiungibile su
`http://localhost:8000`.

### Opzione B — Senza Nix sull'host (VM "standalone")

1. Scarica [NixOS minimal ISO](https://nixos.org/download)
2. Crea VM in VirtualBox/Hyper-V/QEMU (4 GB RAM, 20 GB disco)
3. Installa NixOS minimal (segui [manuale ufficiale](https://nixos.org/manual/nixos/stable/#sec-installation))
4. Trasferisci la cartella `solem/` nella VM (USB, `scp`, shared folder)
5. Dentro la VM: `sudo SOLEM_DIR=/etc/nixos/solem ./scripts/setup-in-vm.sh`
6. Reboot → SOLEM attivo

Dettagli completi e troubleshooting: [docs/TESTING.md](docs/TESTING.md).

---

## Dopo il boot

Vedi **[docs/POST_BOOT.md](docs/POST_BOOT.md)** per la checklist primi 5 minuti.

Comandi più usati:

| Da WSL (`make ...`) | Da PowerShell                | Cosa fa                    |
|---------------------|------------------------------|----------------------------|
| `make ssh`          | `.\scripts\ssh.ps1`          | SSH dentro VM              |
| `make logs`         | `.\scripts\logs.ps1`         | tail log GAVIO             |
| `make setup-env`    | `.\scripts\setup-env.ps1`    | wizard env file + restart  |
| `make status`       | —                            | status servizi             |
| `make health`       | `curl localhost:8000/health` | check API                  |

---

## Struttura repo

```text
solem/
├── flake.nix                       # entry NixOS (definisce solem-vm)
├── Makefile                        # shortcut: make vm/ssh/logs/health
├── nixos/
│   ├── configuration.nix           # config principale (compone moduli)
│   ├── hardware-vm.nix             # VM QEMU + shared folder GAVIO + backend
│   └── modules/
│       ├── solem-core.nix          # utente gavio, Nix tuning, journald
│       ├── networking.nix          # firewall, SSH, mDNS
│       ├── security.nix            # fail2ban, audit, PAM limits
│       ├── ai-freedom.nix          # sudoers/polkit aperti per l'AI
│       ├── gavio.nix               # systemd service GAVIO + Ollama + Docker
│       ├── solem-api.nix           # systemd service SOLEM API :8001
│       ├── solem-backup.nix        # timer giornaliero snapshot stato
│       └── solem-layers.nix        # manifest L1–L7 + paths persistenti
├── backend/
│   └── solem_api/                  # API SOLEM (FastAPI, Layer 1-4 stub)
│       ├── main.py                 # /health /solem/manifest /solem/capabilities
│       ├── requirements.txt
│       └── __init__.py
├── scripts/
│   ├── run-vm.sh / run-vm.ps1      # `nix run .#vm` da WSL/PowerShell
│   ├── build-vm.sh                 # build esplicito
│   ├── setup-in-vm.sh              # applica config in VM NixOS standalone
│   ├── ssh.ps1 / logs.ps1          # accesso VM senza entrare in console
│   └── setup-env.ps1               # wizard /etc/gavio/env
└── docs/
    ├── ARCHITECTURE.md             # 7 layer + come SOLEM ospita GAVIO
    ├── TESTING.md                  # 3 metodi test VM + troubleshoot
    ├── POST_BOOT.md                # checklist primi 5 minuti
    ├── AI_FREEDOM.md               # filosofia + dettagli permessi AI
    ├── MESH.md                     # VPN WireGuard tra device SOLEM
    ├── ZERO_TRUST.md               # mTLS + CA + audit log
    ├── COMPETITIVE.md              # SOLEM vs altri OS
    └── api/solem-api.openapi.yaml  # OpenAPI 3.1 spec SOLEM API
```

## API esposte

| Porta | Servizio  | Cosa                                                      |
|-------|-----------|-----------------------------------------------------------|
| 8000  | GAVIO     | API GAVIO esistente (9 nodi, web UI)                      |
| 8001  | SOLEM API | **Nuovo Step 0**: /manifest, /capabilities, /identity/me  |
| 11434 | Ollama    | LLM locali                                                |
| 22    | SSH       | Accesso shell (forward host :2222)                        |

La SOLEM API è progettata AI-first: ogni endpoint ha schema JSON strutturato,
OpenAPI completo, errori machine-readable. È **l'API che le future AI
chiameranno** per scoprire cosa SOLEM sa fare. Spec in
[docs/api/solem-api.openapi.yaml](docs/api/solem-api.openapi.yaml).

---

## Cosa NON è in scope (Step 0)

Le seguenti feature sono nella spec SOLEM ma arrivano in step successivi:

- Multi-tenant attivato (design pronto, attivazione Step 4)
- Identity Engine completo (vive in KAIROS, estrazione Step 2)
- Messaging E2E (Step 2)
- Memoria 3 livelli con embedding (parziale in GAVIO, completamento Step 2-3)
- AI specialiste oltre GAVIO (Step 3)
- Extensions Marketplace (Step 4+)

---

## Principi non negoziabili

1. **Una sola entità, molte finestre** — device = thin client
2. **La leva è orientata, non cieca** — Identity guida ogni decisione AI
3. **Adattivo, mai prescrittivo**
4. **Vibe e precisione convivono**
5. **Collaborazione aperta, fondamenta sigillate**
6. **Indipendenza, non isolamento** — i tuoi dati restano tuoi
7. **Costruttore-friendly per natura**
