{ config, pkgs, lib, ... }:

# SOLEM UNIFIED CLI — Step 34: `solem` come entry point Friday-style.
#
# Single responsibility: SOLO un comando `solem` che fa dispatcher verso
# i CLI specializzati dei singoli moduli (solem-redteam, solem-heal,
# solem-vault, solem-pki, solem-tor, solem-wg, ecc.).
#
# Threat coperto: nessuno NUOVO. UX. Riduce burden cognitivo per l'utente:
# invece di memorizzare 30+ comandi, ricorda solo `solem <area> <action>`.
#
# Friday-like: il comando "solem" e' la voce principale. Sub-commands
# rappresentano le aree di gestione SOLEM (security, ai, system, ...).
#
# Esempi:
#   solem status                  → status complessivo SOLEM
#   solem security status         → solem-redteam status
#   solem security run            → solem-redteam run
#   solem security heal           → solem-heal run
#   solem ai status               → status GAVIO + Ollama
#   solem ai ask "..."            → bridge a GAVIO API
#   solem net status              → solem-wg + solem-tor status
#   solem net audit               → solem-ai-audit summary
#   solem vault add               → solem-vault add
#   solem backup run              → solem-backup run
#   solem update                  → solem-update-status run

let
  cfg = config.solem.unifiedCli;
in {
  options.solem.unifiedCli = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa il comando unificato `solem` (dispatcher Friday)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "solem";
        runtimeInputs = with pkgs; [ coreutils ];
        text = ''
          # SOLEM unified CLI — Friday-like dispatcher
          AREA="''${1:-status}"
          shift || true
          ACTION="''${1:-status}"
          shift || true

          # Helper: chiama subcommand se esiste, altrimenti messaggio fallback
          dispatch() {
            local CMD="$1"
            shift
            if command -v "$CMD" >/dev/null 2>&1; then
              "$CMD" "$@"
            else
              echo "Comando '$CMD' non disponibile (modulo SOLEM non abilitato?)" >&2
              return 1
            fi
          }

          case "$AREA" in
            # ─── Status aggregato (Friday HUD) ───────────────────────
            status|st)
              cat <<'BANNER'
              ╔══════════════════════════════════════════════════╗
              ║          SOLEM — AI-native OS                    ║
              ║          Friday Mode active                      ║
              ╚══════════════════════════════════════════════════╝
BANNER
              echo
              echo "── Sistema ──"
              echo "  Host:    $(hostname)"
              echo "  Uptime:  $(uptime -p 2>/dev/null || uptime)"
              echo "  Kernel:  $(uname -r)"
              echo "  Load:    $(cut -d' ' -f1-3 /proc/loadavg)"
              echo
              echo "── Security stack (ultima verifica) ──"
              if [ -f /var/log/solem/redteam/LATEST.md ]; then
                head -10 /var/log/solem/redteam/LATEST.md
              else
                echo "  (no redteam report; esegui: solem security run)"
              fi
              echo
              echo "── Quick checks ──"
              for marker in /var/lib/solem/CANARY_TRIPPED /var/lib/solem/MODEL_TAMPERED /var/lib/solem/IDS_ALERT; do
                if [ -f "$marker" ]; then
                  echo "  ⚠ $marker presente!"
                fi
              done
              echo
              echo "Usage: solem <area> <action>"
              echo "Aree: security ai net vault backup update help"
              ;;

            # ─── Security area ───────────────────────────────────────
            security|sec)
              case "$ACTION" in
                status|st) dispatch solem-redteam status ;;
                run)       dispatch solem-redteam run ;;
                buchi)     dispatch solem-redteam buchi ;;
                heal)      dispatch solem-heal run ;;
                audit)     dispatch solem-ai-audit summary ;;
                tamper)    dispatch solem-ai-audit tamper ;;
                ids)       dispatch solem-ids status ;;
                ids-alerts) dispatch solem-ids critical ;;
                apparmor)  dispatch solem-apparmor status ;;
                kernel)    dispatch solem-kernel-check ;;
                pki)       dispatch solem-pki status ;;
                fido)      dispatch solem-fido2 status ;;
                canary)    dispatch solem-canary status ;;
                *) cat <<HELP
solem security <action>:
  status        ultimo redteam summary
  run           esegui redteam ADESSO
  buchi         elenco buchi trovati
  heal          applica fix safe automatici
  audit         eventi auditd ultima ora
  tamper        modifiche file critici
  ids           Suricata IDS status
  ids-alerts    alert critical
  apparmor      profili LSM
  kernel        kernel hardening sysctl
  pki           cert SOLEM emessi
  fido          status FIDO2 MFA
  canary        honey tokens
