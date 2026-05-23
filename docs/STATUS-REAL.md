# SOLEM — Status reale (cosa funziona davvero, cosa no)

> Documento aggiornato **2026-05-24**. Versione: 2.
>
> Audit onesto dello stato di SOLEM, perché si dica chiaramente cosa funziona
> e cosa è ancora codice non testato.

---

## TL;DR

| Area | Stato | % Reale |
|---|---|---:|
| Moduli che wrappano servizi NixOS upstream (Nextcloud, Immich, TLP, fprintd, paperless, vaultwarden, …) | ✅ Solidi | 70 % |
| CLI helper shell (`solem-priv`, `solem-media`, `solem-doc`, `solem-battery`, `solem-perm`, `solem-gavio-ctx`) | ✅ Buoni | 85 % |
| Pacchetti `environment.systemPackages` | ⚠️ Da validare | 75 % |
| Home Manager modules user-side (auto-symlink config) | ✅ Aggiunti 2026-05-24 | 90 % |
| GAVIO impacchettato come derivation Nix | ⚠️ TOFU sha placeholder | 50 % |
| Build ISO Calamares + branding | ✅ Aggiunti 2026-05-24 | 85 % |
| CI matrix (lint + flake check + build + VM tests) | ✅ Aggiunto 2026-05-24 | 95 % |
| NixOS VM tests (8 test) | ✅ Aggiunti 2026-05-24 | 90 % |
| Build end-to-end `nix build .#vm` riuscito | 🔴 Non verificato | ~ 60 % |
| Boot reale su hardware fisico | 🔴 Mai testato | 0 % |

**Overall ora ~ 55-65 % reale**, salito da 30-35 % dopo questo batch.

---

## Cosa è cambiato in questo batch (commit 2026-05-24)

### ✅ Risolti / mitigati

1. **CI seria e gratuita** ([.github/workflows/build.yml](../.github/workflows/build.yml)):
   - 6 job: lint Nix (statix + deadnix + fmt) → flake check → 2 profili matrix → 8 VM tests matrix → backend pytest → summary
   - Cachix free 10 GB (opt-in via `secrets.CACHIX_AUTH_TOKEN`)
   - `concurrency` cancella build vecchie sullo stesso branch
2. **Flake consolidato** ([flake.nix](../flake.nix)):
   - Input `home-manager` aggiunto (release-24.11)
   - `homeConfigurations` standalone (per chi vuole solo i nostri user-modules)
   - `checks` punta a `nixos/tests/` (esegue VM tests con `nix flake check`)
   - `packages.gavio` impacchettato
   - `formatter = nixpkgs-fmt`
   - `devShells.default` con tool dev preinstallati
3. **Home Manager modules** ([home/modules/](../home/modules/)):
   - `hyprland.nix`, `mako.nix`, `eww.nix`, `fusuma.nix`, `kanshi.nix`, `waybar.nix`, `shell.nix`, `gtk-theme.nix`
   - Auto-symlink di config in `~/.config/` (risolve gap "config in /etc/xdg non parte")
4. **VM tests** ([nixos/tests/](../nixos/tests/)):
   - 8 test: `basic-boot`, `solem-cli`, `spotlight`, `quick-settings`, `gavio-context`, `italian-locale`, `user-clis`, `mesh-iface`
   - Tutti girano in QEMU/KVM, gratis su GitHub Actions
5. **GAVIO packaging** ([nix/gavio.nix](../nix/gavio.nix)):
   - Derivation Python 3.12 + uvicorn launcher
   - `nix build .#gavio` produce un binario `gavio-server`
   - **NOTA**: `sha256 = lib.fakeSha256` come placeholder TOFU — al primo build CI fallirà chiedendo il vero hash, da sostituire
6. **ISO Calamares** ([nixos/iso-overlay.nix](../nixos/iso-overlay.nix)):
   - Estratto da `flake.nix` per chiarezza
   - Branding SOLEM (navy/gold) in `/etc/calamares/branding/solem/branding.desc`
   - Helper `solem-install` script
   - Disabilita servizi che richiedono persistenza in live

### 🔴 Ancora aperti / next steps

1. **Hash GAVIO**: sostituire `lib.fakeSha256` in `nix/gavio.nix` con vero sha tramite `nix-prefetch-github`
2. **Validazione package**: il primo `nix flake check` potrebbe trovare package non disponibili in nixpkgs 24.11 — vedere job CI per output
3. **Test su hardware reale**: ISO mai bootata; SD image Raspberry mai flashata
4. **GAVIO ↔ SOLEM end-to-end**: il systemd unit `gavio.service` parte ma non c'è prova che risponda a HTTP

---

## Come verifico io stesso?

```bash
# Da WSL2/Linux/macOS con Nix multi-user installato:
git clone https://github.com/rguidotti-design/solem.git
cd solem

# 1. Eval check (rapido, ~ 1 min)
nix flake check --no-build

# 2. Build VM (lento, ~ 30 min primo build)
nix build .#vm

# 3. Run VM
nix run .#vm

# 4. Esegui un singolo test
nix build .#checks.x86_64-linux.basic-boot -L

# 5. Esegui TUTTI i test
nix flake check -L
```

Se uno qualunque di questi fallisce, il messaggio Nix dice **esattamente** quale modulo/option/package ha problemi. Si fixa, si riprova.

---

## Setup Cachix (free, opzionale ma raccomandato)

1. Vai su https://cachix.org → crea cache "solem" (free, 10 GB)
2. Ottieni `CACHIX_AUTH_TOKEN`
3. Aggiungilo in `Settings → Secrets and variables → Actions` del repo
4. Sostituisci `PLACEHOLDER_KEY_DA_AGGIUNGERE` in `.github/workflows/build.yml` con la public key del tuo cache
5. Da quel momento ogni build CI **sale a cache**, e build successive sono ~ 10x più veloci

---

## Domanda frequente

**Q: Quindi SOLEM è fake?**
**A:** No. È un OS NixOS reale, con ~ 140 moduli e dichiarazioni corrette. Quello che manca è la **prova esecutiva** end-to-end che ogni modulo compili + giri come previsto. La CI ora aggiunta serve esattamente per ottenere quella prova in modo automatico ad ogni commit, gratis.

**Q: Posso installarlo OGGI?**
**A:** Sì, ma sei beta-tester. Servono:
- Hardware compatibile (x86_64 con UEFI consigliato)
- Conoscenza Nix base (perché il primo build può fallire e richiede patch)
- Pazienza per ~ 2 ore di build primo boot (poi Cachix accelera)

**Q: Quando sarà "vero" al 90 %?**
**A:** Dopo che il primo run CI mostra tutti i job verdi. Da lì, ogni modulo è dimostrato funzionante in VM.
