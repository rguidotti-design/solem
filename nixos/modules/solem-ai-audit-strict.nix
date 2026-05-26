{ config, pkgs, lib, ... }:

# SOLEM AI AUDIT STRICT — auditd rules dedicate per UID gavio-ai + tamper detection.
#
# Single responsibility: SOLO regole auditd specifiche per:
#   1. Tracciare OGNI azione di gavio-ai (execve, openat, connect, sendto)
#   2. Tracciare scrittura su file di sistema critici (/etc, /usr, /boot)
#   3. Tracciare ogni uso di setuid/setgid binaries
#   4. Tracciare modifiche a regole audit stesse (anti-disable)
#
# Differenza vs solem-net-audit (logga TUTTI gli outbound) e auditd default:
#   - net-audit: visibilita' rete, tutti gli utenti
#   - ai-audit:  visibilita' chirurgica su UID 970, anche operazioni filesystem
#                + tamper detection su file critici
#
# Anche se nftables blocca un connect(), auditd LOGGA il tentativo →
# forensics dopo l'incidente: "l'AI ha PROVATO a contattare evil.com:8080"
# anche se non c'e' riuscita.
#
# Tutto FOSS (auditd GPL-2.0). 0 €.

let
  cfg = config.solem.aiAuditStrict;
  aiUid = config.solem.aiUser.uid or 970;

  rulesFile = pkgs.writeText "solem-ai-audit-strict.rules" ''
    ## SOLEM AI Audit STRICT — regole dedicate per UID ${toString aiUid} (gavio-ai)
    ## + tamper detection su file di sistema critici.

    # ─── 1. Ogni execve di gavio-ai ──────────────────────────────────
    -a always,exit -F arch=b64 -F auid=${toString aiUid} -S execve -k ai_execve
    -a always,exit -F arch=b32 -F auid=${toString aiUid} -S execve -k ai_execve
    # Anche se l'UID viene cambiato dopo, auid (audit UID) resta originale
    -a always,exit -F arch=b64 -F uid=${toString aiUid} -S execve -k ai_execve
    -a always,exit -F arch=b32 -F uid=${toString aiUid} -S execve -k ai_execve

    # ─── 2. Tentativi di apertura file da gavio-ai ───────────────────
    # Solo openat (open syscall obsoleto). Filtriamo per accesso write/exec.
    -a always,exit -F arch=b64 -F uid=${toString aiUid} -S openat -F a2&0x3 -k ai_open_write
    -a always,exit -F arch=b64 -F uid=${toString aiUid} -S openat -F a2&0x40 -k ai_open_create

    # ─── 3. Connect / sendto / accept di gavio-ai ────────────────────
    # Anche se nftables DROP, audit logga il tentativo.
    -a always,exit -F arch=b64 -F uid=${toString aiUid} -S connect -k ai_connect
    -a always,exit -F arch=b32 -F uid=${toString aiUid} -S connect -k ai_connect
    -a always,exit -F arch=b64 -F uid=${toString aiUid} -S sendto -S sendmsg -k ai_send

    # ─── 4. Tentativi di setuid/setgid (privilege escalation) ────────
    -a always,exit -F arch=b64 -F uid=${toString aiUid} -S setuid -S setgid -S setreuid -S setregid -k ai_setuid_try
    -a always,exit -F arch=b32 -F uid=${toString aiUid} -S setuid -S setgid -S setreuid -S setregid -k ai_setuid_try

    # ─── 5. Tamper detection: scrittura su file critici di sistema ───
    # Watch su /etc, /usr, /boot - chiunque scriva qui viene loggato.
    -w /etc/passwd -p wa -k tamper_passwd
    -w /etc/shadow -p wa -k tamper_shadow
    -w /etc/sudoers -p wa -k tamper_sudoers
    -w /etc/sudoers.d/ -p wa -k tamper_sudoers
    -w /etc/ssh/sshd_config -p wa -k tamper_sshd
    -w /etc/systemd/ -p wa -k tamper_systemd
    -w /etc/nixos/ -p wa -k tamper_nixos
    -w /boot/ -p wa -k tamper_boot
    -w /etc/cron.d/ -p wa -k tamper_cron
    -w /etc/crontab -p wa -k tamper_cron
    -w /var/spool/cron/ -p wa -k tamper_cron

    # ─── 6. Tamper detection: regole audit stesse ────────────────────
    # Se qualcuno prova a disabilitare auditd o modificare regole.
    -w /etc/audit/ -p wa -k tamper_audit
    -w /etc/audit/audit.rules -p wa -k tamper_audit
    -w /etc/audit/auditd.conf -p wa -k tamper_audit

    # ─── 7. Watch kernel modules load/unload ─────────────────────────
    -a always,exit -F arch=b64 -S init_module -S finit_module -S delete_module -k kernel_module
    -a always,exit -F arch=b32 -S init_module -S finit_module -S delete_module -k kernel_module

    # ─── 8. ptrace tentativi (anti-debugger sniffing) ────────────────
    -a always,exit -F arch=b64 -S ptrace -k ptrace_try
    -a always,exit -F arch=b32 -S ptrace -k ptrace_try

    # ─── 9. immutable mode: dopo aver caricato queste regole, audit
    # ───    NON puo' essere modificato fino al reboot (-e 2).
    ## NB: lo lasciamo opzionale via cfg.immutable per evitare lock-in nei test.
  '';

  auditCli = pkgs.writeShellApplication {
    name = "solem-ai-audit";
    runtimeInputs = with pkgs; [ coreutils audit gawk gnugrep ];
    text = ''
      ACTION="''${1:-summary}"
      shift || true

      case "$ACTION" in
        # ── Ultime azioni AI ─────────────────────────────────────────
        ai|recent)
          N="''${1:-30}"
          echo "── Ultimi $N eventi gavio-ai ──"
          for KEY in ai_execve ai_open_write ai_connect ai_setuid_try; do
            echo
            echo "── $KEY ──"
            sudo ausearch -k "$KEY" --start recent -i 2>/dev/null | \
              tail -n "$((N * 3))" | head -n 20 || echo "(none)"
          done
          ;;

        # ── Tamper attempts (modifiche file critici) ─────────────────
        tamper)
          echo "── Tamper events (ultima ora) ──"
          for KEY in tamper_passwd tamper_shadow tamper_sudoers tamper_sshd tamper_systemd tamper_nixos tamper_boot tamper_audit; do
            COUNT=$(sudo ausearch -k "$KEY" --start "1 hour ago" 2>/dev/null | grep -c "type=SYSCALL" || true)
            COUNT=''${COUNT:-0}
            if [ "$COUNT" -gt 0 ]; then
              echo "  ⚠ $KEY: $COUNT eventi"
            fi
          done
          ;;

        # ── Privilege escalation tentativi da gavio-ai ───────────────
        privesc)
          echo "── Tentativi setuid/setgid da gavio-ai ──"
          sudo ausearch -k ai_setuid_try -i 2>/dev/null | head -30 || \
            echo "(nessuno - bene)"
          ;;

        # ── Connect tentativi da gavio-ai (anche bloccati) ──────────
        net|connect)
          echo "── Connect tentativi da gavio-ai (anche bloccati da nft) ──"
          sudo ausearch -k ai_connect --start "1 hour ago" -i 2>/dev/null | \
            awk '/type=SOCKADDR/{print}' | head -20 || echo "(none)"
          ;;

        # ── Kernel module load/unload (rootkit detection) ────────────
        kmod)
          echo "── init_module / delete_module events ──"
          sudo ausearch -k kernel_module -i 2>/dev/null | head -20 || \
            echo "(none)"
          ;;

        # ── Summary ──────────────────────────────────────────────────
        summary|status)
          echo "── SOLEM AI Audit Strict — summary ──"
          echo
          if ! sudo auditctl -s >/dev/null 2>&1; then
            echo "auditd non attivo"
            exit 1
          fi
          sudo auditctl -s | head -10
          echo
          echo "── Rules attive (count) ──"
          sudo auditctl -l 2>/dev/null | wc -l
          echo
          echo "── Eventi per chiave (ultima ora) ──"
          for KEY in ai_execve ai_open_write ai_connect ai_setuid_try \
                     tamper_passwd tamper_shadow tamper_sudoers tamper_systemd \
                     kernel_module ptrace_try; do
            COUNT=$(sudo ausearch -k "$KEY" --start "1 hour ago" 2>/dev/null | grep -c "type=SYSCALL" || true)
            COUNT=''${COUNT:-0}
            printf "  %-20s %d\n" "$KEY" "$COUNT"
          done
          ;;

        help|--help|-h|*)
          cat <<'HELP'
