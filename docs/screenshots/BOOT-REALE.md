# SOLEM — boot reale dimostrato

Catturato il 2026-06-02 da VM SOLEM buildata via `nix build .#vm`
in WSL Ubuntu (Linux 6.x kernel hardened) + QEMU headless.

Quello sotto è **output VERO**, non mockup HTML.

---

## 1. Boot completo NixOS + systemd services

Output console seriale durante boot:

```
[  OK  ] Started Name Service Cache Daemon (nsncd).
[  OK  ] Reached target Host and Network Name Lookups.
[  OK  ] Reached target User and Group Name Lookups.
[  OK  ] Started Network Manager Script Dispatcher Service.
[  OK  ] Finished Firewall.
[  OK  ] Started Hostname Service.
[  OK  ] Started Network Manager.
[  OK  ] Reached target Network.
         Starting Network Manager Wait Online...
         Starting CUPS Scheduler...
         Starting SSH Daemon...
         Starting Permit User Sessions...
[  OK  ] Finished Permit User Sessions.
[  OK  ] Started Getty on tty1.
[  OK  ] Started Serial Getty on ttyS0.
[  OK  ] Reached target Login Prompts.
[  OK  ] Started Linux Audit daemon.        ← Step 9 audit AI-specific
[  OK  ] Started Timer for ClamAV virus database updater (freshclam).  ← anti-malware
[  OK  ] Started Discard unused filesystem blocks once a week.
[  OK  ] Started nix-gc.timer.
[  OK  ] Started Daily Cleanup of Temporary Directories.
```

## 2. Banner ASCII SOLEM al login

```
███████╗  ██████╗  ██╗      ███████╗ ███╗   ███╗
██╔════╝ ██╔═══██╗ ██║      ██╔════╝ ████╗ ████║
███████╗ ██║   ██║ ██║      █████╗   ██╔████╔██║
╚════██║ ██║   ██║ ██║      ██╔══╝   ██║╚██╔╝██║
███████║ ╚██████╔╝ ███████╗ ███████╗ ██║ ╚═╝ ██║
╚══════╝  ╚═════╝  ╚══════╝ ╚══════╝ ╚═╝     ╚═╝

AI-native OS  ·  v0.1.0-step0

solem-vm login: gavio
Password:
```

## 3. MOTD personalizzato post-login (terminale interattivo)

Dopo login (user=`gavio` pass=`gavio`):

```
╭──────────────────────────────────────────────────────────────╮
│  SOLEM  ·  v0.1.0-step0                                      │
│  digita 'solem status' per il quadro live del sistema        │
╰──────────────────────────────────────────────────────────────╯

  SOLEM  —  AI-native OS
  martedì 02 giugno 2026 · 09:19

  Servizi
    gavio.service      ○ down         http://localhost:8000
    solem-api.service  ○ down         http://localhost:8001
    ollama.service     ○ down         http://localhost:11434
    docker.service     ○ down

  Strumenti
    solem status       stato sistema completo
    solem caps         capabilities scoperte
    solem layers       stato dei 7 layer
    solem pair         genera PIN per aggiungere device

  Dashboard  http://localhost:8001    (da host)
```

## 4. Comandi eseguiti dentro la VM

`gavio@solem-vm:~$ solem status`

```
solem-api irraggiungibile su http://127.0.0.1:8001
  → <urlopen error [Errno 111] Connection refused>
  prova: sudo systemctl status solem-api
```

(VM minimale: solem-api/gavio-api non sono attivi di default — richiede
abilitazione esplicita config + package GAVIO; vedi Step 30/51.)

`gavio@solem-vm:~$ solem layers`

```
solem-api irraggiungibile su http://127.0.0.1:8001
  → <urlopen error [Errno 111] Connection refused>
```

(Stesso pattern: i comandi `solem` esistono e parlano con API, ma in
VM minimale l'API non gira. Per VM completa: abilita `solem.api.enable`.)

## 5. Servizi systemd attivi nella VM minimale

- `auditd` (Step 9 / audit)
- `clamav-freshclam` (timer — anti-malware Step "anti-malware")
- `nix-gc.timer` (garbage collection)
- `NetworkManager`
- `sshd`
- `cups` (printing scheduler)
- `dbus`
- `polkit`
- `nsncd` (name service cache)
- `systemd-resolved`
- `systemd-logind`

## Conferma onesta

**SOLEM E' UN OS VERO**. Boota, mostra login branded, MOTD personalizzato,
comandi `solem` installati globalmente, services systemd reali (audit,
clamav, network, etc).

**Quello che NON gira nella VM minimal**:
- `solem-api` (serve abilitarlo via flake module)
- `gavio.service` (richiede src GAVIO + Step 30/51)
- `ollama.service` (richiede modelli pre-download)
- Desktop grafico (la VM esegue console-only di default; per desktop
  reale: `solem.desktop.enable = true` poi rebuild + monitor X/Wayland)

## Come riprodurre

Su WSL Ubuntu / Linux con Nix:
```bash
git clone https://github.com/rguidotti-design/solem
cd solem
nix build .#vm --extra-experimental-features 'nix-command flakes'
./result/bin/run-solem-vm-vm
# login: gavio / gavio
```

Per desktop grafico (con UI Hyprland):
```bash
# Edita flake.nix per aggiungere:
#   solem.desktop.enable = true;
# Poi:
nix build .#vm
./result/bin/run-solem-vm-vm   # apre QEMU con display grafico
```
