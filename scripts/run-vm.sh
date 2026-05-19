#!/usr/bin/env bash
# Lancia SOLEM VM (shortcut per `nix run .#vm`).
#
# La cartella GAVIO host viene montata automaticamente in /opt/gavio
# secondo la configurazione in nixos/hardware-vm.nix (sharedDirectories).
#
# Accesso dopo il boot:
#   - GAVIO API:    http://localhost:8000
#   - SSH:          ssh -p 2222 gavio@localhost  (password: gavio)
#   - Console:      direttamente nel terminale (graphics=false)
#
# Per uscire dalla VM: Ctrl-A, X (sequenza QEMU monitor)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOLEM_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$SOLEM_ROOT"
exec nix run .#vm
