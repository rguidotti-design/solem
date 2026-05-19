# SOLEM — systemd Hardening (Milestone 1.1)

**Riferimento**: Prompt Master v4.0 sez. 1.2 — "Ogni unit con: NoNewPrivileges, ProtectSystem=strict, PrivateDevices, ProtectKernelTunables, MemoryDenyWriteExecute dove applicabile."

**Filosofia**: bilanciare hardening contro attacchi esterni con **AI freedom interna** (vedi [AI_FREEDOM.md](AI_FREEDOM.md)). Hardening protegge il sistema DAL VETTORE servizio, non limita le azioni intenzionali dell'AI quando passa per `sudo`/`polkit`.

---

## Livelli applicati

| Servizio | Livello | NoNewPrivileges | PrivateDevices | MemoryDenyWriteExecute | Motivazione |
|----------|---------|-----------------|----------------|------------------------|-------------|
| `solem-keep.service` | **STRICT** | ✅ true | ✅ true | ✅ true | Solo polla systemctl + POST localhost. Niente sudo, niente devices, niente JIT. |
| `solem-api.service` | **MEDIUM** | ❌ false | ❌ false | ❌ false | Esegue `sudo nixos-rebuild` via `/system/rebuild`. Legge `/proc/*` per `/system/info`. Python uvloop JIT. |
| `gavio.service` | **MEDIUM** | ❌ false | ❌ false | ❌ false | Coerente con `ai-freedom.nix`: GAVIO può `sudo`, accedere a `/dev/uinput` per computer-use, JIT Python. |

---

## Flag applicati universalmente (tutti i 3 servizi)

### Filesystem
| Flag | Effetto | Threat mitigato |
|------|---------|-----------------|
| `ProtectSystem=strict` | `/usr` `/boot` `/etc` read-only | Tampering binaries/config |
| `ProtectHome=tmpfs` | `/home` `/root` `/run/user` → tmpfs vuoto | Exfiltrazione dati altri utenti |
| `PrivateTmp=true` | `/tmp` `/var/tmp` privati per il servizio | TOCTOU race condition con altri processi |
| `ReadWritePaths=[...]` | Path scrivibili esplicitamente whitelist | Scrittura arbitraria filesystem |
| `ReadOnlyPaths=[...]` | Path read-only espliciti (es. `/etc/gavio` per gavio.service) | Modifica accidentale config secret |

### Kernel
| Flag | Effetto | Threat mitigato |
|------|---------|-----------------|
| `ProtectKernelTunables=true` | `/proc/sys` read-only | Modifica sysctl da exploit |
| `ProtectKernelModules=true` | No `modprobe`/`rmmod` | Caricamento modulo malevolo |
| `ProtectKernelLogs=true` | No accesso `syslog` kernel | Lettura dmesg per info leak |
| `ProtectControlGroups=true` | cgroups read-only | Escape cgroup limit |
| `ProtectClock=true` | No `settimeofday()` | Manipolazione tempo per replay attack |
| `ProtectHostname=true` | No `sethostname()` | Spoofing identità nodo |

### Process
| Flag | Effetto | Threat mitigato |
|------|---------|-----------------|
| `LockPersonality=true` | No `personality()` syscall | Bypass ASLR via personality |
| `RestrictRealtime=true` | No SCHED_FIFO/SCHED_RR | DoS via realtime priority |
| `RestrictSUIDSGID=true` | No creazione file SUID/SGID | Privilege escalation persistente |

### Syscall
| Flag | Effetto | Threat mitigato |
|------|---------|-----------------|
| `SystemCallFilter=@system-service ~@cpu-emulation ~@obsolete` | Whitelist + blacklist syscall | Exploit kernel via syscall obscure |
| `SystemCallArchitectures=native` | Solo syscall arch nativa | Cross-arch syscall (x86 su ARM) |
| `SystemCallErrorNumber=EPERM` | Syscall bloccate ritornano EPERM | Coerenza errori (no SIGSYS) |

