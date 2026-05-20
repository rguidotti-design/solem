#!/usr/bin/env bash
# SOLEM — build immagine per ogni form factor.
#
# Uso:
#   ./scripts/build-image.sh iso        # x86_64 ISO bootable
#   ./scripts/build-image.sh raspberry  # ARM64 SD image per Raspberry Pi 4/5
#   ./scripts/build-image.sh jetson     # ARM64 SD image per Jetson Nano/Orin
#   ./scripts/build-image.sh vm         # QEMU VM x86_64
#
# Richiede: nix (>= 2.18) con flake. Per cross-build ARM64 da x86_64,
# binfmt_misc + qemu-user-static abilitati nel sistema host (NixOS):
#   boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

set -euo pipefail

TARGET="${1:-iso}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

if ! command -v nix >/dev/null 2>&1; then
    echo "ERRORE: nix non installato."
    echo "  Install (Linux/WSL2): curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install"
    exit 1
fi

echo "  ╔════════════════════════════════════════════════════╗"
echo "  ║   SOLEM build · target: ${TARGET}"
echo "  ╚════════════════════════════════════════════════════╝"
echo

case "$TARGET" in
    iso|ISO)
        echo "  Build ISO x86_64 (~3-8 min, ~1.5 GB)..."
        nix build .#iso --extra-experimental-features 'nix-command flakes' --print-build-logs
        ls -lh result/iso/*.iso 2>/dev/null || ls -lh result/iso/
        echo
        echo "  Scrivi su USB: sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress"
        ;;

    vm|VM)
        echo "  Build VM x86_64 + lancio QEMU..."
        nix run .#vm --extra-experimental-features 'nix-command flakes'
        ;;

    raspberry|pi|raspberry-pi)
        echo "  Build SD image Raspberry Pi aarch64 (~10-20 min, ~2 GB)..."
        echo "  NB: richiede binfmt aarch64 abilitato se host è x86_64."
        nix build .#packages.aarch64-linux.raspberry \
            --extra-experimental-features 'nix-command flakes' \
            --print-build-logs
        ls -lh result/sd-image/*.img 2>/dev/null || ls -lh result/
        echo
        echo "  Scrivi su microSD (>= 16 GB): sudo dd if=result/sd-image/*.img of=/dev/sdX bs=4M status=progress"
        echo "  Poi: inserisci nel Pi, collega ethernet/wifi, ssh gavio@solem-pi-pi4.local (pwd: gavio)"
        ;;

    jetson|nano)
        echo "  Build SD image Jetson Nano/Orin aarch64..."
        echo "  AVVISO: jetpack-nixos BSP NVIDIA non ancora integrato."
        echo "  Scaffold ok, ma per CUDA Tegra completo: vedi modulo solem-jetson.nix."
        nix build .#packages.aarch64-linux.jetson \
            --extra-experimental-features 'nix-command flakes' \
            --print-build-logs
        ls -lh result/sd-image/*.img 2>/dev/null || ls -lh result/
        ;;

    all)
        for t in iso raspberry jetson; do
            echo "  → $t"
            "$0" "$t"
        done
        ;;

    *)
        echo "Target sconosciuto: $TARGET"
        echo "Usage: $0 [iso|vm|raspberry|jetson|all]"
        exit 1
        ;;
esac
