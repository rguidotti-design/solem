#!/usr/bin/env bash
# SOLEM INIT — wizard onboarding primo boot.
#
# Single responsibility: SOLO raccolta dati iniziali utente (identità,
# AI primaria, profilo, lingua). Scrive in /etc/solem/onboarding.json
# che solem-api legge al boot per popolare L1 Identity.
#
# Non installa nulla, non configura servizi: questo è solo il dialogo.
# Tutto il resto è già declarative in nixos/.
#
# Uso:
#   sudo solem-init               # full wizard
#   sudo solem-init --skip-checks # bypass check requisiti
#   sudo solem-init --json FILE   # batch mode, no prompts

set -euo pipefail

CONF_DIR="/etc/solem"
ONBOARDING_FILE="${CONF_DIR}/onboarding.json"
PROFILE_FILE="${CONF_DIR}/profile"

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERRORE: solem-init richiede root (per scrivere /etc/solem/)." >&2
    exit 1
fi

mkdir -p "${CONF_DIR}"
chmod 755 "${CONF_DIR}"

# ─── Banner ────────────────────────────────────────────────────────────
cat <<'BANNER'

   ┌───────────────────────────────────────────────┐
   │                                               │
   │             S O L E M                         │
   │             AI-native OS                      │
   │                                               │
   └───────────────────────────────────────────────┘

   Benvenuto. Questo wizard ti farà 6 domande per
   configurare il sistema. Tempo stimato: 2 minuti.

BANNER

# ─── Q1. Nome ──────────────────────────────────────────────────────────
read -r -p "  [1/6] Come ti chiami? " NAME
NAME="${NAME:-Utente}"

# ─── Q2. Email ─────────────────────────────────────────────────────────
read -r -p "  [2/6] Email (per identity, mai inviata fuori): " EMAIL
EMAIL="${EMAIL:-utente@solem.local}"

# ─── Q3. AI primaria ───────────────────────────────────────────────────
echo "  [3/6] Quale AI vuoi come assistente primario?"
echo "        1) GAVIO (default — AI personale gerarchica)"
echo "        2) Nessuna (uso SOLEM raw)"
echo "        3) Altra (config manuale dopo)"
read -r -p "        Scelta [1]: " AI_CHOICE
AI_CHOICE="${AI_CHOICE:-1}"
case "${AI_CHOICE}" in
    1) PRIMARY_AI="gavio" ;;
    2) PRIMARY_AI="none"  ;;
    *) PRIMARY_AI="other" ;;
esac

# ─── Q4. Profilo ───────────────────────────────────────────────────────
echo "  [4/6] Profilo d'uso (definisce moduli attivi):"
echo "        1) minimal   — solo essenziali"
echo "        2) developer — vscode, docker, git, dev tools"
echo "        3) creator   — gimp, blender, audacity, kdenlive"
echo "        4) server    — caddy, monitoring, no GUI"
echo "        5) desktop   — full desktop con GUI"
read -r -p "        Scelta [1]: " PROF_CHOICE
PROF_CHOICE="${PROF_CHOICE:-1}"
case "${PROF_CHOICE}" in
    1) PROFILE="minimal"  ;;
    2) PROFILE="developer" ;;
    3) PROFILE="creator"  ;;
    4) PROFILE="server"   ;;
    5) PROFILE="desktop"  ;;
    *) PROFILE="minimal"  ;;
esac

# ─── Q5. Lingua ────────────────────────────────────────────────────────
read -r -p "  [5/6] Lingua principale (it/en/es/fr/de) [it]: " LANG_CODE
LANG_CODE="${LANG_CODE:-it}"

# ─── Q6. Zero-trust ─────────────────────────────────────────────────────
read -r -p "  [6/6] Abilitare zero-trust + mesh VPN? (y/N): " ZT
ZT_ENABLED="false"
[[ "${ZT,,}" =~ ^y ]] && ZT_ENABLED="true"

# ─── Scrittura file ─────────────────────────────────────────────────────
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "${ONBOARDING_FILE}" <<EOF
{
  "completed_at": "${TIMESTAMP}",
  "user": {
    "name": "${NAME}",
    "email": "${EMAIL}",
    "language": "${LANG_CODE}"
  },
  "primary_ai": "${PRIMARY_AI}",
  "profile": "${PROFILE}",
  "zero_trust_enabled": ${ZT_ENABLED},
  "wizard_version": "0.1.0"
}
EOF

echo "${PROFILE}" > "${PROFILE_FILE}"

chmod 644 "${ONBOARDING_FILE}" "${PROFILE_FILE}"

# ─── Riepilogo ─────────────────────────────────────────────────────────
cat <<EOF

   ┌───────────────────────────────────────────────┐
   │   ✓ Configurazione salvata                    │
   └───────────────────────────────────────────────┘

   Nome:      ${NAME}
   Email:     ${EMAIL}
   AI:        ${PRIMARY_AI}
   Profilo:   ${PROFILE}
   Lingua:    ${LANG_CODE}
   ZeroTrust: ${ZT_ENABLED}

   File:      ${ONBOARDING_FILE}

   Prossimi passi:
     1. systemctl restart solem-api
     2. Apri http://localhost:8001
     3. (se hai scelto GAVIO) systemctl enable --now gavio

EOF

exit 0
