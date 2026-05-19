# ADR-003 — bcachefs su Beelink Step 1, ext4 in VM test

**Status**: Accettato
**Data**: 2026-05-17

## Contesto

Prompt v4.0 sez. 2.1 chiede bcachefs default (snapshot/checksum BLAKE3/zstd compression/AES-256-GCM nativi). VM test attuale usa ext4 (semplice, KVM-friendly, niente sorprese).

## Decisione

- **VM test (Step 0)**: ext4 + LUKS opt. Resta com'è. Bcachefs in QEMU = complicato.
- **Beelink bare-metal (Step 1)**: bcachefs come root filesystem, sotto LUKS2.
  - Snapshot pre-aggiornamento automatici (integra con NixOS generations)
  - Compression zstd attiva
  - Checksum BLAKE3 ovunque
  - Encryption gestita da LUKS sotto (defense in depth)
- **Da subito (Mese 2-3)**: script `tests/bcachefs-vm.sh` che fa test bcachefs con disk image secondario nella VM → verifica behavior prima del rollout Beelink.

## Conseguenze

**Positive**:
- Bare-metal Beelink production-grade con FS moderno
- Test bcachefs anticipato evita sorprese

**Negative**:
- bcachefs è "experimental" nel kernel < 6.7 (24.11 ha 6.6.94, supportato ma giovane)
- Recovery più complesso di ext4 in caso disastro

## Mitigazioni

- Backup automatico in `/var/backups/solem/` (snapshot zstd) → recovery indipendente da bcachefs
- Documentazione disaster recovery in `docs/INSTALL.md` aggiornata
- Su Beelink resta opzione "ext4 mode" come fallback (`solem.filesystem = "ext4" | "bcachefs"`)
