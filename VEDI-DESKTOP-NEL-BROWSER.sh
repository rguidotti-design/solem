#!/usr/bin/env bash
# VEDI-DESKTOP-NEL-BROWSER.sh — lancia VM SOLEM GNOME + VNC web
#
# Uso (in WSL Ubuntu):
#   cd /mnt/c/Users/guido/Desktop/solem
#   bash VEDI-DESKTOP-NEL-BROWSER.sh
#
# Poi apri browser Edge/Chrome su:
#   http://localhost:6080/vnc.html
#
# TENERE QUESTO TERMINALE APERTO — chiude = VM si spegne.

set -e

cd "$(dirname "$0")"

echo "================================================================"
echo "  SOLEM Desktop via browser — setup"
echo "================================================================"
echo

# Verifica WSL / Linux
if grep -qi microsoft /proc/version 2>/dev/null; then
    echo "✓ WSL detected"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "✓ Linux nativo"
else
    echo "✗ OS non supportato"
    exit 1
fi

# Cleanup vecchi processi
echo "→ Cleanup..."
pkill -f qemu-kvm 2>/dev/null || true
pkill -f novnc 2>/dev/null || true
pkill -f websockify 2>/dev/null || true
sleep 2

# Verifica build vm-gnome esiste
if [ ! -x ./result-gnome/bin/run-solem-gnome-demo-vm ]; then
    echo "→ VM gnome non buildata. Build ora (30-60 min primo run)..."
    nix build .#vm-gnome --extra-experimental-features 'nix-command flakes' -o result-gnome
fi

# Reset disk per boot pulito
rm -f solem-gnome-demo.qcow2

# Lancia VM con VNC su porta 5900
echo "→ Avvio VM GNOME (VNC porta 5900)..."
./result-gnome/bin/run-solem-gnome-demo-vm -vnc 0.0.0.0:0 -display none &
VM_PID=$!
echo "  VM PID: $VM_PID"

# Aspetta VNC up
for i in 1 2 3 4 5 6 7 8 9 10; do
    if ss -tlnp 2>/dev/null | grep -q ":5900 "; then
        echo "✓ VNC server attivo su porta 5900"
        break
    fi
    sleep 2
done

# Lancia noVNC (web bridge)
echo "→ Avvio noVNC web bridge (porta 6080)..."
nix-shell -p novnc --run "novnc --listen 6080 --vnc localhost:5900" > /tmp/novnc.log 2>&1 &
NOVNC_PID=$!
sleep 3

# Verifica
if ss -tlnp 2>/dev/null | grep -q ":6080 "; then
    echo "✓ noVNC attivo su porta 6080"
else
    echo "✗ noVNC NON partito. Vedi /tmp/novnc.log"
    cat /tmp/novnc.log
    exit 1
fi

echo
echo "================================================================"
echo "  ✓ DESKTOP SOLEM PRONTO"
echo "================================================================"
echo
echo "  APRI NEL BROWSER (Edge/Chrome/Firefox su Windows):"
echo
echo "      http://localhost:6080/vnc.html"
echo
echo "  Click 'Connect'. Aspetta ~30s che GNOME parta nella VM."
echo "  Vedrai Plymouth boot -> GDM auto-login -> GNOME Desktop."
echo
echo "================================================================"
echo
echo "  TIENI QUESTO TERMINALE APERTO. Chiude = VM si spegne."
echo "  Per stop: Ctrl-C"
echo
echo "  VM PID: $VM_PID"
echo "  noVNC PID: $NOVNC_PID"
echo

# Trap cleanup on Ctrl-C
trap 'echo; echo "→ Stop VM + noVNC..."; kill $VM_PID $NOVNC_PID 2>/dev/null; exit 0' INT TERM

# Tieni vivo finche' VM gira
wait $VM_PID
