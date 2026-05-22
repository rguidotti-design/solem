#!/usr/bin/env bash
# SOLEM WELCOME — esperienza first-boot completa per utente non-tech.
#
# Single responsibility: SOLO orchestrare il primo accesso. Mostra banner,
# parla via TTS se disponibile, lancia solem-init, lascia l'utente in una
# bash con suggerimenti.
#
# Eseguito automaticamente al primo login se /etc/solem/onboarding.json
# non esiste (vedi solem-init.nix → bashrc hook).

set -uo pipefail

CONF_DIR="/etc/solem"
ONBOARDING_FILE="${CONF_DIR}/onboarding.json"

# Se già fatto, esci silenzioso
if [[ -f "${ONBOARDING_FILE}" ]]; then
    exit 0
fi

# ─── Helpers TTS (opzionale: piper/espeak-ng) ──────────────────────────
say() {
    local text="$1"
    # Stampa sempre
    echo
    echo "   $text"
    echo
    # TTS se disponibile (italiano)
    if command -v piper >/dev/null 2>&1 && [[ -n "${PIPER_MODEL_PATH:-}" && -f "${PIPER_MODEL_PATH}" ]]; then
        echo "$text" | piper --model "${PIPER_MODEL_PATH}" --output-raw 2>/dev/null \
            | aplay -r 22050 -f S16_LE -t raw 2>/dev/null &
    elif command -v espeak-ng >/dev/null 2>&1; then
        espeak-ng -v it -s 160 "$text" >/dev/null 2>&1 &
    fi
}

clear

cat <<'BANNER'

   ╔═══════════════════════════════════════════════════════╗
   ║                                                       ║
   ║                  S    O    L    E    M                ║
   ║                                                       ║
   ║                     AI-native OS                      ║
   ║                                                       ║
   ╚═══════════════════════════════════════════════════════╝

BANNER

say "Benvenuto in SOLEM. Sono il sistema operativo che ospita la tua AI personale."

sleep 1

cat <<'INFO'
   Questa è la prima volta che usi questo sistema.
   Ti farò 6 domande per configurarlo (tempo: 2 minuti).

   Cosa imparerai dopo:
     • come parlare con la tua AI (GAVIO)
     • come aggiungere altri tuoi dispositivi
     • come installare app
     • come fare backup

INFO

say "Sei pronto? Premi Invio per cominciare, o digita 'salta' per saltare il wizard."

read -r ans
if [[ "${ans,,}" =~ ^salta|skip|no ]]; then
    cat <<'SKIP'
   Saltato. Quando vuoi:
     sudo solem-init           → riprende il wizard
     solem status              → vedi lo stato del sistema
     solem-doc                 → documentazione
SKIP
    exit 0
fi

# ─── Lancia solem-init (sudo se non root) ──────────────────────────────
if [[ ${EUID} -ne 0 ]]; then
    say "Mi serve sudo per scrivere la configurazione di sistema."
    sudo solem-init
else
    solem-init
fi

# ─── Post-init suggerimenti ────────────────────────────────────────────
if [[ -f "${ONBOARDING_FILE}" ]]; then
    cat <<'NEXT'

   Setup completato! Prossime cose da provare:

   ─── Parla con GAVIO ───────────────────────────────────
   $ solem ai "ciao GAVIO, come stai?"

   ─── Stato sistema ─────────────────────────────────────
   $ solem status

   ─── Apri la dashboard browser ──────────────────────────
   $ xdg-open http://localhost:8001

   ─── Aggiungi un altro tuo dispositivo (Pi, smartphone) ─
   $ solem pair
   poi sull'altro device: solem-join --pin XXXX

   ─── Manuale completo ──────────────────────────────────
   $ solem-doc          → apre USER-GUIDE.md
   $ solem help         → comandi disponibili

NEXT
    say "Tutto pronto. Puoi cominciare a usare il sistema."
fi
