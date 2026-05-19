# SOLEM — Primi 5 minuti dopo il boot

Cosa fare appena la finestra QEMU mostra il login prompt.

---

## 1. Login in console (finestra QEMU)

```
solem login: gavio
Password:    gavio
```

## 2. Cambia la password (importante)

```bash
passwd
# (digita gavio attuale, poi due volte la nuova)
```

## 3. Configura GAVIO env file

**Da host (PowerShell), in un nuovo terminale:**
```powershell
cd C:\Users\guido\Desktop\solem
.\scripts\setup-env.ps1
```

Lo script SSH-a nella VM, copia `/etc/gavio/env.example` → `/etc/gavio/env`,
apre vim per editarlo. Compila **almeno una** di queste:

```
GROQ_API_KEY=gsk_...               # gratis: console.groq.com
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_SERVICE_KEY=eyJ...
```

Salva con `:wq`. Lo script riavvia `gavio.service` da solo.

## 4. Verifica che GAVIO risponde

**Browser:** http://localhost:8000

**Curl da host:**
```powershell
curl http://localhost:8000/health
```

## 5. Vedi log in tempo reale

```powershell
.\scripts\logs.ps1            # log GAVIO
.\scripts\logs.ps1 ollama     # log Ollama
```

---

## Comandi utili (da WSL, dentro la cartella `solem/`)

| Comando | Cosa fa |
|---------|---------|
| `make help` | mostra tutti i target |
| `make ssh` | SSH nella VM |
| `make logs` | tail log GAVIO |
| `make status` | status servizi |
| `make restart-gavio` | restart GAVIO |
| `make health` | check `:8000/health` |

Da PowerShell senza Make:

| Script | Cosa fa |
|--------|---------|
| `.\scripts\ssh.ps1` | SSH nella VM |
| `.\scripts\logs.ps1 [servizio]` | tail log (default: gavio) |
| `.\scripts\setup-env.ps1` | wizard env file + restart |

---

## Spegnere la VM

**Pulito** (dentro VM):
```bash
sudo poweroff
```

**Forzato** (da finestra QEMU):
- Menu *Machine* → *Power Down*
- O chiudi semplicemente la finestra

---

## Troubleshooting flash

| Sintomo | Soluzione |
|---------|-----------|
| `gavio.service` failed | `make logs` per vedere stack trace; spesso manca env var |
| Niente risposta su :8000 | `make status` — è up? Firewall guest? |
| Browser timeout localhost:8000 | Controlla port forward in `nixos/hardware-vm.nix` |
| `/opt/gavio` vuoto nella VM | Shared folder 9p non montato — riavvia VM |
| Ollama lento al primo prompt | Modello in download la prima volta — `ollama pull llama3.2:3b` dentro VM |

Per troubleshoot esteso: [TESTING.md](TESTING.md).
