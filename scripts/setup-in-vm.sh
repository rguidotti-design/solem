#!/usr/bin/env bash
# Da eseguire DENTRO una VM NixOS appena installata da ISO ufficiale.
# Trasforma la VM minimal in SOLEM applicando la configurazione del repo.
#
# Usalo se NON hai Nix sull'host (alternativa a `nix run .#vm` da WSL).
#
# Procedura:
#   1. Scarica ISO NixOS minimal (https://nixos.org/download)
#   2. Crea VM in VirtualBox/QEMU/Hyper-V (4GB RAM, 20GB disco, NAT con
#      port forward 22→2222 e 8000→8000)
#   3. Installa NixOS minimal con `nixos-install` (vedi manuale ufficiale)
#   4. Reboot e login come tuo utente
#   5. Copia/clona questa cartella `solem/` dentro la VM in /etc/nixos/solem
#   6. Esegui: sudo SOLEM_DIR=/etc/nixos/solem ./scripts/setup-in-vm.sh

set -euo pipefail

SOLEM_DIR="${SOLEM_DIR:-/etc/nixos/solem}"

if [ "$EUID" -ne 0 ]; then
  echo "Eseguilo come root o con sudo." >&2
  exit 1
fi

if [ ! -d "$SOLEM_DIR" ]; then
  echo "Cartella SOLEM non trovata in $SOLEM_DIR" >&2
  echo "Imposta SOLEM_DIR=/percorso/solem o copia là il repo." >&2
  exit 1
fi

# Abilita flakes globalmente
mkdir -p /etc/nix
if ! grep -q "experimental-features" /etc/nix/nix.conf 2>/dev/null; then
  echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf
fi

cd "$SOLEM_DIR"

# Applica configurazione SOLEM
echo "[setup-in-vm] nixos-rebuild switch…"
nixos-rebuild switch --flake .#solem-vm

cat <<EOF

SOLEM applicato.

Prossimi passi:
  1. passwd          → cambia password di gavio (default: gavio)
  2. Crea /etc/gavio/env (vedi /etc/gavio/env.example) con le tue API key
  3. Monta GAVIO in /opt/gavio:
       - se hai shared folder VirtualBox: VBoxManage sharedfolder add ...
       - oppure git clone https://… /opt/gavio
  4. systemctl start gavio
  5. journalctl -u gavio -f   (per vedere i log)
  6. curl http://localhost:8000/health
EOF
