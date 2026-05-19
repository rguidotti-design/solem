# ADR-004 — Supabase free tier + export script da subito

**Status**: Accettato
**Data**: 2026-05-17

## Contesto

GAVIO oggi usa Supabase cloud free tier (500MB DB + 50K Auth users, no carta). Direttiva utente "solo gratis" è rispettata (free tier non richiede pagamento). Ma esposizione lock-in: se Supabase chiude/cambia ToS, dati persi.

## Decisione

- **Step 0-1**: Supabase free tier resta default per DB GAVIO + Auth
- **Da OGGI**: script `backend/scripts/supabase-export.sh` che fa `pg_dump` settimanale + storage dei file Supabase Storage → backup locale in `/var/backups/solem/supabase/`
- **Step 2** (quando dati > 500MB o > 50K user): transizione a **Postgres self-host** + **Authentik** dentro SOLEM stesso
- Export script eseguito da systemd timer settimanale (`solem-supabase-backup.service`)
- Schema versionato in git (Supabase migrations + SOLEM migrations già esistenti)

## Conseguenze

**Positive**:
- Zero costi durante adozione
- Niente vendor lock-in: export rodato da subito → migrazione self-host indolore
- Disaster recovery: Supabase down ≠ dati persi

**Negative**:
- Doppio path di gestione DB Step 1 (Supabase cloud + SOLEM Postgres futuro)
- Schema migrations devono essere portabili (no Supabase-specific features)

## Implementazione

Modulo `solem-supabase-backup.nix` (TODO M1.2) con:
- timer settimanale `OnCalendar=weekly`
- env file `/etc/gavio/env` per credenziali Supabase
- output: `/var/backups/solem/supabase/dump-<timestamp>.sql.zst`
- retention 12 settimane (~3 mesi)
