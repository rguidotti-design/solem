#!/usr/bin/env bash
# solem-install — installer SOLEM bare-metal su disco
#
# Usa SOLO da live ISO NixOS minimal. Wizard interattivo che:
#  1. Identifica disco target
#  2. Crea partizioni (UEFI: /boot/efi + LUKS + ext4 root; BIOS: GRUB + LUKS + ext4)
#  3. Cifra root con LUKS2 (passphrase)
#  4. Monta filesystem
#  5. Clona repo SOLEM in /mnt/etc/nixos/solem
#  6. nixos-install
#  7. Reboot
#
# Uso (da live ISO NixOS):
#   curl -L https://raw.githubusercontent.com/.../solem-install.sh | sudo bash
# o se hai già il repo:
#   sudo ./scripts/solem-install.sh

set -euo pipefail

#─── Helpers ───────────────────────────────────────────────────────────
BOLD=$'\e[1m'
GOLD=$'\e[38;5;179m'
NAVY=$'\e[38;5;67m'
GREEN=$'\e[32m'
RED=$'\e[31m'
RESET=$'\e[0m'

ok()    { echo "  ${GREEN}●${RESET} $*"; }
warn()  { echo "  ${RED}!${RESET} $*"; }
step()  { echo ""; echo "${BOLD}${NAVY}══${RESET} ${BOLD}$*${RESET}"; }
ask()   { read -rp "  ${GOLD}?${RESET} $1 " REPLY; echo "$REPLY"; }
confirm() {
  read -rp "  ${GOLD}?${RESET} $1 [y/N] " REPLY
  [[ "$REPLY" =~ ^[Yy]$ ]]
}

#─── Banner ────────────────────────────────────────────────────────────
clear
cat <<'EOF'

       ███████╗  ██████╗  ██╗      ███████╗ ███╗   ███╗
       ██╔════╝ ██╔═══██╗ ██║      ██╔════╝ ████╗ ████║
       ███████╗ ██║   ██║ ██║      █████╗   ██╔████╔██║
       ╚════██║ ██║   ██║ ██║      ██╔══╝   ██║╚██╔╝██║
       ███████║ ╚██████╔╝ ███████╗ ███████╗ ██║ ╚═╝ ██║
       ╚══════╝  ╚═════╝  ╚══════╝ ╚══════╝ ╚═╝     ╚═╝

       Installer bare-metal — AI-native OS

EOF

#─── Pre-checks ───────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  warn "Eseguilo come root (sudo)."
  exit 1
fi

if ! command -v nixos-install >/dev/null 2>&1; then
  warn "Questo installer va eseguito da live ISO NixOS."
  warn "Scarica ISO da https://nixos.org/download e bootala."
  exit 1
fi

step "1/7 — Identificazione hardware"
ok "Modalità: $([ -d /sys/firmware/efi ] && echo 'UEFI' || echo 'BIOS Legacy')"
ok "Architettura: $(uname -m)"
echo ""
ok "Dischi disponibili:"
lsblk -dn -o NAME,SIZE,TYPE,MODEL | sed 's/^/    /'

DISK=$(ask "Disco target (es. /dev/sda, /dev/nvme0n1):")
[ -b "$DISK" ] || { warn "$DISK non esiste"; exit 1; }

warn "ATTENZIONE: TUTTI i dati su $DISK saranno CANCELLATI."
confirm "Procedere con installazione su $DISK?" || { echo "Annullato."; exit 1; }

#─── Partizionamento ──────────────────────────────────────────────────
step "2/7 — Partizionamento"
IS_UEFI=$([ -d /sys/firmware/efi ] && echo 1 || echo 0)

if [ "$IS_UEFI" = "1" ]; then
  parted "$DISK" -- mklabel gpt
  parted "$DISK" -- mkpart ESP fat32 1MiB 513MiB
  parted "$DISK" -- set 1 esp on
  parted "$DISK" -- mkpart primary 513MiB 100%

  EFI_PART="${DISK}1"; ROOT_PART="${DISK}2"
  [[ "$DISK" =~ nvme ]] && { EFI_PART="${DISK}p1"; ROOT_PART="${DISK}p2"; }
else
  parted "$DISK" -- mklabel msdos
  parted "$DISK" -- mkpart primary 1MiB 100%
  parted "$DISK" -- set 1 boot on
  ROOT_PART="${DISK}1"
fi

