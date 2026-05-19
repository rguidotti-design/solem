# ADR-002 — Rust adoption: new critical-path Rust by default

**Status**: Accettato
**Data**: 2026-05-17

## Contesto

Prompt v4.0 sez. 5.4 chiede memory safety via Rust ove possibile. SOLEM Step 0 ha 4 CLI Python (`solem-cli`, `solem-shell`, `solem-doctor`, `solem-keep`) + backend Python FastAPI. Riscrivere tutto in Rust = mesi di lavoro per zero beneficio percepibile finora.

## Opzioni considerate

1. **Rewrite-all** Python→Rust Step 1 — costoso, rischio bug nuovi
2. **Nessuna Rust adoption** — viola direttiva v4.0
3. **Selective: nuovo critical-path Rust, esistente Python** ← scelto

## Decisione

- **Codice esistente Python**: resta Python. Riscrivere in Rust SOLO se profiling dimostra bottleneck di performance o sicurezza.
- **Nuovo critical-path code**: Rust by default. Include:
  - Futuro `gaviod` daemon (Gavio Runtime Subsystem) — IPC ring buffer
  - Eventuali kernel module SOLEM (rust-for-linux)
  - Componenti che gestiscono memoria condivisa, lock, concurrency intensa
- **Non-critical new code**: Python OK (CLI, scripting, glue)
- **FFI Python↔Rust** via `pyo3` quando ha senso (es. inference dispatcher chiamato da FastAPI Python)

## Conseguenze

**Positive**:
- Memory safety dove conta (IPC, kernel-userspace)
- Iterazione rapida su CLI/glue dove non conta
- No rewrite cieco

**Negative**:
- Doppio stack (Python + Rust) = doppia toolchain
- Possibile FFI overhead

## Implementazione

Step 2+: aggiungere `cargo` + `rust-analyzer` ai dev tools del profilo `developer`. Setup workspace `backend/rust/` dedicato per moduli Rust quando necessari.