HELP
                ;;
              esac
              ;;

            # ─── AI area ─────────────────────────────────────────────
            ai|gavio)
              case "$ACTION" in
                status)
                  echo "── GAVIO ──"
                  systemctl is-active gavio.service 2>/dev/null || echo "(gavio.service non attivo)"
                  echo
                  echo "── Ollama ──"
                  systemctl is-active ollama.service 2>/dev/null || echo "(ollama non attivo)"
                  echo
                  echo "── Prompt Filter (Step 21) ──"
                  systemctl is-active solem-prompt-filter.service 2>/dev/null || echo "(filter non attivo)"
                  ;;
                ask)
                  Q="''${1:-?}"
                  echo "Bridge GAVIO API: $Q"
                  curl -s -X POST "http://127.0.0.1:8001/api/chat" \
                    -H "Content-Type: application/json" \
                    -d "{\"message\":\"$Q\"}" 2>/dev/null || echo "(GAVIO non disponibile via filter:8001)"
                  ;;
                model-check) dispatch solem-model-integrity status ;;
                guard)       dispatch solem-guard status ;;
                user)        dispatch solem-ai-user status ;;
                *) cat <<HELP
solem ai <action>:
  status        gavio + ollama + prompt filter
  ask <q>       bridge query a GAVIO via prompt filter
  model-check   integrita' modelli LLM
  guard         sandbox status
  user          isolamento gavio-ai
HELP
                ;;
              esac
              ;;

            # ─── Network area ────────────────────────────────────────
            net|network)
              case "$ACTION" in
                status)
                  dispatch solem-wg status || true
                  echo
                  dispatch solem-tor status || true
                  echo
                  dispatch solem-ai-net status || true
                  ;;
                wg|wireguard) shift || true; dispatch solem-wg "$@" ;;
                tor|onion)    shift || true; dispatch solem-tor "$@" ;;
                ai-net)       dispatch solem-ai-net status ;;
                audit)        dispatch solem-net-audit summary ;;
                dns)          dispatch solem-ai-dns status ;;
                *) cat <<HELP
solem net <action>:
  status        WireGuard + Tor + AI nft status
  wg <action>   WireGuard mesh management
  tor <action>  Tor onion service
  ai-net        nftables egress filter
  audit         connect outbound log
  dns           DNS allowlist
HELP
                ;;
              esac
              ;;

            # ─── Vault area ──────────────────────────────────────────
            vault)
              dispatch solem-vault "$ACTION" "$@"
              ;;

            # ─── Backup area ─────────────────────────────────────────
            backup)
              case "$ACTION" in
                status|run|init|list|restore|check) dispatch solem-backup "$ACTION" "$@" ;;
                *) dispatch solem-backup help ;;
              esac
              ;;

            # ─── Update area ─────────────────────────────────────────
            update|upgrade)
              dispatch solem-update-status "$ACTION" "$@"
              ;;

            # ─── USB / Thunderbolt / Hardware ────────────────────────
            usb)
              dispatch solem-usb-guard "$ACTION" "$@"
              ;;
            tb|thunderbolt)
              dispatch solem-thunderbolt "$ACTION" "$@"
              ;;

            # ─── HPC area ────────────────────────────────────────────
            hpc)
              dispatch solem-hpc "$ACTION" "$@"
              ;;

            # ─── Help ─────────────────────────────────────────────────
            help|--help|-h|*)
              cat <<'HELP'
              ╔══════════════════════════════════════════════════╗
              ║       SOLEM — Friday-style unified CLI           ║
              ╚══════════════════════════════════════════════════╝

  solem status              dashboard sistema + security recente

  solem security <action>   gestione 27 layer security
    ├─ status, run, buchi, heal, audit, tamper
    └─ ids, apparmor, kernel, pki, fido, canary

  solem ai <action>         GAVIO + Ollama + prompt filter
    ├─ status, ask <q>, model-check, guard, user

  solem net <action>        WireGuard + Tor + nft
    ├─ status, wg, tor, ai-net, audit, dns

  solem vault <action>      secret manager age-encrypted
  solem backup <action>     borg + age + offsite
  solem update <action>     auto-update NixOS
  solem usb <action>        USBGuard
  solem tb <action>         Thunderbolt + IOMMU
  solem hpc <action>        SLURM HPC toolkit

Friday-like: "solem ask" → bridge a GAVIO per query naturali.
Esempi:
  solem ai ask "stato sistema?"
  solem security buchi
  solem net wg new-peer my-phone
HELP
              ;;
          esac
        '';
      })
    ];

    environment.etc."solem/unified-cli.md".text = ''
      # SOLEM Unified CLI (Step 34)

      Entry point unico `solem` che fa dispatcher verso CLI specializzati
      di tutti i moduli SOLEM. Riduce burden cognitivo: ricordi solo
      "solem <area> <action>".

      ## Aree esposte
      - **status** — dashboard sistema + security recente
      - **security** — 27 layer security gestione
      - **ai** — GAVIO + Ollama + prompt filter
      - **net** — WireGuard + Tor + nft
      - **vault** — secret manager
      - **backup** — borg + age + offsite
      - **update** — auto-update NixOS
      - **usb / tb** — hardware control
      - **hpc** — SLURM toolkit

      ## Friday-mode integration
      `solem ai ask "<query>"` fa bridge HTTP a GAVIO via prompt filter (Step 21).
      Quello e' il "voice di Friday" — comando naturale, risposta intelligente.

      ## Limiti onesti
      - Dispatcher solo: ogni sub-command e' un CLI separato gia' esistente.
        Se modulo X non abilitato, comando relativo dice "non disponibile".
      - Help context-sensitive: solem <area> help mostra azioni di quell'area.
      - No tab completion (TODO Step 34b: bash/zsh completion script).
    '';
  };
}
