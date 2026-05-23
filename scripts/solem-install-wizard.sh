#!/usr/bin/env bash
# SOLEM INSTALL WIZARD — installer interattivo 5 step bare-metal.
#
# Single responsibility: SOLO guidare l'utente nell'installazione.
# Wraps nixos-install con prompt sicuri, LUKS opzionale, profile scelto.
#
# Step:
#   1. Selezione disco target (con preview lsblk)
#   2. Partition + LUKS opzionale (con conferma esplicita)
#   3. Mount + nixos-generate-config
#   4. Clone repo SOLEM + nixos-install
#   5. Post-install (password root, primo solem-init)

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERRORE: solem-install-wizard richiede root."
    echo "  sudo solem-install-wizard"
    exit 1
fi

# ─── Util ────────────────────────────────────────────────────────────
red()   { printf "\033[31m%s\033[0m\n" "$*"; }
gold()  { printf "\033[38;5;179m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
dim()   { printf "\033[2m%s\033[0m\n" "$*"; }

confirm() {
    local prompt="$1"
    local ans
    read -r -p "$prompt [yes/NO]: " ans
    [[ "${ans,,}" == "yes" ]]
}

clear

cat <<'BANNER'

   ╔══════════════════════════════════════════════════════════╗
   ║                                                          ║
   ║         S O L E M   ·   Install Wizard                  ║
   ║                                                          ║
   ║         Da live USB a sistema installato in 5 step       ║
   ║                                                          ║
   ╚══════════════════════════════════════════════════════════╝

BANNER

dim "Questo wizard installa SOLEM su un disco. ATTENZIONE: il disco scelto"
dim "verrà completamente cancellato. Backup PRIMA di procedere."
echo

# ─── STEP 1: Seleziona disco ─────────────────────────────────────────
gold "──── STEP 1/5 ── SELEZIONE DISCO ──────────────────────────────────"
echo
lsblk -d -o NAME,SIZE,MODEL,TRAN | head -20
echo
read -r -p "Disco target (es. nvme0n1, sda): " DISK
DISK="/dev/${DISK}"
if [[ ! -b "$DISK" ]]; then
    red "ERRORE: $DISK non è un device block."
    exit 1
fi

DISK_SIZE=$(lsblk -bnd -o SIZE "$DISK" 2>/dev/null || echo 0)
DISK_HUMAN=$(numfmt --to=iec --suffix=B "$DISK_SIZE" 2>/dev/null || echo "?")

red "ATTENZIONE: $DISK ($DISK_HUMAN) verrà completamente cancellato."
confirm "Confermi (DIGITA esattamente 'yes' per procedere)?" || { dim "Annullato."; exit 0; }

# ─── STEP 2: LUKS encryption? ────────────────────────────────────────
echo
gold "──── STEP 2/5 ── DISK ENCRYPTION (LUKS) ───────────────────────────"
echo
dim "Crittografia full-disk con password al boot. Consigliato per laptop."
dim "Su server headless va abbinato a TPM2 unlock (config post-install)."
echo
USE_LUKS="no"
if confirm "Abilitare crittografia LUKS sul disco?"; then
    USE_LUKS="yes"
fi

# ─── STEP 3: Profile selection ───────────────────────────────────────
echo
gold "──── STEP 3/5 ── PROFILO ──────────────────────────────────────────"
cat <<'PROFILES'

   [1] minimal    — server headless, no desktop
   [2] developer  — toolchain Python/Rust/Go/Node/C++
   [3] creator    — GIMP, Blender, Kdenlive, Audacity
   [4] server     — datacenter, monitoring, mesh
   [5] desktop    — Hyprland navy + Cormorant + waybar

PROFILES
read -r -p "Profile [5]: " PROF_NUM
case "${PROF_NUM:-5}" in
    1) PROFILE="minimal"  ;;
    2) PROFILE="developer" ;;
    3) PROFILE="creator"  ;;
    4) PROFILE="server"   ;;
    *) PROFILE="desktop"  ;;
esac

# ─── STEP 4: Partition + format + install ───────────────────────────
echo
gold "──── STEP 4/5 ── PARTITION + INSTALL ──────────────────────────────"
echo
dim "Schema: /boot ESP 512MB + root ext4 (con LUKS se abilitato)"
echo
confirm "Procedere con il partitioning (ULTIMA POSSIBILITÀ DI ANNULLARE)?" || exit 0

echo
green "→ Wipe partition table..."
sgdisk --zap-all "$DISK"
sgdisk -n 1:0:+512M -t 1:ef00 -c 1:boot "$DISK"
sgdisk -n 2:0:0     -t 2:8300 -c 2:nixos "$DISK"

# Detect partition naming (sda1/nvme0n1p1)
if [[ "$DISK" =~ nvme ]]; then
    BOOT_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
else
    BOOT_PART="${DISK}1"
    ROOT_PART="${DISK}2"
fi

green "→ Format ESP (FAT32)..."
mkfs.fat -F 32 -n boot "$BOOT_PART"

if [[ "$USE_LUKS" == "yes" ]]; then
    green "→ LUKS encrypt root partition (ti chiederà passphrase)..."
    cryptsetup luksFormat --type luks2 --label nixos-crypt "$ROOT_PART"
    cryptsetup luksOpen "$ROOT_PART" cryptroot
    ROOT_FS="/dev/mapper/cryptroot"
else
    ROOT_FS="$ROOT_PART"
fi

green "→ Format root (ext4)..."
mkfs.ext4 -L nixos "$ROOT_FS"

green "→ Mount..."
mount "$ROOT_FS" /mnt
mkdir -p /mnt/boot
mount "$BOOT_PART" /mnt/boot

green "→ nixos-generate-config..."
nixos-generate-config --root /mnt

# ─── STEP 5: Clone SOLEM + install ───────────────────────────────────
echo
gold "──── STEP 5/5 ── INSTALL SOLEM ────────────────────────────────────"

green "→ Clone SOLEM repo in /mnt/etc/nixos..."
rm -rf /mnt/etc/nixos.old 2>/dev/null || true
mv /mnt/etc/nixos /mnt/etc/nixos.old 2>/dev/null || true
git clone https://github.com/rguidotti-design/solem /mnt/etc/nixos

# Copia hardware-configuration.nix generato
cp /mnt/etc/nixos.old/hardware-configuration.nix /mnt/etc/nixos/nixos/hardware-bare-metal.nix 2>/dev/null || true

# Scrivi profilo scelto
mkdir -p /mnt/etc/solem
echo "$PROFILE" > /mnt/etc/solem/profile

green "→ nixos-install (può richiedere 10-30 min)..."
echo "$DISK" > /mnt/etc/solem/install-disk
echo "$USE_LUKS" > /mnt/etc/solem/luks-enabled

# Use solem-bare config (placeholder finché solem-bare non sarà definito nel flake)
nixos-install --flake /mnt/etc/nixos#solem-vm --no-root-passwd

echo
green "→ Setta password utente 'gavio'..."
nixos-enter --root /mnt -c "passwd gavio"

echo
green "════════════════════════════════════════════════════════════════"
green "  ✓ INSTALL COMPLETO"
green "════════════════════════════════════════════════════════════════"
echo
echo "  Disco:        $DISK ($DISK_HUMAN)"
echo "  LUKS:         $USE_LUKS"
echo "  Profile:      $PROFILE"
echo "  User:         gavio (password appena settata)"
echo
echo "  Prossimi passi:"
echo "    1. umount -R /mnt"
echo "    2. reboot (togli USB)"
echo "    3. Login come 'gavio' → solem-welcome parte automatico"
echo
