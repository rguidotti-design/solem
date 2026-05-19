# Contribuire a SOLEM

Grazie per voler contribuire. SOLEM è un progetto a sé (non azienda) — ogni PR è benvenuta se rispetta la filosofia.

---

## Filosofia (non negoziabile)

Vedi spec founder + i **7 principi**:
1. Una sola entità, molte finestre
2. La leva è orientata, non cieca
3. Adattivo, mai prescrittivo
4. Vibe e precisione convivono
5. **Collaborazione aperta, fondamenta sigillate** ← qui le PR
6. Indipendenza, non isolamento
7. Costruttore-friendly per natura

**PR accettate**: nuove capability, extension L7, bridge L6, miglioramenti UI, fix bug, performance, test, documentazione.

**PR NON accettate**:
- Telemetria/tracking silenzioso
- Lock-in cloud forzato
- Dipendenze proprietarie obbligatorie
- Emoji nell'UI (rispetta spec branding)
- Rimozione di feature self-host

---

## Setup dev

```bash
# Clona
git clone https://github.com/<user>/solem
cd solem

# WSL2 + Nix + flakes (vedi docs/TESTING.md)
nix develop                  # apre shell con tool

# Test backend Python
cd backend
pytest -v

# Lint
ruff check solem_api/ tests/
ruff format solem_api/ tests/

# Eval NixOS senza buildare
nix eval .#nixosConfigurations.solem-vm.config.system.build.vm.drvPath

# Lancia VM
nix run .#vm
```

---

## Stile codice

### Python (backend)
- **Python 3.12+** con type hints SEMPRE
- **Pydantic v2** per modelli dati
- **async/await** per tutto I/O
- **Docstring Google** sui pubblici
- **ruff** lint + format
- **pytest** test, coverage > 70% per nuovi moduli
- **structlog** per log strutturati (Step 2+)

### Nix
- Moduli in `nixos/modules/solem-<feature>.nix`
- Naming: lowercase + dash, `solem.<feature>.<option>`
- Sempre `lib.mkEnableOption "..."` per opt-in
- Commenti in italiano OK per filosofia, codice in inglese
- `lib.mkIf cfg.enable { ... }` per attivazione condizionale

### TypeScript / JS (dashboard)
- Vanilla JS Step 0 (zero build step)
- Step 1+: TypeScript strict mode, React 18, Tailwind
- Niente emoji, palette navy + oro
- Densità informativa BlackBerry-style

### Markdown (docs)
- Linee max 100 chars
- Code fences con lingua specificata
- Tabelle allineate
- Italiano OK per docs SOLEM, inglese per OpenAPI/CHANGELOG

---

## Workflow Git

```
main          ← produzione, sempre verde, tag release v*
├── dev       ← integrazione, target PR
│   ├── feat/<feature-name>
│   ├── fix/<bug-name>
│   └── docs/<topic>
```

Branch:
- `feat/...` per feature nuove
- `fix/...` per bug fix
- `docs/...` per solo docs
- `refactor/...` per refactor senza nuova feature

Commit message: **convenzionali**
```
feat(L1): aggiungi versioning sezioni identity
fix(api): status 204 + return None genera AssertionError FastAPI
docs: aggiorna INSTALL.md con sezione disaster recovery
refactor(db): estrai _ensure_default_owner in bootstrap.py
test(memory): copri search LIKE con casi edge
```

---

## PR checklist

Prima di aprire PR:

- [ ] Test esistenti passano (`pytest` + `ruff check`)
- [ ] Nuovi test per ogni nuova funzione pubblica
- [ ] `nix eval` passa (no syntax error Nix)
- [ ] CHANGELOG.md aggiornato in sezione "Unreleased"
- [ ] Docs aggiornate se cambi behavior
- [ ] No segreti hardcoded (controllato manualmente + git diff)
- [ ] Filosofia rispettata (vedi sezione sopra)

---

## Architettura: come aggiungere

### Nuova Capability (L4)
1. Implementa endpoint in `backend/solem_api/layers/<layer>.py`
2. Aggiungi `CapabilityManifest(...)` a `layers/capabilities.py::SOLEM_NATIVE`
3. Aggiungi test in `backend/tests/test_capabilities.py`

### Nuova AI specialista (Step 3+)
1. Implementa endpoint HTTP che ricevi POST `/invoke` con `{task, context, model, system_prompt}`
2. Registra agent via `POST /solem/agents` con manifest
3. Modifica `system_prompt` di GAVIO per delegare quando contesto matches

### Nuovo modulo NixOS
1. Crea `nixos/modules/solem-<feature>.nix`
2. Aggiungi `./modules/solem-<feature>.nix` a `imports` di `nixos/configuration.nix`
3. Sempre `options.solem.<feature>.enable = lib.mkEnableOption "..."`
4. Documenta in `CHANGELOG.md`
5. Aggiungi sezione in `README.md` o `docs/<feature>.md`

### Nuova Extension L7 (Step 4+)
1. Crea repo separato `solem-extension-<name>`
2. Aggiungi `solem.extension.json` manifest (vedi `layers/extensions.py::ExtensionManifest`)
3. Submit PR su `solem-marketplace` (Step 4+) o testa localmente via `/solem/extensions/install`

---

## Code of conduct

- Rispetto reciproco
- Critica costruttiva (idee, non persone)
- Niente flame, niente politica fuori contesto
- Documenta le decisioni, non solo il codice
- Quando hai dubbi, chiedi prima invece di assumere

---

## Contatto

- Issue: GitHub
- Email founder: guidottrbn@gmail.com
- Discussions: GitHub Discussions (Step 4+ aperto al pubblico)
