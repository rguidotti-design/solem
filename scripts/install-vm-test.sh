#!/usr/bin/env bash
# SOLEM — smoke test ISO in QEMU (headless).
#
# Builda l'ISO + la avvia in QEMU + verifica che il login getty risponda.
# Usato per validare che l'ISO si avvii davvero senza intervento manuale.
#
# Richiede: nix (con flake), qemu, expect (opzionale per scripted login).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

echo "  ╔════════════════════════════════════════════════════╗"
echo "  ║   SOLEM — smoke test ISO in QEMU                   ║"
echo "  ╚════════════════════════════════════════════════════╝"
echo

# Pre-flight
for cmd in nix qemu-system-x86_64; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERRORE: $cmd non installato. Skip test."
        exit 1
    fi
done

# Build ISO (skip se già presente)
if [ ! -e result/iso ]; then
    echo "  [1/3] Build ISO..."
    nix build .#iso --extra-experimental-features 'nix-command flakes' --print-build-logs
fi

ISO_PATH=$(ls result/iso/*.iso 2>/dev/null | head -n1)
if [ -z "$ISO_PATH" ]; then
    echo "ERRORE: nessuna ISO trovata in result/iso/"
    exit 1
fi
echo "  ISO: $ISO_PATH ($(du -h "$ISO_PATH" | cut -f1))"

# Boot headless con monitor su file FIFO
echo "  [2/3] Boot ISO in QEMU (headless, 2 GB RAM)..."
QEMU_LOG=/tmp/solem-vm-smoke.log
qemu-system-x86_64 \
    -m 2048 -smp 2 \
    -cdrom "$ISO_PATH" \
    -nographic \
    -serial mon:stdio \
    -boot d \
    > "$QEMU_LOG" 2>&1 &
QEMU_PID=$!
echo "  PID: $QEMU_PID · log: $QEMU_LOG"

# Aspetta che apparga il login getty (max 120s)
echo "  [3/3] Aspetto getty login (max 120s)..."
TIMEOUT=120
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if grep -q "login:" "$QEMU_LOG" 2>/dev/null; then
        echo "  ✓ Login prompt apparso dopo ${ELAPSED}s"
        kill -9 $QEMU_PID 2>/dev/null || true
        echo
        echo "  ╔════════════════════════════════════════════════════╗"
        echo "  ║   ✓ ISO BOOT OK                                    ║"
        echo "  ╚════════════════════════════════════════════════════╝"
        exit 0
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    if [ $((ELAPSED % 10)) -eq 0 ]; then
        echo "    ...attendo (${ELAPSED}s/${TIMEOUT}s)"
    fi
done

# Timeout
kill -9 $QEMU_PID 2>/dev/null || true
echo
echo "  ✗ TIMEOUT — login non apparso entro ${TIMEOUT}s"
echo "  Log boot:"
tail -40 "$QEMU_LOG"
exit 1
