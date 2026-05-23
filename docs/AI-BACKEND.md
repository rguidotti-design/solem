# SOLEM è un OS, non un'AI

SOLEM è un sistema operativo. **Niente di più, niente di meno**.

L'unica AI **pre-integrata** è **GAVIO**, perché è quella dell'autore. Ma SOLEM funziona con qualsiasi backend AI compatibile via una singola variabile d'ambiente.

## Architettura

```
┌──────────────────────────────────────────────────┐
│  SOLEM = OS (NixOS + 92 moduli + 60 API layer)   │
│                                                  │
│   ┌──────────────┐   ┌─────────────────────┐    │
│   │  capabilities│──▶│   /solem/ai/route   │────┼──▶ GAVIO_API_URL
│   │  (vision,    │   │  (thin proxy HTTP)   │    │
│   │  summarizer, │   └─────────────────────┘    │
│   │  ai_shell,   │                              │
│   │  rag, ...)   │                              │
│   └──────────────┘                              │
└──────────────────────────────────────────────────┘
                                  ▲
                                  │  HTTP
                                  │
        ┌─────────────────────────┴─────┐
        │                               │
   ┌────▼─────┐                    ┌────▼─────┐
   │  GAVIO   │  default           │ ALTRO    │  opt-in
   │  :8000   │  pre-installato    │ BACKEND  │  cambia env var
   └──────────┘                    └──────────┘
```

## Default: GAVIO

SOLEM al primo boot avvia `gavio.service` systemd. GAVIO è in `/opt/gavio/` (montato via `solem-gavio-storage.nix`).

```nix
# default in configuration.nix
services.gavio.enable = true;
```

L'env var `GAVIO_API_URL` punta a `http://127.0.0.1:8000` (GAVIO locale).

## Sostituire l'AI: 1 env var

SOLEM **non si accorge** di chi sta parlando dietro l'endpoint, basta che parli il protocollo `/api/chat` (compat OpenAI o GAVIO).

### Opzione A — Ollama puro

```bash
sudo systemctl edit solem-api
```

Aggiungi:
```ini
[Service]
Environment=GAVIO_API_URL=http://127.0.0.1:11434
Environment=GAVIO_CHAT_ENDPOINT=/v1/chat/completions
```

```bash
sudo systemctl restart solem-api
# Verifica
solem ai "test"
```

### Opzione B — LM Studio

```ini
Environment=GAVIO_API_URL=http://127.0.0.1:1234
Environment=GAVIO_CHAT_ENDPOINT=/v1/chat/completions
```

### Opzione C — llama.cpp server

```ini
Environment=GAVIO_API_URL=http://127.0.0.1:8080
Environment=GAVIO_CHAT_ENDPOINT=/v1/chat/completions
```

### Opzione D — Claude API (paid, NON default)

Non rispetta `feedback_solem_only_free.md`. Ma se l'utente vuole:

```ini
Environment=GAVIO_API_URL=https://api.anthropic.com/v1
Environment=GAVIO_CHAT_ENDPOINT=/messages
Environment=GAVIO_API_KEY=sk-ant-...
```

(richiede patch a `ai_router.py` per gestire l'header `x-api-key`, non incluso di default).

### Opzione E — OpenAI compat (paid, NON default)

```ini
Environment=GAVIO_API_URL=https://api.openai.com
Environment=GAVIO_CHAT_ENDPOINT=/v1/chat/completions
Environment=GAVIO_API_KEY=sk-...
```

## Disabilitare AI completamente

SOLEM funziona senza alcuna AI. Le capabilities che richiedono AI restituiscono `503` con messaggio chiaro. Tutto il resto (cluster, network, backup, install app, focus mode, ecc.) funziona ugualmente.

```bash
sudo systemctl stop gavio
sudo systemctl disable gavio
```

`solem ai "test"` → `503 gavio_offline_no_fallback`. Ma `solem status`, `solem backup`, `solem-app install …` → continuano a funzionare.

## Cosa NON è SOLEM

- ❌ SOLEM non parla
- ❌ SOLEM non ricorda
- ❌ SOLEM non ragiona
- ❌ SOLEM non ha un suo modello LLM
- ❌ SOLEM non sceglie quale modello usare (lo fa GAVIO o il backend che hai configurato)

## Cosa È SOLEM

- ✅ Un OS NixOS riproducibile, 92 moduli opt-in
- ✅ Un'API REST con 262 endpoint per "fare cose" (cluster, mesh, backup, focus, install app, …)
- ✅ Multi-arch (x86_64 + aarch64) + multi-form-factor (workstation/edge/mobile/glass)
- ✅ 0 € — 100% FOSS
- ✅ Pre-integrato con GAVIO ma agnostico

## Naming convenzionale (per evitare confusione)

| Nome modulo | Significato |
|---|---|
| `solem-ai-freedom` | "Libertà di esecuzione PER l'AI" (sudo NOPASSWD selettivo per gavio user) — NON "SOLEM è AI" |
| `solem-ai-hardware-tuning` | "Tuning hardware PER far girare un'AI" (HugePages, CPU pinning Ollama, GPU passthrough) — NON "SOLEM è AI" |
| `solem-api` | API REST dell'OS, non dell'AI |
| `/solem/ai/route` | Thin proxy verso l'AI esterna pre-integrata (GAVIO) |
| `solem-cluster` | Distributed compute per workload (anche AI) — niente di AI proprio |
| Badge waybar "SOLEM" | Nome OS, non AI. GAVIO ha logo "G" separato. |

L'AI vive **fuori** da SOLEM. SOLEM **la ospita** al massimo possibile.
