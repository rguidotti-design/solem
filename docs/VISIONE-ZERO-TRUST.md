# SOLEM — Visione Zero-Trust + AI-Native (architettura completa)

> Definizione di scopo per chiunque legge il codice.
> Non è marketing. Le cose elencate qui sono **da implementare/validare**,
> molte sono **scaffold** che richiedono testing reale.

---

## Scopo

SOLEM è un OS che:

1. **Protegge i dati** prima di tutto. Da malware, da AI (incluso il suo
   GAVIO), da reti ostili, da operatori curiosi.
2. **Lavora ovunque**: workstation, server, supercomputer, HPC, quantum,
   edge, mobile.
3. **Si adatta al workload**: informatica, CAD, cybersec, finanza, AI, HPC.
4. **È il miglior punto di contatto IA↔uomo**: AI può agire ma con
   guardrails, audit, kill switch.

Non è "OS open-source generico". È un OS **opinionated** che mette la
**sicurezza dei dati** e il **controllo umano sull'AI** come pilastri.

---

## Pilastri tecnici

### 1. Zero Trust per le AI (inclusa GAVIO)

**Principio**: GAVIO è un servizio sospetto come qualunque altro processo.
Può agire ma OGNI azione è:
- Verificata (whitelist/blacklist),
- Limitata (sandbox bubblewrap),
- Loggata (audit immutabile),
- Monitorata (Falco eBPF runtime),
- Killable automaticamente (kill switch su threshold).

**Modulo**: `solem-ai-guardrails.nix` ([nixos/modules/solem-ai-guardrails.nix](../nixos/modules/solem-ai-guardrails.nix))

**CLI**: `solem-guard exec <comando>` — GAVIO chiama QUESTO, non shell diretta.

**Architettura runtime**:

```
GAVIO (user non-root)
  │
  ▼
solem-guard exec "comando"
  │
  ├── 1. BLACKLIST? (rm -rf, mkfs, shutdown) → BLOCKED + log
  ├── 2. WHITELIST? (uname, ls, solem-api) → ALLOW + bubblewrap
  └── 3. Altro → NOTIFY USER + tty prompt → ALLOW/DENY + log
        │
        ▼ parallel:
      Falco eBPF watcher
        │
        ▼ trigger su:
        - AI outbound a IP non-LAN
        - AI scrive in /etc/usr/boot
        - AI spawna shell non-wrappata
        │
        ▼  ≥ 5 violazioni in 60s:
      Kill switch → systemctl stop gavio + notify
```

**systemd hardening** (gavio.service):
- `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict`
- `ProtectHome=tmpfs`, `RestrictNamespaces`
- `SystemCallFilter @system-service ~@privileged`
- `IPAddressDeny any` (eccetto LAN)
- `MemoryHigh=3G` (no DOS)

### 2. Protezione dati end-to-end

| Layer | Tool FOSS | Status |
|---|---|---|
| Full Disk Encryption | LUKS2 + cryptsetup | scaffold (`solem-secure.nix`) |
| Secure Boot + TPM2 | Lanzaboote + tpm2-tools | scaffold (`solem-secure-boot.nix`) |
| Per-file encryption | age + sops-nix | scaffold (`solem-secrets.nix`) |
| Network: VPN doppia | WireGuard mesh + tunnel esterno | scaffold (`solem-double-vpn.nix`) |
| DNS protetto | stubby+unbound (DoT/DoH) | scaffold (`solem-dns-private.nix`) |
| Block ads/trackers | blocky | scaffold (`solem-dns-blocker.nix`) |
| E2EE sync | Nextcloud client-side + Vaultwarden | scaffold (`solem-cloud-personal.nix`) |
| Backup encrypted | restic + age key | scaffold (`solem-backup-restic.nix`) |
| Privacy network | Tor + I2P + Yggdrasil opt-in | scaffold (`solem-tor.nix`, `solem-privacy-network.nix`) |
| Shred-on-trash | shred multi-pass | scaffold (`solem-privacy-tools.nix`) |

**Doppia VPN architecture**:

```
Application
  │
  ▼
WireGuard mesh SOLEM (interno, peer-to-peer authenticated)
  │
  ▼
Tunnel esterno (Mullvad/Tailscale/self-host VPN)
  │
  ▼
Internet
```

Routing: ogni pacchetto passa per **due** tunnel encrypted independent. Se uno è compromesso, l'altro protegge.

### 3. Anti-malware proattivo

