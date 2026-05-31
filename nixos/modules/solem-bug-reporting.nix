{ config, pkgs, lib, ... }:

# SOLEM BUG REPORTING — Step 52: opt-in privacy-first crash report.
#
# Single responsibility: SOLO CLI per generare bug report sanitizzato
# (no PII, no hostname, no UUID persistente) + apri issue GitHub
# manuale.
#
# Filosofia opt-in extreme:
#   - NIENTE invio automatico
#   - NIENTE telemetria background
#   - UTENTE decide cosa includere
#   - Anonymization automatica: rimuove hostname, IP, username, paths utente

let
  cfg = config.solem.bugReporting;
in {
  options.solem.bugReporting = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Installa solem-bug CLI (generazione report sanitizzato).";
    };

    issuesUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://github.com/rguidotti-design/solem/issues/new";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      (pkgs.writeShellApplication {
        name = "solem-bug";
        runtimeInputs = with pkgs; [ coreutils systemd xdg-utils gawk gnused jq ];
        text = ''
          ACTION="''${1:-collect}"
          OUT="/tmp/solem-bug-$(date +%s).md"

          sanitize() {
            # Rimuove username, hostname, IP, MAC, UUID persistente
            sed -E \
              -e "s/$(whoami)/<USER>/g" \
              -e "s/$(hostname)/<HOST>/g" \
              -e "s/\\b([0-9]{1,3}\\.){3}[0-9]{1,3}\\b/<IP>/g" \
              -e "s/\\b([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\\b/<MAC>/g" \
              -e "s|/home/[^/ ]*|<HOME>|g" \
              -e "s/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/<UUID>/g"
          }

          case "$ACTION" in
            collect)
              echo "── Generazione bug report sanitizzato ──"
              echo "Tutto e' SCRITTO LOCALMENTE in $OUT."
              echo "Niente invio automatico. Tu decidi se condividere."
              echo

              {
                echo "# SOLEM Bug Report"
                echo
                echo "**Data**: $(date -Iseconds | sed 's/T.*//')"
                echo
                echo "## Descrivi il bug"
                echo "(scrivi qui cosa e' successo, cosa ti aspettavi)"
                echo
                echo "<!-- DA COMPILARE -->"
                echo
                echo "## Per riprodurre"
                echo "1. Step 1"
                echo "2. Step 2"
                echo "3. Errore visto"
                echo
                echo "## Ambiente"
                echo "\`\`\`"
                echo "OS: SOLEM $(cat /etc/os-release 2>/dev/null | grep VERSION_ID || echo '?')"
                echo "Kernel: $(uname -r)"
                echo "Architecture: $(uname -m)"
                echo "Last NixOS gen: $(sudo nix-env --list-generations --profile /nix/var/nix/profiles/system 2>/dev/null | tail -1 || echo '?')"
                echo "\`\`\`"
                echo
                echo "## Last journal errors (sanitized)"
                echo "\`\`\`"
                journalctl --since "10 minutes ago" -p err --no-pager 2>/dev/null | tail -30 | sanitize
                echo "\`\`\`"
                echo
                echo "## Last failed units (sanitized)"
                echo "\`\`\`"
                systemctl list-units --state=failed --no-pager 2>/dev/null | sanitize
                echo "\`\`\`"
                echo
                echo "## SOLEM red-team report (se presente)"
                LATEST_RT=$(ls -t /var/log/solem/redteam/*.json 2>/dev/null | head -1)
                if [ -n "$LATEST_RT" ]; then
                  echo "\`\`\`json"
                  jq '.summary' "$LATEST_RT" 2>/dev/null | sanitize
                  echo "\`\`\`"
                fi
                echo
                echo "---"
                echo "Generato da: solem-bug collect"
                echo "Sanitizzato: hostname/IP/MAC/UUID/path-home rimossi"
              } > "$OUT"

              echo
              echo "✓ Report generato: $OUT"
              echo
              echo "PROSSIMI PASSI:"
              echo "  1. Modifica $OUT — compila sezione 'Descrivi il bug'"
              echo "  2. ${cfg.issuesUrl}"
              echo "  3. Copia/incolla contenuto $OUT come nuova issue"
              echo
              echo "Per aprire link issue browser:"
              echo "  solem-bug open"
              echo "Per ispezionare il report:"
              echo "  cat $OUT"
              ;;

            open)
              xdg-open "${cfg.issuesUrl}" 2>/dev/null || echo "Vai a: ${cfg.issuesUrl}"
              ;;

            help|--help|-h|*)
              cat <<'HELP'
solem-bug — generazione bug report sanitizzato (NO telemetry)

  collect   genera report in /tmp/solem-bug-<ts>.md (sanitizzato)
  open      apre browser su issues GitHub (per copia/incolla)

Filosofia:
  - ZERO telemetria automatica
  - ZERO invio background
  - Tu DECIDI cosa condividere
  - Sanitization automatica: hostname/IP/MAC/UUID/path-home rimossi

Workflow:
  1. solem-bug collect           genera report locale
  2. cat /tmp/solem-bug-*.md     verifica contenuto
  3. solem-bug open              apri GitHub issues
  4. Copia/incolla report come nuova issue
HELP
              ;;
          esac
        '';
      })
    ];

    environment.etc."solem/bug-reporting.md".text = ''
      # SOLEM Bug Reporting (Step 52)

      Privacy-first opt-in: nessuna telemetria automatica.

      ## Filosofia
      - ZERO invio automatico crash / metriche / usage
      - ZERO daemon background
      - ZERO UUID persistente assegnato all'utente
      - Bug report = SOLO se utente esegue `solem-bug collect`
      - Sanitization automatica: hostname, IP, MAC, UUID, path /home/X
        sostituiti con placeholder

      ## Sanitization rules
      ```
      <USER>   <- $(whoami)
      <HOST>   <- $(hostname)
      <IP>     <- IPv4 pattern x.x.x.x
      <MAC>    <- xx:xx:xx:xx:xx:xx
      <HOME>   <- /home/anything
      <UUID>   <- 8-4-4-4-12 hex pattern
      ```

      ## Cosa NON e' incluso nel report
      - Network config (Wi-Fi SSID, WireGuard keys)
      - Account info (email, profile)
      - File contents (solo file paths sanitizzati)
      - Browser history / app data
      - GAVIO conversation log
      - Vault content

      ## Cosa SI include (sanitizzato)
      - OS version + kernel + arch
      - Ultimi 30 errori journal (priorita' >= err)
      - Failed systemd units
      - SOLEM red-team summary (counter buchi, non dettagli)
      - Sezione user-editable "Descrivi il bug"

      ## Limiti onesti
      - Sanitization e' regex-based: pattern non standard (es. custom
        ipv6) possono leakare. Sempre RILEGGI prima di inviare.
      - Issue su GitHub e' PUBBLICA: anche se sanitizzato, considera
        cosa scrivi nella descrizione bug.
      - Per bug security-sensitive: NON usare GitHub issue, usa email
        sicura (security@solem.so se esiste).
    '';
  };
}
