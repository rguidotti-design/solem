# ADR-006 — Constitutional layer triple-defense

**Status**: Accettato
**Data**: 2026-05-17

## Contesto

Prompt v4.0 sez. 4.11 chiede "Constitutional layer: regole dichiarative inviolabili" per GAVIO. Oggi GAVIO ha `safety.py` come enforcer interno. Decisione su dove vivono e come sono enforced.

## Decisione: triple-defense

### Layer 1 — Dichiarativo Nix (single source of truth)
- File `/etc/gavio/constitution.nix` generato da modulo NixOS `solem-constitution.nix`
- Regole versionate in flake → diff fra versioni leggibile in git
- Rollback con `nixos-rebuild --rollback` se nuove regole sono troppo restrittive
- Esempio:
  ```nix
  solem.constitution = {
    forbidden_actions = [
      { pattern = "rm -rf /home/.*"; reason = "Distruzione dati utente"; }
      { pattern = "shutdown -h"; reason = "Spegnimento sistema senza 2FA"; }
    ];
    require_two_factor = [ "filesystem.delete" "network.outbound.new_domain" ];
    require_user_confirm = [ "send_message" "execute_subprocess" ];
  };
  ```

### Layer 2 — SOLEM gateway (centralized enforcement)
- Ogni azione GAVIO → POST `/solem/constitution/check` PRIMA di esecuzione
- Endpoint legge `/etc/gavio/constitution.nix` (compilato a JSON al boot)
- Risposta: `{allowed: bool, reason: string, requires: ["confirm" | "2fa" | null]}`
- Audit log immutabile firmato ed25519 per ogni check

### Layer 3 — GAVIO internal enforcer (defense in depth)
- `safety.py` resta in GAVIO ma diventa **runtime enforcer locale**
- Verifica regole anche se SOLEM gateway è down
- Cache locale delle regole sincronizzata da SOLEM al boot

## Conseguenze

**Positive**:
- 3 layer = se uno cade, gli altri proteggono
- Regole dichiarative + versionate = governance chiara
- Rollback rapido di policy disastrose

**Negative**:
- Complessità: 3 path da mantenere allineati
- Latency extra ~5ms per check gateway (mitigato da cache lato GAVIO)

## Implementazione

- **M1.3** (Mese 3): definizione schema Nix `solem.constitution` + endpoint `/solem/constitution/check`
- **M2.5** (Mese 5-6): UI editor regole in dashboard tab Settings
- **M3.1** (Mese 7-8): firma ed25519 audit log