| Threat | Tool FOSS | Status |
|---|---|---|
| Rootkit | rkhunter + chkrootkit | da aggiungere |
| Antivirus | ClamAV (FOSS, GPL) | da aggiungere |
| Runtime behavior | Falco eBPF | scaffold (`solem-ai-guardrails.falco`) |
| USB injection | USBGuard allowlist | scaffold (`solem-usbguard.nix`) |
| Outbound firewall | Opensnitch interactive | scaffold (`solem-opensnitch.nix`) |
| Process integrity | AIDE / Tripwire | da aggiungere |
| Mandatory access control | AppArmor profiles | scaffold (`solem-secure.apparmor`) |
| Container isolation | bubblewrap + nsjail | scaffold (`solem-sandbox.nix`) |
| Kernel lockdown | KSPP boot cmdline | scaffold (`solem-kernel-hardening.nix`) |
| Memory protection | MemoryDenyWriteExecute (selettivo) | scaffold |

**Detection-before-execution**: file scaricati → ClamAV scan automatico
prima di eseguibile. Browser download hook (Firefox extension TODO).

### 4. Auto-adatta al workload

**Modulo**: `solem-workload-detect.nix`

**CLI**: `solem-workload apply <profile>` o `solem-workload auto`

Profili con tuning specifico:

| Profilo | Use case | CPU gov | swappiness | dirty_ratio | extras |
|---|---|---|---|---|---|
| `coding` | Dev VSCode/Vim/Cargo/Go | performance | 10 | default | ulimit alti |
| `cad` | FreeCAD/Blender/KiCad | performance | 5 | 5 | GPU max |
| `cybersec` | Wireshark/Nmap/Burp | performance | default | default | promiscuous OK |
| `finanza` | Jupyter/Pandas/R | performance | 60 | default | swap aggressivo |
| `server` | Self-host 24/7 | schedutil | 10 | default | no sleep |
| `hpc/ai` | CUDA/ROCm/qiskit | performance | 1 | 3 | huge pages |
| `balanced` | Laptop daily | schedutil | 60 | 20 | default |

Detection automatica: osserva `ps -eo comm` ogni 5 min, mappa a profilo.

### 5. Multi-target (workstation → quantum)

| Target | Modulo | Stato |
|---|---|---|
| Workstation x86_64 | `solem-vm-minimal` | scaffold |
| Laptop con TLP charge limit | `solem-battery-pro.nix` | scaffold |
| Server (no GUI, 24/7) | `solem-server-mode.nix` | scaffold |
| Raspberry Pi 4/5 | `solem-raspberry.nix` | scaffold |
| Jetson Nano/Orin | `solem-jetson.nix` | scaffold |
| Apple Silicon (Asahi) | `solem-asahi.nix` | scaffold |
| PinePhone mobile | `solem-pinephone.nix` | scaffold |
| Steam Deck-like | `solem-steam-deck.nix` | scaffold |
| HPC cluster | `solem-hpc.nix` | scaffold |
| Quantum (Qiskit/Cirq) | `solem-quantum.nix` | scaffold |
| Datacenter rack | `solem-datacenter.nix` | scaffold |
| WSL2 (Windows host) | `solem-wsl.nix` | scaffold |

Tutti questi sono **dichiarazioni Nix**. Ogni target richiede test reale
su hardware specifico. La maggior parte NON è ancora stata validata.

### 6. Database + server-side

| Servizio | FOSS | Stato |
|---|---|---|
| PostgreSQL | ✅ | NixOS module standard |
| MySQL/MariaDB | ✅ | NixOS module standard |
| Redis | ✅ | NixOS module standard |
| pgAdmin GUI | ✅ | in `solem-database.nix` |
| Backup pg_dump | ✅ | in `solem-supabase-backup.nix` |
| Object storage (S3-compat) | MinIO ✅ | in `solem-data-engineering.nix` |
| Time-series | InfluxDB/QuestDB ✅ | da aggiungere |
| Graph DB | Neo4j / Memgraph | da aggiungere |

### 7. HPC + Quantum + AI

| Stack | FOSS | Stato |
|---|---|---|
| Container HPC (Apptainer) | ✅ | da aggiungere a `solem-hpc.nix` |
| Workload manager (SLURM) | ✅ | scaffold |
| MPI (OpenMPI) | ✅ | scaffold |
| CUDA (NVIDIA) | unfree opt-in | scaffold (`solem-ai-hardware-tuning.nix`) |
| ROCm (AMD) | ✅ | scaffold |
| Qiskit (IBM Quantum) | ✅ (Apache-2.0) | scaffold (`solem-quantum.nix`) |
| Cirq (Google Quantum) | ✅ | scaffold |
| Ollama (LLM local) | ✅ | esiste in nixpkgs |
| llama.cpp | ✅ | esiste |
| vLLM (production LLM) | ✅ | esiste |

---

## Pilastri NON tecnici