### Network
| Flag | Effetto | Threat mitigato |
|------|---------|-----------------|
| `RestrictAddressFamilies=[AF_UNIX AF_INET AF_INET6]` | No AF_NETLINK/AF_PACKET/raw sockets | Raw socket exploitation |
| `IPAddressAllow=[127.0.0.1 ::1]` (solo solem-keep) | Outbound solo localhost | Esfiltrazione dati a C2 esterno |

---

## Flag NON applicati (e perché)

### `NoNewPrivileges=true`
- ✅ solem-keep (puro polling)
- ❌ solem-api: blocca `sudo nixos-rebuild` invocato da `/system/rebuild`
- ❌ gavio: blocca `sudo` da Python (GAVIO `system_control.py` ne ha bisogno)

### `PrivateDevices=true`
- ✅ solem-keep
- ❌ solem-api: `/system/info` legge `/proc/cpuinfo` etc.
- ❌ gavio: computer-use opt-in usa `/dev/uinput`, `/dev/video*`

### `MemoryDenyWriteExecute=true`
- ✅ solem-keep (Python stdlib only, no JIT)
- ❌ solem-api: uvloop usa LuaJIT-style optimization
- ❌ gavio: `faster-whisper`, `httpx` (anyio backends), Ollama bindings usano memoria writable+executable

### `RestrictNamespaces=true`
- ✅ solem-keep
- ❌ solem-api: sudo subprocess può fare namespace
- ❌ gavio: Docker sandbox opt-in richiede namespace creation

### `ProtectProc=invisible`
- ✅ solem-keep
- ❌ solem-api: `/system/info` legge `/proc/uptime`, `/proc/meminfo`
- ❌ gavio: nodi system ispezionano processi

---

## Verifica score hardening

`systemd-analyze security <servizio>` ritorna score 0-10 (10 = peggio, 0 = perfetto).

Target SOLEM Step 1:
- `solem-keep.service` → **≤ 2.0** (strict, raggiungibile)
- `solem-api.service` → **≤ 4.0** (medium)
- `gavio.service` → **≤ 5.0** (medium con eccezioni AI-freedom giustificate)

Check automatico via `solem-doctor` (sezione `[hardening]` aggiunta in M1.1).

---

## Coerenza con AI Freedom

L'utente `gavio` ha:
- `sudo NOPASSWD` per qualsiasi comando (via `ai-freedom.nix`)
- Polkit aperto per azioni privilegiate D-Bus
- Gruppi: wheel/docker/video/audio/dialout/input/plugdev/networkmanager

**Questo NON è in conflitto con hardening systemd** perché:
1. **Hardening protegge da attacchi via VETTORE servizio**: se qualcuno trova exploit RCE in GAVIO Python, l'hardening limita il danno (no scrittura a `/usr`, no kernel modules, ecc.)
2. **AI freedom permette azioni INTENZIONALI dell'utente/AI**: quando GAVIO decide di fare `sudo nixos-rebuild`, passa per il canale sudo legittimo (non syscall raw bloccate)
3. **Defense in depth**: 3 layer indipendenti — kernel hardening + systemd unit isolation + audit log

I tre layer si rinforzano, non si contraddicono.

---

## Rollback

Se hardening rompe qualcosa (es. un servizio non parte):

```bash
# Identifica il flag colpevole
systemd-analyze security <service>
journalctl -u <service> | grep -i "denied\|permission\|EPERM"

# Disabilita temporaneo singolo flag (override in /etc/nixos/...)
systemctl edit <service>
# In editor: aggiungi [Service] e ServiceName=false

# Oppure rollback intero
sudo nixos-rebuild --rollback
```

---

## Roadmap hardening

| Step | Cosa aggiungere |
|------|-----------------|
| M1.1 ✅ | Flag base sui 3 servizi core (questo doc) |
| M1.2 | Hardening su `solem-update.service`, `solem-backup.service` |
| M2.x | Estendere a `caddy.service` (zero-trust), `ollama.service` |
| M3.x | AppArmor profili custom per L7 extensions (sandbox terze parti) |
| M5.x | KSPP kernel cmdline params completi + lockdown=integrity |
