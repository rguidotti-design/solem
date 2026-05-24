{ config, pkgs, lib, ... }:

# SOLEM AI USER — utente dedicato per processi AI (GAVIO + altri).
#
# Single responsibility: SOLO creare l'utente `gavio-ai` con privilegi
# minimi e isolato da `gavio` (utente umano). Non configura il sandbox
# (vedi solem-ai-guardrails.nix), non configura GAVIO stesso.
#
# Modello threat:
#   - L'utente umano `gavio` ha sudo (wheel), accesso al vault, dati personali.
#   - L'AI/agent gira come `gavio-ai`: NO wheel, NO sudo, NO accesso a /home/gavio.
#   - Se l'AI viene compromessa (RCE, prompt injection con tool use), il
#     blast radius è limitato a /var/lib/gavio-ai e syscall whitelist.
#
# Limiti onesti:
#   - Non protegge da kernel exploit (serve seccomp + LSM separati).
#   - Non protegge da escape del sandbox se l'AI è già root (non lo è).
#   - Su Step 0 single-tenant questa è la prima vera separazione.

let
  cfg = config.solem.aiUser;
in {
  options.solem.aiUser = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Crea l'utente di sistema `gavio-ai` per eseguire i processi AI
        isolati dall'utente umano `gavio`.
      '';
    };

    username = lib.mkOption {
      type = lib.types.str;
      default = "gavio-ai";
      description = "Nome dell'utente AI (default gavio-ai)";
    };

    uid = lib.mkOption {
      type = lib.types.int;
      default = 970;
      description = "UID fisso (range system 100-999, default 970)";
    };

    homeDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/gavio-ai";
      description = "Home directory dell'utente AI";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.${cfg.username} = {
      gid = cfg.uid;
    };

    users.users.${cfg.username} = {
      isSystemUser = true;
      uid = cfg.uid;
      group = cfg.username;
      home = cfg.homeDir;
      createHome = true;
      shell = pkgs.bash;
      description = "SOLEM AI process user (GAVIO + agent)";

      # CRITICO: NESSUN gruppo privilegiato.
      # - NO wheel (no sudo)
      # - NO docker (no container privilegiati)
      # - NO networkmanager (no modifica routing)
      # - NO video/audio (no accesso device — l'AI parla via API GAVIO)
      # - NO input (no keystroke/mouse capture)
      extraGroups = [ ];

      # Password disabilitata — l'utente NON è interattivo.
      hashedPassword = "!";
    };

    # Home dell'utente AI con permessi stretti.
    # Solo gavio-ai può leggere/scrivere. gavio NON può.
    systemd.tmpfiles.rules = [
      "d ${cfg.homeDir} 0700 ${cfg.username} ${cfg.username} -"
      "d ${cfg.homeDir}/workdir 0700 ${cfg.username} ${cfg.username} -"
      "d ${cfg.homeDir}/cache 0700 ${cfg.username} ${cfg.username} -"
      "d /var/log/solem/ai-user 0750 ${cfg.username} ${cfg.username} -"
    ];

    # CLI di ispezione (utente umano controlla cosa fa l'AI)
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "solem-ai-user";
        runtimeInputs = with pkgs; [ coreutils procps util-linux ];
        text = ''
          ACTION="''${1:-status}"
          AI_USER="${cfg.username}"
          AI_HOME="${cfg.homeDir}"

          case "$ACTION" in
            status)
              echo "── SOLEM AI User ──"
              echo "Username: $AI_USER"
              if getent passwd "$AI_USER" >/dev/null; then
                echo "Esiste: sì"
                echo "UID:    $(id -u "$AI_USER")"
                echo "Groups: $(id -Gn "$AI_USER" | tr ' ' ',')"
                echo "Home:   $AI_HOME"
                echo "Shell:  $(getent passwd "$AI_USER" | cut -d: -f7)"
              else
                echo "Esiste: NO (modulo solem.aiUser disabilitato?)"
                exit 1
              fi
              echo
              echo "── Processi attivi come $AI_USER ──"
              ps -u "$AI_USER" -o pid,comm,cmd 2>/dev/null | head -20 || echo "(nessuno)"
              ;;

            check-isolation)
              echo "── Test isolamento $AI_USER ↛ gavio ──"
              # Test 1: l'AI può leggere /home/gavio? NON deve.
              if sudo -u "$AI_USER" -- test -r /home/gavio 2>/dev/null; then
                echo "✗ FAIL: $AI_USER può leggere /home/gavio"
              else
                echo "✓ OK:  $AI_USER non può leggere /home/gavio"
              fi
              # Test 2: l'AI può sudo? NON deve.
              if sudo -u "$AI_USER" sudo -n true 2>/dev/null; then
                echo "✗ FAIL: $AI_USER ha sudo"
              else
                echo "✓ OK:  $AI_USER non ha sudo"
              fi
              # Test 3: l'AI è in wheel? NON deve.
              if id "$AI_USER" 2>/dev/null | grep -q wheel; then
                echo "✗ FAIL: $AI_USER in gruppo wheel"
              else
                echo "✓ OK:  $AI_USER NON in wheel"
              fi
              # Test 4: home propria scrivibile?
              if sudo -u "$AI_USER" -- touch "$AI_HOME/workdir/.test" 2>/dev/null; then
                sudo -u "$AI_USER" -- rm -f "$AI_HOME/workdir/.test"
                echo "✓ OK:  $AI_USER scrive in $AI_HOME/workdir"
              else
                echo "✗ FAIL: $AI_USER non scrive nella propria home"
              fi
              ;;

            ps)
              ps -u "$AI_USER" -o pid,pcpu,pmem,comm,cmd 2>/dev/null || echo "(nessun processo)"
              ;;

            help|--help|-h|*)
              cat <<'HELP'