### 8. Onestà radicale

Questo doc dice la verità:

- **Maggior parte moduli sono scaffold**. Hanno la struttura giusta ma
  non sono stati testati runtime.
- **CI non verde end-to-end ancora**. Quick Validate sì, SOLEM CI build
  iso fail.
- **GAVIO è uno STUB**. Necessario impacchettare backend reale.
- **Zero utenti**. Il design pensato per molti, l'uso ancora di uno.

### 9. Single Responsibility

Ogni modulo `solem-X.nix`:
- Fa UNA cosa
- È opt-in (`cfg.enable` default false eccetto base)
- Documenta dipendenze
- Ha test (TODO: VM tests per ognuno)

### 10. FOSS-only di default

Closed-source SOLO con opt-in esplicito utente (es. NVIDIA driver,
Steam, Widevine, Slack desktop). Mai forzato dal default.

---

## Roadmap implementazione (priorità in ordine)

### Step 1 — Fondamenta sicurezza (mesi 1-3)

**Goal**: SOLEM minimal che boota, GAVIO stub, guardrails attivi.

- [ ] CI verde end-to-end (Build iso, VM tests)
- [ ] ISO bootabile testato su QEMU + Beelink reale
- [ ] solem-ai-guardrails attivo + Falco eBPF runtime
- [ ] solem-secure (LUKS2 + Secure Boot + TPM2) validato su hardware
- [ ] solem-double-vpn testato con WireGuard mesh + Mullvad
- [ ] auditd + AppArmor profiles per servizi core

### Step 2 — AI native funzionante (mesi 3-6)

**Goal**: GAVIO reale (no stub), tool-calling via solem-api,
workload auto-adapt.

- [ ] GAVIO impacchettato come Nix derivation (no stub)
- [ ] Tool-calling pattern documentato e testato
- [ ] solem-workload-detect auto-applica profili (testing reale)
- [ ] LLM locale (Ollama) integrato con GAVIO
- [ ] Wake word "Hey GAVIO" con openWakeWord (offline)
- [ ] Anomaly detection ML per guardrails (oltre rule-based)

### Step 3 — Multi-target validation (mesi 6-9)

**Goal**: testare TUTTE le configs nixosConfigurations su hardware reale.

- [ ] Workstation x86_64 (Beelink) — daily driver autore
- [ ] Raspberry Pi 4/5 SD image bootabile
- [ ] Jetson Nano/Orin con CUDA Tegra
- [ ] Server modalità 24/7 (no sleep, no GUI)
- [ ] WSL2 — distribution importabile
- [ ] PinePhone — base usabile

### Step 4 — Workload specifici (mesi 9-12)

**Goal**: profilo informatica/CAD/cybersec/finanza/HPC funzionanti.

- [ ] Profilo `coding`: VSCodium + nix-shell ready
- [ ] Profilo `cad`: FreeCAD + Blender + KiCad + GPU
- [ ] Profilo `cybersec`: pentest tools + isolated network
- [ ] Profilo `finanza`: Jupyter + pandas + GnuCash
- [ ] Profilo `hpc`: SLURM single-node + multi-node test
- [ ] Profilo `quantum`: Qiskit simulazione + IBM backend

### Step 5 — Production hardening (anno 2)

- [ ] Compliance audit (CIS, NIST)
- [ ] Pentesting esterno (community)
- [ ] Performance benchmark vs Ubuntu/Win/macOS
- [ ] Documentazione utente completa
- [ ] Bug bounty program

---

## Cosa NON faremo

- Telemetria (mai)
- Account centralizzato obbligatorio
- DRM Widevine L1 (richiede hardware vendor cert)
- App store con paywall
- "GAVIO Premium" tier
- Closed-source di default
- AI cloud-only (deve avere fallback locale)
- Force-update senza consenso utente

---

## Come contribuire

1. Forka il repo
2. Crea modulo `solem-X.nix` single-responsibility
3. Documenta in `docs/MODULO-X.md`
4. Aggiungi VM test in `nixos/tests/X.nix`
5. PR con descrizione del problema risolto

Niente PR cosmetiche. Niente moduli aggiunti senza test. Niente codice
che non è stato eseguito almeno una volta.

---

## Take-away

SOLEM è un **progetto serio di nicchia** con visione precisa:
**sicurezza dati + AI sotto controllo umano + workload polymorphism**.

Non è un sostituto Windows/macOS per il mass market.
È uno strumento per chi ha bisogno di **controllo totale** sui propri
sistemi e dati.

La community (utenti, contributor, sponsor) verrà costruita dall'autore
del progetto man mano che la base tecnica diventa solida.

Step-by-step, no fake, no shortcut.