ok "Partizioni create"

#─── LUKS encryption ──────────────────────────────────────────────────
step "3/7 — Cifratura LUKS2 root"
if confirm "Cifrare la root partition con LUKS2?"; then
  warn "Sarà richiesta una passphrase. NON dimenticarla — non c'è recovery."
  cryptsetup luksFormat --type luks2 "$ROOT_PART"
  cryptsetup luksOpen "$ROOT_PART" cryptroot
  ROOT_DEV="/dev/mapper/cryptroot"
  USE_LUKS=1
else
  ROOT_DEV="$ROOT_PART"
  USE_LUKS=0
fi

#─── Filesystem ───────────────────────────────────────────────────────
step "4/7 — Filesystem"
mkfs.ext4 -L nixos "$ROOT_DEV"
[ "$IS_UEFI" = "1" ] && mkfs.fat -F 32 -n boot "$EFI_PART"

mount /dev/disk/by-label/nixos /mnt
[ "$IS_UEFI" = "1" ] && { mkdir -p /mnt/boot; mount "$EFI_PART" /mnt/boot; }
ok "Filesystem montati"

#─── Generate config + clone SOLEM ────────────────────────────────────
step "5/7 — Genera config NixOS + clona SOLEM"
nixos-generate-config --root /mnt
mkdir -p /mnt/etc/nixos/solem

SOURCE_DIR="${SOLEM_SOURCE:-/iso/solem}"
if [ ! -d "$SOURCE_DIR" ]; then
  REPO_URL=$(ask "URL git repo SOLEM (es. https://github.com/USER/solem):")
  nix-shell -p git --run "git clone --depth 1 '$REPO_URL' /mnt/etc/nixos/solem"
else
  cp -r "$SOURCE_DIR"/* /mnt/etc/nixos/solem/
fi
ok "SOLEM in /mnt/etc/nixos/solem"

#─── Hardware configuration custom ────────────────────────────────────
step "6/7 — Genera hardware-bare.nix"
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_DEV")
LUKS_UUID=$([ "$USE_LUKS" = "1" ] && blkid -s UUID -o value "$ROOT_PART" || echo "")
EFI_UUID=$([ "$IS_UEFI" = "1" ] && blkid -s UUID -o value "$EFI_PART" || echo "")

cat > /mnt/etc/nixos/solem/nixos/hardware-bare.nix <<EOF
{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" "kvm-amd" ];
$([ "$USE_LUKS" = "1" ] && cat <<EOF2
  boot.initrd.luks.devices.cryptroot = {
    device = "/dev/disk/by-uuid/$LUKS_UUID";
    allowDiscards = true;
  };
EOF2
)
  fileSystems."/" = { device = "/dev/disk/by-uuid/$ROOT_UUID"; fsType = "ext4"; };
$([ "$IS_UEFI" = "1" ] && echo "  fileSystems.\"/boot\" = { device = \"/dev/disk/by-uuid/$EFI_UUID\"; fsType = \"vfat\"; };")
$([ "$IS_UEFI" = "1" ] && cat <<EOF3
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
EOF3
) $([ "$IS_UEFI" != "1" ] && echo "  boot.loader.grub = { enable = true; device = \"$DISK\"; };")
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
EOF
ok "hardware-bare.nix generato"

# Aggiungi configurazione solem-bare al flake
cat >> /mnt/etc/nixos/solem/flake.nix.bare <<'EOF'
# Aggiungi a flake.nix:
# nixosConfigurations.solem-bare = nixpkgs.lib.nixosSystem {
#   inherit system;
#   modules = [
#     ./nixos/configuration.nix
#     ./nixos/hardware-bare.nix
#   ];
# };
EOF

#─── Install ──────────────────────────────────────────────────────────
step "7/7 — nixos-install (richiede ~10-30 min)"
warn "Lo step finale scarica/builda l'intero sistema. Non interrompere."
confirm "Procedere?" || { echo "Annullato. /mnt resta montato per intervento manuale."; exit 0; }

nixos-install --root /mnt --flake "/mnt/etc/nixos/solem#solem-bare"

ok ""
ok "Installazione completata!"
ok "Riavvia (rimuovi ISO): ${BOLD}reboot${RESET}"
ok "Al primo boot: login ${BOLD}gavio${RESET} / password configurata"
ok "Cambia la password subito con: ${BOLD}passwd${RESET}"
