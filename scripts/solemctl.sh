#!/usr/bin/env bash
# SOLEMCTL — CLI orchestrator subcommand avanzati.
#
# Single responsibility: SOLO routing comandi nuovi (ai/search/ext/update/
# backup/crashes) → endpoint API. Complementa `solem` (Python CLI in
# solem-cli.nix) che copre status/identity/pair/panic.
#
# Uso:
#   solemctl search <query>       → universal search
#   solemctl ai <prompt>          → AI router /ai/route
#   solemctl backup               → trigger backup-restic
#   solemctl update [check|apply|rollback]
#   solemctl ext list|install|enable|disable <id>
#   solemctl profile [name]       → leggi/cambia profile
#   solemctl crashes              → ultimi crash report
#   solemctl help

set -euo pipefail

API="${SOLEM_API_URL:-http://127.0.0.1:8001}"
CMD="${1:-help}"
shift 2>/dev/null || true

call_api() {
    local method="$1"; shift
    local path="$1"; shift
    local data="''${1:-}"
    if [[ -n "${data}" ]]; then
        curl -fsS -X "${method}" "${API}${path}" -H 'Content-Type: application/json' -d "${data}"
    else
        curl -fsS -X "${method}" "${API}${path}"
    fi
}

case "${CMD}" in
    profile)
        if [[ $# -eq 0 ]]; then
            call_api GET /solem/manifest | jq -r '.profile'
        else
            echo "Cambio profile in: $1 (richiede solem-init + reboot)"
            sudo bash -c "echo '$1' > /etc/solem/profile"
        fi
        ;;

    search)
        Q="${*:-}"
        if [[ -z "${Q}" ]]; then echo "Uso: solem search <query>" >&2; exit 1; fi
        call_api POST /solem/search "{\"q\":\"${Q}\",\"limit_per_source\":5}" | jq -r '.[] | "[\(.source)] \(.title) — \(.action)"'
        ;;

    ai)
        PROMPT="${*:-}"
        if [[ -z "${PROMPT}" ]]; then echo "Uso: solem ai <prompt>" >&2; exit 1; fi
        DATA=$(jq -n --arg p "${PROMPT}" '{messages:[{role:"user",content:$p}],hint:"auto"}')
        call_api POST /solem/ai/route "${DATA}" | jq -r '"[\(.backend):\(.model)] \(.content)"'
        ;;

    backup)
        echo "Trigger backup restic..."
        sudo systemctl start solem-backup-restic.service
        sudo systemctl status solem-backup-restic.service --no-pager | head -20
        ;;

    update)
        ACTION="${1:-check}"
        case "${ACTION}" in
            check)    call_api POST /solem/updates/check    | jq . ;;
            apply)    call_api POST /solem/updates/apply    | jq . ;;
            rollback) call_api POST /solem/updates/rollback | jq . ;;
            history)  call_api GET /solem/updates/history  | jq . ;;
            status)   call_api GET /solem/updates/status   | jq . ;;
            *) echo "update: check|apply|rollback|history|status" >&2; exit 1 ;;
        esac
        ;;

    ext|extensions)
        ACTION="${1:-list}"
        ID="${2:-}"
        case "${ACTION}" in
            list)     call_api GET /solem/marketplace/installed | jq . ;;
            avail|available) call_api GET /solem/marketplace/available | jq . ;;
            install)  [[ -z "$ID" ]] && { echo "ID richiesto"; exit 1; }
                      call_api POST "/solem/marketplace/install/${ID}" | jq . ;;
            enable)   call_api POST "/solem/marketplace/enable/${ID}"  | jq . ;;
            disable)  call_api POST "/solem/marketplace/disable/${ID}" | jq . ;;
            uninstall) call_api DELETE "/solem/marketplace/uninstall/${ID}" | jq . ;;
            *) echo "ext: list|avail|install|enable|disable|uninstall" >&2; exit 1 ;;
        esac
        ;;

    crashes)
        call_api GET /solem/crashes | jq -r '.[] | "[\(.severity)] \(.detected_at) | \(.unit // "?") | \(.summary)"' | head -20
        ;;

    help|--help|-h|"")
        cat <<EOF
solemctl — comandi avanzati SOLEM (complemento del CLI 'solem')

  solemctl profile [name]    Leggi/cambia profile (minimal/developer/...)
  solemctl search <query>    Universal search (apps + files + capabilities)
  solemctl ai <prompt>       Smart AI router (Ollama/Groq)
  solemctl backup            Trigger backup encrypted ora
  solemctl update <action>   check|apply|rollback|history|status
  solemctl ext <action> [id] list|avail|install|enable|disable|uninstall
  solemctl crashes           Ultimi crash report
  solemctl help              Questo messaggio

Per status/identity/pair/panic usa il comando 'solem' (Python CLI).
Per onboarding primo boot: sudo solem-init

Env:
  SOLEM_API_URL  URL API (default: http://127.0.0.1:8001)
EOF
        ;;

    *)
        echo "Comando sconosciuto: ${CMD}. Usa 'solem help'." >&2
        exit 1
        ;;
esac
