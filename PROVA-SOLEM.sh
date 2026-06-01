#!/usr/bin/env bash
# PROVA-SOLEM.sh — one-command per provare SOLEM in WSL/Linux/macOS
#
# Uso:
#   bash <(curl -sSL https://raw.githubusercontent.com/rguidotti-design/solem/main/PROVA-SOLEM.sh)
#
# Oppure scaricare + eseguire:
#   curl -O https://raw.githubusercontent.com/rguidotti-design/solem/main/PROVA-SOLEM.sh
#   bash PROVA-SOLEM.sh
#
# Env opzionali:
#   SOLEM_AUTO_YES=1     auto-install Nix senza prompt
#   SOLEM_SKIP_VM=1      build solo, no run VM
#   SOLEM_REPO=URL       repo alternativo
#   SOLEM_DIR=PATH       dir alternativa (default ~/solem-source)

set -e

REPO_URL="${SOLEM_REPO:-https://github.com/rguidotti-design/solem}"
REPO_DIR="${SOLEM_DIR:-$HOME/solem-source}"

# Color helpers
cyan()   { printf "\033[36m%s\033[0m\n" "$*"; }
green()  { printf "\033[32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
red()    { printf "\033[31m%s\033[0m\n" "$*"; }
bold()   { printf "\033[1m%s\033[0m\n" "$*"; }
step()   { echo; printf "\033[1;36m▶ %s\033[0m\n" "$*"; }

banner() {
  cat <<'EOF'

╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║       SOLEM — AI-native OS · prova in 5-30 minuti            ║
║                                                              ║
║   Lo script:                                                 ║
║     1. Verifica sistema (Linux/WSL/macOS)                    ║
║     2. Installa Nix se manca (auto-yes con SOLEM_AUTO_YES=1) ║
║     3. Clone repo SOLEM                                      ║
║     4. Builda VM SOLEM (10-30 min primo run)                 ║
║     5. Lancia VM in QEMU                                     ║
║                                                              ║
║   Disk: 20GB+ · RAM: 8GB+ · Tempo: 30 min                    ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
}

check_os() {
  step "Step 1: Verifica OS"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    green "✓ macOS: OK"
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if grep -qi microsoft /proc/version 2>/dev/null; then
      green "✓ WSL2: OK (verifica che WSL sia versione 2: 'wsl -l -v')"
    else
      green "✓ Linux nativo: OK"
    fi
  else
    red "OS non supportato: $OSTYPE"
    echo "SOLEM richiede Linux, WSL2 o macOS."
    exit 1
  fi
}

check_disk() {
  step "Step 2: Verifica spazio disco"
  AVAIL_KB=$(df "$HOME" | awk 'NR==2{print $4}')
  AVAIL_GB=$(( AVAIL_KB / 1024 / 1024 ))
  echo "Spazio disponibile in HOME: ${AVAIL_GB}GB"
  if [ "$AVAIL_GB" -lt 15 ]; then
    red "⚠ Solo ${AVAIL_GB}GB liberi. Servono almeno 15GB (Nix store ~10GB)."
    echo "Libera spazio prima di continuare."
    exit 1
  fi
  green "✓ Spazio sufficiente"
}

check_nix() {
  step "Step 3: Verifica Nix"
  # Source profile se esiste
  [ -f /etc/profile.d/nix.sh ] && . /etc/profile.d/nix.sh
  [ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ] && . "$HOME/.nix-profile/etc/profile.d/nix.sh"

  if command -v nix >/dev/null 2>&1; then
    green "✓ Nix gia' installato: $(nix --version 2>&1 | head -1)"
    return 0
  fi
  yellow "Nix NON installato."

  # Non-interactive mode if SOLEM_AUTO_YES o stdin not a tty
  if [ "${SOLEM_AUTO_YES:-0}" = "1" ] || [ ! -t 0 ]; then
    ANS="y"
    cyan "Modalita' auto: installo Nix..."
  else
    printf "Installo Nix? (single-user, no sudo) [Y/n] "
    read -r ANS </dev/tty || ANS="y"
    ANS="${ANS:-y}"
  fi

  if [[ "$ANS" =~ ^[Yy] ]]; then
    cyan "Download + install Nix (5-10 min)..."
    # Determinate Systems installer (più affidabile, no daemon su WSL)
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
      sh -s -- install --no-confirm --determinate || {
        yellow "Determinate installer fallito, tento upstream..."
        sh <(curl -L https://nixos.org/nix/install) --no-daemon
      }
    # Re-source profile
    [ -f /etc/profile.d/nix.sh ] && . /etc/profile.d/nix.sh
    [ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ] && . "$HOME/.nix-profile/etc/profile.d/nix.sh"

    if ! command -v nix >/dev/null 2>&1; then
      red "Nix install fallito o richiede reload shell."
      echo
      echo "PROSSIMI PASSI MANUALI:"
      echo "  1. Chiudi terminale + riapri"
      echo "  2. Verifica: nix --version"
      echo "  3. Ri-esegui questo script"
      exit 1
    fi
    green "✓ Nix installato"
  else
    red "Nix richiesto. Abort."
    exit 1
  fi
}

enable_flakes() {
  step "Step 4: Abilita Nix flakes"
  CONF="$HOME/.config/nix/nix.conf"
  mkdir -p "$(dirname "$CONF")"
  if grep -q "experimental-features.*flakes" "$CONF" 2>/dev/null; then
    green "✓ Flakes gia' abilitati"
  else
    echo "experimental-features = nix-command flakes" >> "$CONF"
    green "✓ Flakes abilitati in $CONF"
  fi
}

clone_repo() {
  step "Step 5: Clone repo SOLEM"
  if [ -d "$REPO_DIR/.git" ]; then
    cyan "Repo esistente in $REPO_DIR — pull updates..."
    cd "$REPO_DIR"
    git fetch origin 2>&1 | tail -3 || yellow "Fetch fallito, continuo con copia locale."
    git reset --hard origin/main 2>&1 | head -3 || true
  else
    cyan "Clone $REPO_URL in $REPO_DIR ..."
    git clone --depth 1 "$REPO_URL" "$REPO_DIR"
    cd "$REPO_DIR"
  fi
  green "✓ Repo pronto: $REPO_DIR"
}

build_vm() {
  step "Step 6: Build VM SOLEM (10-30 min primo run)"
  cd "$REPO_DIR"
  # Mostra progresso
  nix build .#vm \
    --extra-experimental-features 'nix-command flakes' \
    --print-build-logs \
    --print-out-paths 2>&1 | tail -50

  if [ ! -e ./result ]; then
    red "Build fallito. Vedi log sopra."
    echo
    echo "DEBUG:"
    echo "  cd $REPO_DIR"
    echo "  nix build .#vm --show-trace"
    exit 1
  fi
  green "✓ VM buildata: $(readlink ./result)"
}

run_vm() {
  if [ "${SOLEM_SKIP_VM:-0}" = "1" ]; then
    step "Skip run VM (SOLEM_SKIP_VM=1)"
    echo "Per lanciare manualmente:"
    echo "  cd $REPO_DIR && ./result/bin/run-*-vm"
    return 0
  fi

  step "Step 7: Lancia VM SOLEM in QEMU"
  cd "$REPO_DIR"
  VMSCRIPT=$(find ./result/bin -name 'run-*-vm' 2>/dev/null | head -1)
  if [ -z "$VMSCRIPT" ] || [ ! -x "$VMSCRIPT" ]; then
    red "Script run-VM non trovato in ./result/bin/"
    ls ./result/bin/ 2>/dev/null
    exit 1
  fi

  cat <<INFO

  ┌─────────────────────────────────────────────────────────────┐
  │  SOLEM VM in avvio (Ctrl-A x per uscire da QEMU)            │
  │                                                             │
  │  Login: user=gavio  pass=gavio                              │
  │                                                             │
  │  Dentro la VM, prova:                                       │
  │    solem-welcome           wizard primo setup               │
  │    solem-localhost         dashboard endpoint locali        │
  │    solem-demo              walkthrough 10 capability        │
  │    solem-redteam run       auto-attack adesso               │
  │    solem-bench quick       benchmark performance            │
  │    poweroff                spegni VM                        │
  │                                                             │
  │  WSL note: console-only di default. Per UI grafica:         │
  │    solem.desktop.enable = true; nixos-rebuild switch        │
  │                                                             │
  └─────────────────────────────────────────────────────────────┘

INFO
  exec "$VMSCRIPT"
}

main() {
  banner
  check_os
  check_disk
  check_nix
  enable_flakes
  clone_repo
  build_vm
  run_vm
}

main "$@"
