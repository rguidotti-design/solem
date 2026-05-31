#!/usr/bin/env bash
# PROVA-SOLEM.sh — one-command per provare SOLEM in WSL/Linux
#
# Uso:
#   curl -sSL https://raw.githubusercontent.com/rguidotti-design/solem/main/PROVA-SOLEM.sh | bash
#
# Oppure scarica + esegui:
#   wget https://raw.githubusercontent.com/rguidotti-design/solem/main/PROVA-SOLEM.sh
#   chmod +x PROVA-SOLEM.sh
#   ./PROVA-SOLEM.sh

set -e

REPO_URL="${SOLEM_REPO:-https://github.com/rguidotti-design/solem}"
REPO_DIR="${SOLEM_DIR:-$HOME/solem-source}"

cyan()   { printf "\033[36m%s\033[0m\n" "$*"; }
green()  { printf "\033[32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
red()    { printf "\033[31m%s\033[0m\n" "$*"; }
bold()   { printf "\033[1m%s\033[0m\n" "$*"; }

banner() {
  cat <<'EOF'
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║       SOLEM — AI-native OS · prova in 5 minuti               ║
║                                                              ║
║   Questo script:                                             ║
║     1. Verifica/installa Nix (se manca)                      ║
║     2. Clone repo SOLEM                                      ║
║     3. Builda VM SOLEM (~10-30min primo run)                 ║
║     4. Lancia VM in QEMU                                     ║
║                                                              ║
║   Servono: 8GB RAM, 20GB disco, 30min                        ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
}

check_os() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    bold "macOS: OK (Nix supportato)"
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    bold "Linux: OK"
  elif grep -qi microsoft /proc/version 2>/dev/null; then
    bold "WSL: OK"
  else
    red "OS non supportato: $OSTYPE"
    echo "SOLEM richiede Linux, WSL2, o macOS."
    exit 1
  fi
}

check_nix() {
  if command -v nix >/dev/null 2>&1; then
    green "✓ Nix gia' installato: $(nix --version)"
    return 0
  fi
  yellow "Nix non installato."
  read -p "Installo Nix ora? (richiede sudo) [y/N] " ANS
  if [[ "$ANS" =~ ^[Yy] ]]; then
    cyan "Installazione Nix (single-user)..."
    curl --proto '=https' --tlsv1.2 -sSf -L https://nixos.org/nix/install | sh -s -- --daemon
    # Reload env
    if [ -f /etc/profile.d/nix.sh ]; then
      . /etc/profile.d/nix.sh
    elif [ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
      . "$HOME/.nix-profile/etc/profile.d/nix.sh"
    fi
    if ! command -v nix >/dev/null 2>&1; then
      red "Nix install fallito o richiede reload shell."
      echo "Esegui: source /etc/profile.d/nix.sh"
      echo "Oppure: source ~/.nix-profile/etc/profile.d/nix.sh"
      echo "Poi ri-esegui questo script."
      exit 1
    fi
  else
    red "Nix richiesto. Abort."
    exit 1
  fi
}

enable_flakes() {
  if nix --extra-experimental-features 'nix-command flakes' eval --expr 'true' 2>/dev/null | grep -q true; then
    green "✓ Nix flakes OK"
    return 0
  fi
  cyan "Abilito flakes (richiede edit ~/.config/nix/nix.conf)..."
  mkdir -p "$HOME/.config/nix"
  echo "experimental-features = nix-command flakes" >> "$HOME/.config/nix/nix.conf"
  green "✓ Flakes abilitati"
}

clone_repo() {
  if [ -d "$REPO_DIR/.git" ]; then
    cyan "Repo esistente in $REPO_DIR — pull updates..."
    cd "$REPO_DIR"
    git pull --rebase || yellow "Pull fallito, continuo con copia locale."
  else
    cyan "Clone repo SOLEM in $REPO_DIR ..."
    git clone "$REPO_URL" "$REPO_DIR"
    cd "$REPO_DIR"
  fi
  green "✓ Repo pronto: $REPO_DIR"
}

build_vm() {
  cyan "Build VM SOLEM (10-30 min primo run)..."
  cd "$REPO_DIR"
  nix build .#vm --print-out-paths
  if [ ! -e ./result ]; then
    red "Build fallito. Vedi log sopra."
    exit 1
  fi
  green "✓ VM buildata: $(readlink ./result)"
}

run_vm() {
  cd "$REPO_DIR"
  VMSCRIPT="./result/bin/run-solem-vm-vm"
  if [ ! -x "$VMSCRIPT" ]; then
    # Auto-discover il nome reale
    VMSCRIPT=$(find ./result/bin -name 'run-*-vm' | head -1)
  fi
  if [ ! -x "$VMSCRIPT" ]; then
    red "Script run-VM non trovato in ./result/bin/"
    ls ./result/bin/
    exit 1
  fi
  cat <<INFO

  ┌─────────────────────────────────────────────────────────────┐
  │  SOLEM VM in avvio                                          │
  │                                                             │
  │  Login: user=gavio  pass=gavio                              │
  │                                                             │
  │  Dentro la VM, prova:                                       │
  │    solem-welcome           wizard primo setup               │
  │    solem-localhost         dashboard endpoint locali        │
  │    solem-demo              walkthrough 10 capability        │
  │    solem-redteam run       auto-attack adesso               │
  │    solem-bench quick       benchmark performance            │
  │                                                             │
  │  Per uscire: poweroff (dentro VM) o Ctrl-A x (QEMU)         │
  │                                                             │
  └─────────────────────────────────────────────────────────────┘

INFO
  exec "$VMSCRIPT"
}

main() {
  banner
  check_os
  check_nix
  enable_flakes
  clone_repo
  build_vm
  run_vm
}

main "$@"
