# SOLEM — stato build artifacts

Tracciamento dei build effettivamente eseguiti (oltre alla CI eval).

## ISO x86_64

| Data        | SHA commit | Size  | Build host | Stato                | Note                  |
|-------------|------------|-------|------------|----------------------|-----------------------|
| 2026-05-21  | a9cdcfd    | 5.5 GB| WSL2 Ubuntu| ✅ Build OK          | Primo build riuscito  |

**Comando**: `nix build .#iso`
**Path**: `result/iso/nixos-24.11.20250630.50ab793-x86_64-linux.iso`

### Contenuto verificato (eval/build)
- Live system bootable con utente `gavio` (password iniziale `gavio`)
- Banner getty branded SOLEM
- NetworkManager attivo
- SSH server abilitato (port 22)
- Tutto SOLEM stack in /run/current-system

### Da verificare (richiede QEMU/hardware)
- [ ] Boot effettivo in QEMU (login getty entro 120s)
- [ ] `solem status` risponde nel live system
- [ ] `solem-init` interattivo funziona
- [ ] nixos-install su disco riesce

## SD-image Raspberry Pi 4/5 (aarch64)

| Data        | SHA commit | Stato                  |
|-------------|------------|------------------------|
| 2026-05-21  | a9cdcfd    | ✅ Eval OK (nix eval)   |
| —           | —          | ⏳ Build mai eseguito   |

**Comando**: `nix build .#raspberry`
**Path target**: `result/sd-image/*.img`
**Tempo stimato build cross-arch su x86_64**: 30-60 min

## SD-image Jetson Nano/Orin (aarch64)

| Data        | SHA commit | Stato                  |
|-------------|------------|------------------------|
| 2026-05-21  | a9cdcfd    | ✅ Eval OK (nix eval)   |
| —           | —          | ⏳ Build mai eseguito   |

**Avviso**: senza overlay `jetpack-nixos`, il BSP NVIDIA Tegra non è incluso. La SD image bootta ma niente CUDA hardware. Vedi `nixos/modules/solem-jetson.nix`.

## VM x86_64

| Data        | SHA commit | Stato                                |
|-------------|------------|--------------------------------------|
| 2026-05-17  | (early)    | ✅ Build + run OK in QEMU (manuale)   |

**Comando**: `nix run .#vm`
**Note**: usato per dev iterativo. Login `gavio/gavio`, accesso `ssh -p 2222`.

## Test suite

| Suite                      | Test count | CI status            |
|----------------------------|------------|----------------------|
| backend/tests/             | 98         | Verificare workflow  |
| Integration trittico       | 1 (end2end)| ✅ Locale            |
| Cluster device_class       | 7          | ✅ Locale            |
| Smoke main + manifest      | 6          | ✅ Locale            |

## CI GitHub Actions

| Workflow         | Stato locale     | Note                                  |
|------------------|------------------|---------------------------------------|
| smoke-test.yml   | aggiornato       | 5 job: backend tests, api smoke, flake check, progress server, eval all arches |
| build.yml        | da verificare    | Pre-esistente                         |
| release.yml      | da verificare    | Pre-esistente                         |

## Roadmap build

- [x] Build ISO x86_64 (5.5 GB)
- [ ] Smoke boot ISO in QEMU headless con getty timeout
- [ ] Build SD-image Raspberry (cross-arch su x86_64 + binfmt aarch64)
- [ ] Build SD-image Jetson (richiede jetpack-nixos overlay)
- [ ] Release GitHub con .iso allegata
- [ ] Build deterministico riproducibile (verifica hash su builds successive)