solem-ai-user — info utente AI dedicato (gavio-ai)

  status            stato utente, groups, home, processi
  check-isolation   verifica che AI NON acceda a /home/gavio + no sudo
  ps                processi attivi come gavio-ai

Modello threat:
  gavio       → utente umano, sudo, vault, dati personali (UID 1000)
  gavio-ai    → AI process, NO sudo, NO accesso /home/gavio (UID 970)

Se l'AI viene compromessa, blast radius = /var/lib/gavio-ai.
HELP
              ;;
          esac
        '';
      })
    ];

    environment.etc."solem/ai-user.md".text = ''
      # SOLEM AI User — Separazione utente/AI

      ## Modello threat

      Step 0 single-tenant aveva un problema grosso: gavio (umano) e
      processo AI condividevano lo stesso UID. Se l'AI veniva compromessa
      (prompt injection con tool use, RCE via dipendenza), aveva:
        - accesso al vault age-encrypted
        - sudo (gruppo wheel)
        - read su tutta /home/gavio
        - capacity di parlare con qualsiasi rete

      ## Soluzione: gavio-ai

      Utente di sistema dedicato:
        - UID 970 (range system, non interattivo)
        - NO wheel, NO docker, NO networkmanager
        - Home /var/lib/gavio-ai (chmod 700)
        - shell bash MA password disabilitata
        - Login impossibile via SSH/console

      ## Verifica isolamento

      ```
      solem-ai-user check-isolation
      ```

      Deve stampare ✓ OK su:
        - gavio-ai NON legge /home/gavio
        - gavio-ai NON ha sudo
        - gavio-ai NON in wheel
        - gavio-ai scrive nella propria home

      ## Cosa NON copre questo modulo

      - Sandbox syscall → vedi solem-ai-guardrails
      - Network egress filter → vedi (prossimo) solem-ai-network
      - MAC mandatorio → vedi (prossimo) solem-ai-apparmor
      - Capability drop → systemd service config (CapabilityBoundingSet=)

      Questo modulo è SOLO la prima riga di difesa: UID separato.
      Tutto il resto è additivo.
    '';
  };
}
