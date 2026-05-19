# ADR-005 — Tailscale Funnel RESTA, no migrazione a WireGuard+Caddy+LE

**Status**: Accettato (decisione opposta a default precedente)
**Data**: 2026-05-17

## Contesto

GAVIO oggi esposto via **Tailscale Funnel** su `gavio.tail72feef.ts.net`. Il default proposto nell'audit GAVIO era migrazione a WireGuard + Caddy + Let's Encrypt Step 1. L'utente ha indicato: **tieni Tailscale**.

## Motivazioni utente

- Tailscale Funnel è **gratis** (free tier abbondante)
- Gestisce **cert TLS automaticamente** (no setup Let's Encrypt)
- Mesh privato già funzionante
- Migrazione WG+Caddy+LE richiede:
  - dominio pubblico (~10-15€/anno → **VIOLA direttiva 100% gratis**)
  - DNS config
  - cert renewal automation
  - firewall hardening per port 80/443 pubblici
- **4-8h lavoro per zero beneficio funzionale** rispetto a Tailscale

## Decisione

- **Tailscale Funnel resta** in produzione (oggi + Step 1+)
- **SOLEM mesh WireGuard** (`solem-mesh.nix`) resta come opzione opt-in **per device interni** (mesh tra Beelink/laptop/PinePhone)
- Tailscale Funnel = "esposizione esterna" (per accesso da rete non-mesh)
- WireGuard SOLEM = "mesh interno" (tra device dell'utente)

I due coesistono. Non si sostituiscono.

## Quando rivedere

Migrazione a WG+Caddy+LE diventa sensata SE:
1. Tailscale alza prezzi (oggi 100% gratis fino a 3 user, basta)
2. Vuoi mostrare GAVIO con dominio brand-able (es. `gavio.solem.<tuo-dominio>`)
3. Tailscale chiude o cambia ToS

Finché non succede, **tieni Tailscale**.

## Conseguenze

**Positive**:
- Zero lavoro extra Step 1
- Tailscale Funnel più affidabile di Caddy self-managed
- Direttiva "100% gratis" rispettata (Tailscale free tier non costa)

**Negative**:
- Lock-in lieve a Tailscale (mitigato: protocollo WireGuard sotto, export trivial)
- Nome host `*.tail72feef.ts.net` non brandable (ma OK per founder)

## Aggiornamento file impattati

- `ROADMAP.md` Step 1 → rimuovo "Reverse proxy Caddy con Let's Encrypt"
- `docs/INSTALL.md` → rimuovo riferimento a transizione WG+LE
- `GAVIO_INTEGRATION_AUDIT.md` → aggiorno § 2.3 (conflitto risolto)