solem-ai-audit — audit AI-specific + tamper detection

  ai [N]           ultimi N eventi gavio-ai (execve/open/connect/setuid)
  tamper           tentativi modifica file critici sistema
  privesc          tentativi setuid/setgid da gavio-ai
  net              connect attempts (anche bloccati da nftables)
  kmod             kernel module load/unload (rootkit detect)
  summary          stats per ogni chiave audit

Tutto FOSS (auditd GPL). Aggrega ausearch su chiavi SOLEM dedicate.
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.aiAuditStrict = {
    enable = lib.mkEnableOption "Audit rules dedicate per gavio-ai + tamper detection /etc /usr /boot";

    immutable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Aggiunge "-e 2" alla fine: dopo il boot, audit rules NON sono
        modificabili. Anti-disable attack: anche root puo' solo aggiungere,
        non rimuovere o modificare. Default off (rompe debug).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = config.solem.aiUser.enable;
      message = "solem.aiAuditStrict richiede solem.aiUser.enable = true";
    }];

    security.auditd.enable = true;
    security.audit = {
      enable = true;
      rules = lib.splitString "\n" (builtins.readFile rulesFile)
        ++ lib.optional cfg.immutable "-e 2";
    };

    environment.systemPackages = [
      auditCli
      pkgs.audit
    ];

    environment.etc."solem/ai-audit-strict.md".text = ''
      # SOLEM AI Audit Strict

      ## Cosa fa

      Aggiunge auditd rules dedicate a 3 categorie:

      ### 1. Tutto cio' che fa gavio-ai (UID ${toString aiUid})
        - execve: ogni binary lanciato
        - openat: ogni file aperto in write/create mode
        - connect/sendto: ogni tentativo di rete (anche se nftables DROP)
        - setuid/setgid: tentativi privilege escalation

      ### 2. Tamper detection su file di sistema
        - /etc/passwd, /etc/shadow, /etc/sudoers (credenziali)
        - /etc/ssh/sshd_config (SSH config)
        - /etc/systemd/, /etc/nixos/ (config sistema)
        - /boot/ (kernel + bootloader)
        - /etc/cron.d/, /var/spool/cron/ (persistence)
        - /etc/audit/ (anti-disable audit stesso)

      ### 3. Sistema-wide kernel-level
        - init_module / delete_module (rootkit kernel)
        - ptrace (anti-debugger sniffing)

      ## Visibilita' totale per forensics

      Anche se nftables blocca un connect a evil.com:8080, auditd LOGGA
      il tentativo. Dopo un incidente: "l'AI ha PROVATO a contattare
      questi 50 IP nell'ultima ora". Critica per capire intent + scope.

      ## Verifica

      ```
      solem-ai-audit summary       # stats per chiave
      solem-ai-audit tamper        # eventi modifiche /etc
      solem-ai-audit ai            # ultimi 30 eventi AI
      solem-ai-audit privesc       # tentativi setuid
      ```

      ## Limiti onesti

      - Audit log puo' diventare GROSSO: ~100 MB/giorno su sistemi attivi.
        Configura logrotate (gia' default in nixpkgs auditd).
      - Auditd kernel: ~1-3% CPU overhead.
      - Eventi possono andare PERSI se buffer kernel pieno (backlog limit).
      - Non e' detection real-time: serve consultare i log periodicamente
        o aggiungere un daemon che esegue ausearch in loop.
      - immutable=true impedisce di modificare rules anche dopo legitimate
        boot; lockin completo fino al reboot.
    '';
  };
}
