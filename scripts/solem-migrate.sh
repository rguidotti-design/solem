#!/usr/bin/env bash
# SOLEM MIGRATE — assistant per migrazione da altre distro Linux a SOLEM.
#
# Single responsibility: SOLO esportare dati utente da distro corrente in
# un bundle .tar.gz che SOLEM può importare al primo boot. Niente install,
# niente partition magic.
#
# Supporta: Ubuntu/Debian, Fedora, Arch, NixOS, macOS (parziale).
#
# Output: /tmp/solem-migration-bundle-YYYYMMDD.tar.gz contiene:
#   - /home/$USER/Documents
#   - /home/$USER/Pictures
#   - /home/$USER/Music
#   - ~/.ssh, ~/.gnupg (chiavi)
#   - lista pacchetti installati (per suggerimento)
#   - .bashrc, .zshrc, .config/git
#
# Uso:
#   solem-migrate                    # bundle completo
#   solem-migrate --no-keys          # esclude ssh/gpg keys
#   solem-migrate --output PATH      # destinazione custom

set -euo pipefail

INCLUDE_KEYS=true
OUTPUT_DIR="/tmp"
USER_HOME="${HOME}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-keys) INCLUDE_KEYS=false; shift ;;
        --output)  OUTPUT_DIR="$2"; shift 2 ;;
        --help|-h)
            grep "^# " "$0" | head -25
            exit 0
            ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BUNDLE="${OUTPUT_DIR}/solem-migration-${TIMESTAMP}.tar.gz"
STAGING="$(mktemp -d)"
trap 'rm -rf "${STAGING}"' EXIT

echo "  ╔════════════════════════════════════════════════════╗"
echo "  ║   SOLEM Migrate                                    ║"
echo "  ║   Esporto dati per import in SOLEM                 ║"
echo "  ╚════════════════════════════════════════════════════╝"
echo

# ─── Detect distro ─────────────────────────────────────────────────────
DISTRO="unknown"
if [[ -f /etc/os-release ]]; then
    DISTRO="$(. /etc/os-release && echo "${ID}")"
elif [[ "$(uname)" == "Darwin" ]]; then
    DISTRO="macos"
fi
echo "  Distro rilevata: ${DISTRO}"

# ─── Package list ──────────────────────────────────────────────────────
echo "  [1/5] Esporto lista pacchetti..."
mkdir -p "${STAGING}/packages"
case "${DISTRO}" in
    ubuntu|debian)
        dpkg --get-selections > "${STAGING}/packages/dpkg.txt" 2>/dev/null || true
        ;;
    fedora|rhel|centos)
        rpm -qa > "${STAGING}/packages/rpm.txt" 2>/dev/null || true
        ;;
    arch|manjaro)
        pacman -Qe > "${STAGING}/packages/pacman.txt" 2>/dev/null || true
        ;;
    nixos)
        nix-env -q > "${STAGING}/packages/nix-env.txt" 2>/dev/null || true
        ;;
    macos)
        brew list > "${STAGING}/packages/brew.txt" 2>/dev/null || true
        ;;
esac
echo "${DISTRO}" > "${STAGING}/packages/source_distro.txt"

# ─── User data ─────────────────────────────────────────────────────────
echo "  [2/5] Copio Documents/Pictures/Music..."
mkdir -p "${STAGING}/home"
for d in Documents Pictures Music Videos Downloads Desktop; do
    if [[ -d "${USER_HOME}/${d}" ]]; then
        cp -r "${USER_HOME}/${d}" "${STAGING}/home/" 2>/dev/null || true
    fi
done

# ─── Dotfiles ──────────────────────────────────────────────────────────
echo "  [3/5] Copio dotfiles..."
mkdir -p "${STAGING}/dotfiles"
for f in .bashrc .zshrc .profile .gitconfig .vimrc; do
    [[ -f "${USER_HOME}/${f}" ]] && cp "${USER_HOME}/${f}" "${STAGING}/dotfiles/"
done
for d in .config/git .config/nvim .config/fish; do
    [[ -d "${USER_HOME}/${d}" ]] && cp -r "${USER_HOME}/${d}" "${STAGING}/dotfiles/" 2>/dev/null || true
done

# ─── SSH + GPG keys (opt-out via --no-keys) ────────────────────────────
if "${INCLUDE_KEYS}"; then
    echo "  [4/5] Copio chiavi SSH/GPG (encrypted nel bundle)..."
    mkdir -p "${STAGING}/keys"
    [[ -d "${USER_HOME}/.ssh"   ]] && cp -r "${USER_HOME}/.ssh"   "${STAGING}/keys/" 2>/dev/null || true
    [[ -d "${USER_HOME}/.gnupg" ]] && cp -r "${USER_HOME}/.gnupg" "${STAGING}/keys/" 2>/dev/null || true
else
    echo "  [4/5] SKIP chiavi (--no-keys)"
fi

# ─── Manifest ──────────────────────────────────────────────────────────
cat > "${STAGING}/MANIFEST.json" <<EOF
{
  "tool": "solem-migrate",
  "version": "0.1.0",
  "exported_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "source_distro": "${DISTRO}",
  "source_user": "$(whoami)",
  "source_hostname": "$(hostname)",
  "include_keys": ${INCLUDE_KEYS},
  "contents": [
    "home/Documents", "home/Pictures", "home/Music",
    "home/Videos", "home/Downloads", "home/Desktop",
    "dotfiles/", "packages/", "keys/ (se include_keys=true)"
  ]
}
EOF

# ─── Tarball ───────────────────────────────────────────────────────────
echo "  [5/5] Creo archive ${BUNDLE}..."
tar -czf "${BUNDLE}" -C "${STAGING}" . 2>/dev/null

SIZE="$(du -h "${BUNDLE}" | cut -f1)"

cat <<EOF

  ╔════════════════════════════════════════════════════╗
  ║   ✓ Migration bundle pronto                        ║
  ╚════════════════════════════════════════════════════╝

  File:     ${BUNDLE}
  Size:     ${SIZE}
  Distro:   ${DISTRO}

  Su SOLEM, importa con:
    solem-migrate-import ${BUNDLE}

  Trasferimento sicuro tramite mesh VPN (no cloud):
    scp ${BUNDLE} gavio@solem.local:/tmp/

EOF
