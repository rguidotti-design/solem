# SOLEM — Cosa manca per essere operativo (prima del test hardware)

> Aggiornato 2026-05-24. Versione 1. Audit onesto del lavoro restante
> per portare SOLEM da "codice scritto" a "OS che gira sul Beelink".

---

## Stato attuale (post commit 67ece07 + fix CI)

- 140 moduli SOLEM scritti
- 8 moduli home-manager
- 8 VM tests
- CI matrix x86_64 (lint + flake-check + build vm/iso + test)
- Cachix `solem.cachix.org` configurato (free 10 GB)
- 2 nixosConfigurations: `solem-vm` (minimal CI-friendly) + `solem-vm-full`

---

## Lista per essere operativo PRIMA del test hardware

### 🔴 P0 — Bloccanti per `nix build .#vm` riuscito

| # | Cosa | Stato | Effort |
|---|------|------:|-------:|
| 1 | Tutti i 7 job CI passano verdi su VM minimal | 🔴 In corso | 1-3 h |
| 2 | `nix build .#vm-full` passa (config completa) | 🔴 Da fare | 4-8 h |
| 3 | `nix build .#iso` passa | 🔴 Da fare | 2-4 h |
| 4 | Lock file `flake.lock` committato e aggiornato | 🔴 Da fare | 5 min |
| 5 | Cachix push attivo (token configurato) | ✅ Pronto | – |

**Bloccanti tipici da fixare iterativamente**:
- Pacchetti che non esistono in `nixpkgs-24.11` (es. `bruno`, `simplex-chat-desktop`, `cinny-desktop`, `kdePackages.kwallet-pam`, `super-slicer`)
- Opzioni servizi cambiate (`services.joplin-server`, `services.metabase`)
- `lib.mkForce` mancanti dove ci sono conflitti tra moduli
- Permessi UDP/TCP duplicati (modulo X apre :8080 e modulo Y idem)

**Strategia**: ogni CI run fallita → log Nix dice **esattamente** quale modulo. Fix di 5-30 minuti per ognuno.

### 🟡 P1 — Bloccanti per "first-boot funzionante"

| # | Cosa | Stato | Effort |
|---|------|------:|-------:|
| 6 | VM boota fino a getty (greeter testuale) | 🔴 Mai testato | 1 h |
| 7 | Login `gavio:gavio` funziona | 🔴 Mai testato | 30 min |
| 8 | `solem` CLI risponde a `--help` | 🔴 Mai testato | 30 min |
| 9 | `solem-welcome` parte e finisce | 🔴 Mai testato | 1 h |
| 10 | Hyprland avvia (solo se `solem-vm-full` con desktop) | 🔴 Mai testato | 2-4 h |
| 11 | GAVIO stub risponde `/health` | 🟡 Stub aggiunto | 1 h |
| 12 | `solem-doctor` non crasha | 🔴 Mai testato | 30 min |
| 13 | Update da `solem update apply` funziona | 🔴 Mai testato | 2 h |

### 🟢 P2 — Polish per "esperienza decente"

| # | Cosa | Stato | Effort |
|---|------|------:|-------:|
| 14 | flake.lock con hash di tutti gli input | 🔴 | 5 min |
| 15 | `nix flake show` ordinato e leggibile | ✅ | – |
| 16 | README.md aggiornato con quick-start `nix run .#vm` | 🟡 | 30 min |
| 17 | INSTALL.md con istruzioni Beelink Step-by-step | 🟡 | 1 h |
| 18 | Calamares branding navy/gold visibile (screenshot) | 🟡 Solo testo | 2 h |
| 19 | `nix fmt` applicato a tutti i `.nix` | 🔴 | 5 min |
| 20 | `statix check` zero warning | 🔴 | 1-2 h |
| 21 | `deadnix .` zero dead code | 🔴 | 30 min |

### 🔵 P3 — Per build full e robustezza

