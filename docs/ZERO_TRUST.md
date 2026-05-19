# SOLEM Zero-Trust

> Nessuna rete è fidata. Anche la mesh WireGuard interna è trattata come
> Internet pubblico: ogni richiesta autenticata, autorizzata, loggata.

---

## Principi Zero-Trust applicati a SOLEM

1. **Verify explicitly** — ogni richiesta API attraversa mTLS + token + policy
2. **Least privilege** — ogni AI / device ha SOLO le capabilities di cui ha bisogno
3. **Assume breach** — audit log su tutto, rotate cert frequentemente
4. **Identity is the new perimeter** — chi sei conta più di dove sei
5. **Continuous validation** — token short-lived (≤15 min), revoca real-time

---

## Architettura

```
client (phone)
    │  mTLS connection (client cert firmato da CA SOLEM)
    ▼
┌─────────────────────────────────────────┐
│ Caddy :8443                             │
│  ├─ verify client cert vs CA            │
│  ├─ extract identity from cert CN       │
│  ├─ policy check (allow/deny)           │
│  ├─ audit log → /var/log/solem/audit.jsonl
│  └─ reverse_proxy ↓                     │
└─────────────────────────────────────────┘
    │
    ├─ /api/gavio/*  → http://127.0.0.1:8000
    └─ /api/solem/*  → http://127.0.0.1:8001
```

Backend GAVIO e SOLEM API ascoltano solo su `127.0.0.1`. **L'unica porta
esposta sulla rete è Caddy:8443**, che richiede mTLS.

---

## Attivazione

```nix
solem.zeroTrust = {
  enable = true;
  hostname = "solem.local";
  port = 8443;
  upstreams = {
    gavio = "http://127.0.0.1:8000";
    solem = "http://127.0.0.1:8001";
  };
};
```

Al primo boot, `solem-ca-bootstrap.service` genera:

- `/var/lib/solem-ca/ca.key` (RSA 4096, valida 10 anni) — **MAI esposta**
- `/var/lib/solem-ca/ca.crt` (cert pubblico CA)
- `/var/lib/solem-ca/server.key` (server cert per Caddy, RSA 2048)
- `/var/lib/solem-ca/server.crt` (valido 365 giorni, auto-renew)

---

## Onboarding device (in combinazione con mesh)

1. Pairing via PIN (vedi [MESH.md](MESH.md)) → device ottiene config WireGuard
2. Durante confirm, device invia anche CSR per cert mTLS
3. Coordinator firma CSR con CA SOLEM → restituisce cert client
4. Device usa quel cert per ogni richiesta a `https://solem.local:8443`

Risultato: ogni device ha un **cert unico, revocabile, scadente**.

---

## Audit log

Ogni richiesta passata da Caddy logga in `/var/log/solem/audit.jsonl`:

```json
{
  "ts": "2026-05-17T19:30:00Z",
  "request": {
    "remote_ip": "10.42.0.10",
    "client_cert_cn": "phone-ruben",
    "method": "POST",
    "uri": "/api/gavio/chat"
  },
  "status": 200,
  "duration_ms": 245
}
```

Roll automatico ogni 100 MB, retention 10 file.

L'AI può leggere `/var/log/solem/audit.jsonl` per:
- Capire pattern d'uso utente
- Rilevare anomalie ("PIN usato da IP sconosciuto", "richieste fuori dal solito")
- Generare briefing privacy ("oggi GAVIO ha chiamato Supabase 47 volte per te")

---

## Confronto con i big

| Aspetto | Tailscale | Cloudflare ZT | **SOLEM** |
|---------|-----------|---------------|-----------|
| Coordinator self-hosted | No (Headscale OSS) | No | **Sì** |
| CA self-hosted | Sì | No | **Sì** |
| Audit log locale | Limitato | Cloud | **Locale-first** |
| AI-aware policy | No | No | **Sì (Step 2+)** |
| Costo | Free → $5/user | $7/user | **0€** (self-host) |
| Data sovereignty | Mixed | Cloud | **Tuoi server** |

---

## Stato implementazione

| Componente | Step 0 | Step target |
|------------|--------|-------------|
| Modulo NixOS `solem-zero-trust.nix` | ✅ scaffold | — |
| Bootstrap CA automatico | ✅ | — |
| Caddy mTLS reverse proxy | ✅ | — |
| Firma CSR client al pairing | ❌ stub | Step 1 |
| Policy engine (chi-può-fare-cosa) | ❌ | Step 2 (OPA o custom) |
| Token short-lived AI-to-AI | ❌ | Step 2 |
| Audit log → SIEM esterno | ❌ | Step 3+ (Grafana Loki) |
| Cert revocation list (CRL) | ❌ | Step 2 |

---

## Trade-off con "AI Freedom"

[AI_FREEDOM.md](AI_FREEDOM.md) dice "l'AI ha sudo NOPASSWD, polkit aperto".
Zero-trust **non contraddice**: la libertà dell'AI è **sulla macchina locale**.
La rete attorno è sigillata. L'AI può fare di tutto sul suo host, ma:
- Ogni chiamata di rete attraversa Caddy → loggata
- Ogni device esterno deve essere paired e autenticato
- Niente dispositivo casuale può "parlare" con la tua SOLEM
