# SOLEM — Costi

> **SOLEM è 100% gratuito. Zero abbonamenti. Zero costi obbligatori. Mai.**

Direttiva del founder Ruben Guidotti: **nessun sistema a pagamento**, nemmeno opzionale, nei file SOLEM. Self-host gratis è l'unico modello supportato.

---

## Software stack — tutto open source

| Componente | Licenza | Costo |
|------------|---------|-------|
| NixOS | MIT | 🆓 |
| Python 3.12 | PSF | 🆓 |
| FastAPI / Pydantic / httpx | MIT/BSD | 🆓 |
| SQLite | Public domain | 🆓 |
| Ollama (LLM locale) | MIT | 🆓 |
| Docker / Podman | Apache 2 | 🆓 self-host |
| WireGuard | GPL2 | 🆓 |
| Caddy (mTLS proxy) | Apache 2 | 🆓 |
| Hyprland (compositor) | BSD-3 | 🆓 |
| Firefox / Chromium | MPL / BSD | 🆓 |
| Plymouth (boot splash) | GPL2 | 🆓 |
| Pipewire (audio) | MIT | 🆓 |
| BlueZ (Bluetooth) | GPL2 | 🆓 |
| Jupyter / NumPy / Pandas / sklearn | BSD | 🆓 |
| OpenTofu (Terraform fork) | MPL | 🆓 |
| kubectl / Helm / k9s | Apache 2 | 🆓 |
| Blender / GIMP / Inkscape | GPL | 🆓 |
| Tutti i moduli NixOS | MIT | 🆓 |

**Conclusione**: l'intero stack è open source, riproducibile, audit-able, self-host gratis per sempre.

---

## Servizi esterni — solo free tier sufficienti

| Servizio | Free tier che usiamo | Note |
|----------|----------------------|------|
| **Supabase** (opzionale, solo Step 2+) | 500MB DB, 1GB storage, 50K Auth users, 2GB bandwidth/mese | Self-host alternativa: Postgres su SOLEM stesso |
| **Ollama** (LLM locale) | Illimitato, gira sul tuo hardware | Default backend GAVIO |
| **Groq** (LLM cloud veloce, free tier) | ~14K richieste/giorno modelli Llama/Mixtral | Fallback opzionale se Ollama troppo lento |
| **Let's Encrypt** (HTTPS) | Illimitato | Per cert pubblici se esporti SOLEM |
| **GitHub** (hosting code + CI Actions) | Repo illimitati + 2000 min/mese CI privati | Per backup repo SOLEM |
| **mDNS `.local`** | Gratuito, zero-config | Naming device LAN |
| **WireGuard self-host** | Gratuito | Mesh tra device |

**Nessun servizio cloud a pagamento è usato di default né suggerito.**

---

## Hardware — una tantum, mai obbligato

| Hardware | Costo una tantum | Quando |
|----------|------------------|--------|
| **VM su PC esistente** | 🆓 | Step 0 (oggi) |
| **Beelink Mini S12 Pro** o equivalente | ~250-300€ (acquisto **tuo**, non da noi) | Step 1 (estate 2026) — opzionale |
| **NVIDIA Jetson Orin Nano** o equivalente | ~500€ (acquisto **tuo**) | Step 3+ — opzionale per LLM locale veloce |
| **Raspberry Pi 5** o equivalente | ~80€ (acquisto **tuo**) | Step 3+ — edge IoT bridge, opzionale |

SOLEM **non vende hardware**. Acquisti da fornitori tuoi quando vuoi. Tutto auto-host.

---

## Backup

| Strategia | Costo |
|-----------|-------|
| Backup locale automatico (`solem-backup` timer giornaliero in `/var/backups/solem/`) | 🆓 (modulo già attivo Step 0) |
| Backup verso altro nodo SOLEM (mesh peer) via `rsync`/`restic` | 🆓 (richiede 2° device) |
| Backup verso disco USB esterno locale | 🆓 (richiede 1 USB stick) |
| Backup verso server casa di amici/famiglia (mesh) | 🆓 |

Niente backup cloud paganti consigliati.

---

## Budget realistico

| Step | Costo totale stimato |
|------|----------------------|
| **Step 0** (oggi, VM test) | **0€** |
| **Step 1** (Beelink bare-metal) | **0€/mese** + 250€ una tantum solo se compri Beelink |
| **Step 2+** | **0€/mese** sempre |

---

## Cose che evitiamo per principio

- ❌ **Tracking utente** — nessuna telemetria silenziosa
- ❌ **Vendor lock-in cloud** — ogni feature ha sempre modalità self-host
- ❌ **App store con revenue share** — Extensions L7 sono libere e gratuite
- ❌ **Subscriptions** — niente abbonamenti, mai
- ❌ **Dati venduti a terzi** — i tuoi dati restano tuoi
- ❌ **Managed services paganti** — sempre self-host
- ❌ **Hardware proprietario** — usi quello che vuoi tu
- ❌ **API LLM cloud paganti suggerite** — solo Ollama locale + free tier Groq

---

## Configurazione zero-costi (default Step 0)

In `configuration.nix`:
```nix
solem.profile = "developer";    # niente creator/desktop pesanti
solem.creator.ai.enable = false; # solo Ollama locale
```

In `/etc/gavio/env`:
```
LLM_BACKEND=auto
OLLAMA_HOST=http://127.0.0.1:11434
OLLAMA_MODEL=llama3.2:3b
# (nessuna API key cloud richiesta)
```

GAVIO funziona 100% in locale con Ollama. Groq solo se vuoi velocità extra (free tier comunque).

---

## Trasparenza

Questo file viene aggiornato a ogni step con i costi REALI.
Se un modulo SOLEM introduce un costo nascosto, è un bug — apri issue.
