#!/usr/bin/env bash
# Build SOLEM VM image (richiede Nix con flakes su Linux/WSL2).
#
# Prerequisiti:
#   - WSL2 con Ubuntu (o Linux nativo)
#   - Nix installato: sh <(curl -L https://nixos.org/nix/install) --daemon
#   - Flakes abilitati: ~/.config/nix/nix.conf con
#     "experimental-features = nix-command flakes"
#
# Uso: ./scripts/build-vm.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOLEM_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$SOLEM_ROOT"

echo "[solem] Build VM SOLEM…"
echo "[solem] (prima volta: scarica nixpkgs ~500MB, ci mette 5-15 min)"

# Build VM eseguibile (script che lancia QEMU con la configurazione SOLEM)
nix build .#vm --print-out-paths

echo ""
echo "Build completato."
echo "Lancia la VM con:"
echo "  ./result/bin/run-solem-vm"
echo ""
echo "Oppure direttamente:"
echo "  nix run .#vm"
