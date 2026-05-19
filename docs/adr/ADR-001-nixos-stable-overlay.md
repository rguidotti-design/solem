# ADR-001 — NixOS stable + overlay unstable selettivo

**Status**: Accettato
**Data**: 2026-05-17
**Decisori**: Ruben Guidotti (founder) + assistente di sistema

## Contesto

Il Prompt Master v4.0 sez. 1.1 chiede "Linux LTS più recente con hardening". SOLEM Step 0 è su `nixos-24.11` (stable, LTS). Pacchetti AI/Wayland cambiano molto velocemente — restare su stable rallenta accesso a versioni nuove di Hyprland, llama.cpp, ollama, ecc.

## Opzioni considerate

1. **Solo stable 24.11** — riproducibile, ma pacchetti AI vecchi di mesi
2. **Solo unstable** — sempre l'ultima versione, ma rebuild rumorosi, possibili regressioni
3. **Hybrid: stable base + overlay unstable selettivo** ← scelto

## Decisione

Base sistema su `nixos-24.11`. Aggiungo input `nixpkgs-unstable` al flake e creo overlay che importa da unstable **solo per**:

- `hyprland`, `waybar`, `wofi`, `mako` (Wayland ecosystem)
- `ollama`, `llama-cpp`, `whisper-cpp`, `piper` (AI inference)
- `caddy` (reverse proxy mTLS, security fixes)

Kernel, systemd, glibc, networkmanager → stable (riproducibilità + stabilità boot).

## Conseguenze

**Positive**:
- Boot/sistema affidabili come stable
- Tooling AI sempre aggiornato
- Surface area aggiornamenti ridotta (solo overlay)

**Negative**:
- Maggiore complessità flake.nix
- Possibili incompatibilità di librerie tra stable/unstable (mitigate da Nix isolamento)

## Implementazione

Aggiunge in `flake.nix` input `nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable"` + overlay che mappa selettivamente pacchetti unstable.

Riferimento upstream: pattern "overlay-by-attribute" documentato in nixpkgs manual.
