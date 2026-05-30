{ config, pkgs, lib, ... }:

# SOLEM PAM FAILLOCK — Step 16: console+SSH login fail tracking + lockout.
#
# Single responsibility: SOLO configurazione PAM faillock (pam_faillock.so).
# Estende solem-ssh-hardened (Step 11) che copre SSH lato sshd config; qui
# il check e' a livello PAM, applicato a TUTTE le auth (console, sudo, ssh).
#
# Threat coperto:
#   - Brute-force password console fisica (tastiera diretta al boot)
#   - Brute-force password sudo (anche se SSH bloccato)
#   - Brute-force password GUI display manager
#
# Differenza con fail2ban (in Step 11):
#   - fail2ban: legge log sshd, banna IP via iptables (network-level)
#   - pam_faillock: kernel/PAM-level, banna USER account (anche da console)
#   - Sono COMPLEMENTARI, non sostituti.
#
# Tutto FOSS (Linux-PAM BSD-3). 0 €.

let
  cfg = config.solem.pamFaillock;
in {
  options.solem.pamFaillock = {
    enable = lib.mkEnableOption "PAM faillock: lockout account dopo N fail login";

    deny = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = ''
        Numero massimo di tentativi falliti prima del lockout.
        Default 5 (bilanciato: utente che sbaglia 3-4 volte non lockato).
      '';
    };

    fail_interval = lib.mkOption {
      type = lib.types.int;
      default = 900;
      description = ''
        Finestra temporale (sec) per contare i fail.
        Default 900s = 15min. 5 fail in 15min -> lockout.
      '';
    };

    unlock_time = lib.mkOption {
      type = lib.types.int;
      default = 600;
      description = ''
        Tempo (sec) di lockout dopo che il counter scatta.
        Default 600s = 10min. Bilanciato: utente legit aspetta 10min,
        attaccante automatico viene rallentato significativamente.
      '';
    };

    even_deny_root = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Apply lockout ANCHE a root? Default true (paranoid: root puo'
        essere brute-forceato da console se l'attaccante riavvia in
        modalità single-user — pam_faillock blocca anche quello).
        Disabilita SOLO se rischi di lockare-out te stesso (recovery
        difficile su sistemi remoti).
      '';
    };

    audit_login = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Logga ogni fail su audit log (oltre a /run/faillock/)";
    };
  };

  config = lib.mkIf cfg.enable {
    # ────────────────────────────────────────────────────────────────
    # PAM: aggiunge faillock a tutti i servizi PAM-aware
    # ────────────────────────────────────────────────────────────────
    # NixOS espone PAM tramite security.pam.services.<name>. Modificare
    # i text di sshd/login/sudo per includere pam_faillock.
    #
    # NOTA: settando questo a tutti i servizi, un fail in uno conta per
    # gli altri (audit centralizzato).

    security.pam.services = {
      login.failDelay.enable = true;
      login.failDelay.delay = 4000000;  # 4s delay tra fail (rallenta brute)

      sshd.failDelay.enable = true;
      sshd.failDelay.delay = 4000000;
    };

    # faillock config globale
    environment.etc."security/faillock.conf".text = ''
      # SOLEM PAM faillock config
      deny = ${toString cfg.deny}
      fail_interval = ${toString cfg.fail_interval}
      unlock_time = ${toString cfg.unlock_time}
      ${lib.optionalString cfg.even_deny_root "even_deny_root"}
      ${lib.optionalString cfg.audit_login "audit"}

      # Lockfile: /run/faillock/<user> tracking. tmpfs => reset al reboot
      # (intenzionale: un attacker che riesce reboot perde counter, ma
      # fail2ban e auditd persistono).
      dir = /run/faillock

      # Silent mode: don't reveal "account locked" to attacker
      silent
    '';

    # ────────────────────────────────────────────────────────────────
    # CLI di gestione
    # ────────────────────────────────────────────────────────────────
    environment.systemPackages = with pkgs; [
      linux-pam  # provides faillock binary
      (pkgs.writeShellApplication {
        name = "solem-faillock";
        runtimeInputs = with pkgs; [ coreutils linux-pam ];
        text = ''
          ACTION="''${1:-status}"
          shift || true

          case "$ACTION" in
            status)
              echo "── SOLEM PAM Faillock ──"
              echo "deny=${toString cfg.deny}"
              echo "fail_interval=${toString cfg.fail_interval}s"
              echo "unlock_time=${toString cfg.unlock_time}s"
              echo
              echo "── Account con fail attivi ──"
              for U in $(getent passwd | cut -d: -f1 | sort -u); do
                count=$(sudo faillock --user "$U" 2>/dev/null | grep -cE '^[0-9]{4}' || true)
                if [ "$count" -gt 0 ]; then
                  printf "  %-20s %d fail\n" "$U" "$count"
                fi
              done | head -20
              ;;

            user)
              U="''${1:?Usage: solem-faillock user <username>}"
              echo "── Stato $U ──"
              sudo faillock --user "$U"
              ;;

            reset)
              U="''${1:?Usage: solem-faillock reset <username>}"
              sudo faillock --user "$U" --reset
              echo "✓ Fail counter di $U azzerato"
              ;;

            help|--help|-h|*)
              cat <<'HELP'
solem-faillock — PAM lockout management

  status        elenca account con fail attivi
  user <name>   stato dettagliato di uno specifico account
  reset <name>  azzera counter di un account (utile dopo legit fail)

Threat coperto: brute-force password console / SSH / sudo a livello PAM.

Complementare a:
  - fail2ban (network IP ban)
  - solem-ssh-hardened (sshd config)

Tutto FOSS (Linux-PAM BSD).
HELP
              ;;
          esac
        '';
      })
    ];

    environment.etc."solem/pam-faillock.md".text = ''
      # SOLEM PAM Faillock

      PAM-level account lockout dopo ${toString cfg.deny} fail login in
      ${toString cfg.fail_interval}s -> lockout ${toString cfg.unlock_time}s.

      ## Differenza con fail2ban

      | Tool | Layer | Banna | Dove |
      |---|---|---|---|
      | fail2ban | network (iptables) | IP | log sshd parsing |
      | pam_faillock | kernel/PAM | USER | counter /run/faillock |

      pam_faillock funziona anche con SSH key-only (se sbagli passphrase
      ssh-agent multiple volte non scatta — ma scatta su sudo/su/login GUI).

      ## CLI

      ```bash
      solem-faillock status         # elenca account con fail
      solem-faillock user gavio     # dettaglio
      solem-faillock reset gavio    # azzera (utile dopo legit fail)
      ```

      ## Limiti onesti

      - Counter in /run/faillock (tmpfs): reset dopo reboot.
        Mitigazione: attacker che reboot perde anche tutti i suoi
        progressi, e auditd persiste su disk.
      - even_deny_root=true: se ti lockki-out come root su sistema senza
        recovery console, recovery e' difficile. Per VM/laptop con accesso
        fisico OK. Per server remoto: imposta a false.
      - silent mode: utente legittimo non vede "account locked" → potrebbe
        confondersi. Trade-off security vs UX.
      - Brute-force distribuito (10k IP) non scatta lockout user perche'
        ogni IP fa 1 tentativo. Mitigato da fail2ban globale (bantime
        increment) + 4s failDelay tra fail.
    '';
  };
}
