# ADR-008 — GAVIO sul Beelink come single source of truth, portatile client mesh

**Status**: Accettato
**Data**: 2026-05-17

## Contesto

Step 1 introduce Beelink mini-PC bare-metal. Decisione: dove gira GAVIO autoritativo? Sul portatile attuale (sempre acceso quando lavori) o Beelink (sempre acceso H24)?

## Decisione

- **Beelink = single source of truth GAVIO**
  - Sempre acceso → GAVIO sempre raggiungibile da qualsiasi device
  - DB GAVIO (Supabase free tier o futuro Postgres self-host) accessibile dal Beelink
  - Memoria/wiki/state persistente sul Beelink
  - `gavio.service` enabled by default sul Beelink, **disabled** sul portatile
- **Portatile = client mesh**
  - Solo: client web/CLI (`solem` CLI + browser)
  - Script di build/test/dev (modifica codice GAVIO localmente, sync via Git o 9p mount)
  - No DB locale (no fork data)
- **Sync codice**: portatile pushy su Git → Beelink pulla via webhook o cron
- **Mesh WireGuard** (`solem-mesh.nix`) tra portatile e Beelink per accesso LAN privato

## Conseguenze

**Positive**:
- Un solo posto dove cercare lo stato GAVIO ("dov'è la memoria?" → "sul Beelink")
- Portatile risparmia batteria/risorse (GAVIO non gira lì)
- Multi-device dell'utente accedono allo stesso GAVIO
- Backup centralizzato sul Beelink

**Negative**:
- Beelink diventa SPOF (single point of failure) — mitigato da:
  - `solem-backup.nix` snapshot quotidiano locale
  - Snapshot replicato verso secondo nodo mesh (Step 2+, opt-in)
- Senza connessione mesh → portatile offline rispetto a GAVIO

## Implementazione

- **Step 1** (M1.x): durante install Beelink, GAVIO migrato dal portatile (export dati + import)
- Modulo `solem-profile = "server"` sul Beelink abilita GAVIO automaticamente
- Modulo `solem-profile = "developer"` su portatile disabilita `gavio.service` (`services.gavio.enable = false`)
- Client CLI `solem` + browser su portatile puntano a `http://<beelink-ip>:8000` via mesh WireGuard
