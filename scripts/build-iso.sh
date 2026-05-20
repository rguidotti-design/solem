#!/usr/bin/env bash
# Build ISO bootable di SOLEM. Funziona su Linux (incluso WSL2).
#
# Output: ./result/iso/solem-*.iso
# Scrivibile su USB stick con:  dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

echo "  ╔════════════════════════════════════════════════════╗"
echo "  ║   SOLEM — build ISO bootable                       ║"
echo "  ╚════════════════════════════════════════════════════╝"
echo
echo "  Repo:  $REPO_ROOT"
echo "  Stima: 3-8 min · Output: ~1.5 GB"
echo

if ! command -v nix >/dev/null 2>&1; then
    echo "ERRORE: nix non installato. Installa con:"
    echo "  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install"
    exit 1
fi

nix build .#iso \
  --extra-experimental-features 'nix-command flakes' \
  --print-build-logs

echo
echo "  ╔════════════════════════════════════════════════════╗"
echo "  ║   ✓ ISO costruita                                  ║"
echo "  ╚════════════════════════════════════════════════════╝"
echo
ls -lh result/iso/*.iso 2>/dev/null || ls -lh result/iso/

cat <<EOF

  Per scrivere su USB stick:
    sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress conv=fsync
  ATTENZIONE: /dev/sdX è la chiavetta — TUTTO il contenuto verrà cancellato.

  Per testare in VM senza scrivere su disco:
    qemu-system-x86_64 -enable-kvm -m 4G -cdrom result/iso/*.iso

EOF