| # | Cosa | Stato | Effort |
|---|------|------:|-------:|
| 22 | `solem-vm-full` builda (con tutti i 140 moduli) | 🔴 Probabilmente fallisce | 4-8 h |
| 23 | GAVIO impacchettato vero (no stub) | 🟡 Stub | 4 h |
| 24 | Test boot tempo < 30 secondi | 🔴 Mai misurato | 2 h |
| 25 | Test memoria RAM idle < 1 GB | 🔴 Mai misurato | 2 h |
| 26 | aarch64 cross-build (Raspberry/Jetson) passa | 🔴 | 4-8 h |
| 27 | Test multi-utente (family-sharing) | 🔴 | 1 h |
| 28 | Test Nextcloud accessibile da browser | 🔴 | 2 h |
| 29 | Test fingerprint enroll/auth (richiede hardware) | ⏸ Differito P7 | – |

---

## Roadmap suggerita (questa settimana)

### Day 1-2 (oggi+domani): far passare CI minimal
1. Aspetta il run CI corrente — leggi i log dei 2 job falliti
2. Fixa errori uno-a-uno (sono package names quasi sempre, soluzione veloce)
3. Re-run finché matrix `build-profiles` è verde
4. **Target**: `nix build .#vm` riuscito in cloud

### Day 3-4: VM tests verdi
1. Quando build profili è verde, lancia `vm-tests` matrix
2. 8 test girano in ~ 5 minuti ciascuno; se uno fallisce, log dice quale modulo
3. Fixa moduli con bug logici
4. **Target**: 8/8 VM tests verdi

### Day 5: VM gira davvero
1. Da WSL2 locale o cloud VM: `nix run .#vm`
2. Verifica boot + login + `solem help`
3. Profila tempi (boot, idle, primo `solem ai`)
4. **Target**: video di 30 secondi che mostra SOLEM bootare

### Day 6-7: ISO + full config
1. `nix build .#iso` → ISO bootabile via QEMU
2. Calamares parte
3. Spegni VM, riavvia da ISO appena costruita, finta installazione su /tmp
4. **Target**: video di 2 minuti — boot ISO, Calamares branded, installazione

### Day 8+: full config (solem-vm-full)
1. `nix build .#nixosConfigurations.solem-vm-full.config.system.build.vm`
2. Probabilmente fallisce su 3-5 moduli "ambiziosi" (immich + nextcloud + radicale + paperless tutti insieme)
3. Fix iterativi
4. **Target**: VM con desktop completo + GAVIO stub running

---

## Cosa fa la CI quando è verde

- Ogni `git push` → 30 minuti dopo, tutti i binari sono su Cachix
- Chiunque cloni il repo: `nix run .#vm` → scarica binari (5-15 min), niente compilazione
- Pull request → blocco automatico se introduce regressioni
- Release: `git tag v0.x.y` → ISO generata + caricata su GitHub Releases (workflow `release.yml`)

---

## Cosa NON fa la CI

- Test su hardware fisico (P7, differito)
- Test interattivi GUI (richiede X server in CI, lento e fragile)
- Benchmark performance (separato in workflow `bench.yml` da creare)
- Test mobile (PinePhone), edge ARM (richiede QEMU emulation lenta)

---

## Come monitorare progressi

```bash
# Da terminale (richiede gh CLI installato)
gh run watch                                         # ultimo run live
gh run list --workflow=build.yml --limit=5           # ultimi 5 build
gh run view <ID> --log-failed                        # log job falliti

# Da browser
https://github.com/rguidotti-design/solem/actions    # tutti i workflow
https://app.cachix.org/cache/solem                   # stato cache
```

---

## Take-away

**SOLEM oggi**: codice esiste, struttura solida, CI strutturata.
**SOLEM tra 1 settimana di lavoro a tempo pieno**: VM boota, ISO bootable, test verdi.
**SOLEM tra 2 settimane**: utente non-tecnico può scaricare ISO, bootare USB, installare con Calamares.
**SOLEM tra 4 settimane** (con P7 hardware): produzione su Beelink + smartphone+laptop pair.

Tutto questo a **costo 0 €**.
