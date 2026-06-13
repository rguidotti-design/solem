#!/usr/bin/env bash
# APRI-SOLEM.sh — apre SOLEM desktop come FINESTRA Windows (via WSLg).
#
# Niente VNC, niente browser, niente networking. Finestra nativa.
#
# Uso (in WSL Ubuntu):
#   cd /mnt/c/Users/guido/Desktop/solem
#   bash APRI-SOLEM.sh
#
# Si apre una finestra QEMU sul desktop Windows con SOLEM GNOME.
# TIENI APERTO questo terminale. Per spegnere: chiudi la finestra o Ctrl-C qui.

set -e
cd "$(dirname "$0")"

echo "════════════════════════════════════════════════"
echo "  SOLEM — apertura desktop (finestra Windows)"
echo "════════════════════════════════════════════════"
echo

# Verifica WSLg
if [ ! -d /mnt/wslg ]; then
    echo "✗ WSLg non disponibile. Serve WSL2 su Windows 11."
    echo "  Update: wsl --update  (da PowerShell)"
    exit 1
fi
echo "✓ WSLg disponibile"

# Environment WSLg per finestra grafica
export DISPLAY=:0
export WAYLAND_DISPLAY=wayland-0
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export GDK_BACKEND=x11
export PULSE_SERVER=unix:/mnt/wslg/PulseServer

# Cleanup processi vecchi (VNC, ecc.)
pkill -f qemu-kvm 2>/dev/null || true
pkill -f novnc 2>/dev/null || true
pkill -f websockify 2>/dev/null || true
sleep 2

# Verifica build esiste
if [ ! -x ./result-gnome/bin/run-solem-gnome-demo-vm ]; then
    echo "→ VM non buildata. Build (30-60 min primo run)..."
    nix build .#vm-gnome --extra-experimental-features 'nix-command flakes' -o result-gnome
fi

# Reset disco per boot pulito
rm -f solem-gnome-demo.qcow2

echo
echo "→ Avvio SOLEM... (la finestra apparira tra ~10 secondi)"
echo "  Login automatico: utente gavio"
echo "  Aspetta ~60s per il desktop GNOME completo."
echo
echo "  TIENI QUESTO TERMINALE APERTO."
echo "  Per spegnere: chiudi finestra QEMU o premi Ctrl-C qui."
echo

# Lancia QEMU con finestra GTK nativa (WSLg la proietta su Windows)
exec ./result-gnome/bin/run-solem-gnome-demo-vm -display gtk,gl=off
