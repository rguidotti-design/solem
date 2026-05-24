{ config, pkgs, lib, ... }:

# SOLEM NET AUDIT — log ogni connessione outbound (auditd).
#
# Single responsibility: SOLO configurare auditd con rules che loggano
# tutte le syscall `connect()` outbound. Visibilità totale su cosa parla
# con cosa nel sistema.
#
# Privacy + sicurezza: rileva exfiltration dati, processi che parlano a
# C2 server, malware phone-home.

let
  cfg = config.solem.netAudit;

  auditRules = pkgs.writeText "solem-net-audit.rules" ''
    ## SOLEM Network Audit rules

    # Log ogni connect() syscall (outbound TCP/UDP)
    -a always,exit -F arch=b64 -S connect -k net_connect
    -a always,exit -F arch=b32 -S connect -k net_connect

    # Log ogni sendto() / sendmsg() su socket TCP/UDP
    # (cattura datagram UDP outbound, DNS, etc.)
    -a always,exit -F arch=b64 -S sendto -S sendmsg -k net_send

    # Log accept() inbound (chi si connette a noi)
    -a always,exit -F arch=b64 -S accept -S accept4 -k net_accept

    # Log bind() (chi apre porte di ascolto)
    -a always,exit -F arch=b64 -S bind -k net_bind
  '';

  auditCli = pkgs.writeShellApplication {
    name = "solem-net-audit";
    runtimeInputs = with pkgs; [ coreutils audit gawk ];
    text = ''
      ACTION="''${1:-summary}"

      case "$ACTION" in
        # ── Ultime N connessioni outbound ────────────────────────────
        recent|tail)
          N="''${1:-20}"
          sudo ausearch -k net_connect --start recent -i 2>/dev/null | tail -n "$((N * 5))" || \
            echo "auditd non attivo o nessuna entry"
          ;;

        # ── Summary per processo ─────────────────────────────────────
        by-process)
          echo "── Connessioni outbound per processo (ultimi 5 min) ──"
          sudo ausearch -k net_connect --start "5 minutes ago" -i 2>/dev/null | \
            awk '/comm=/{
              for(i=1;i<=NF;i++) if($i ~ /^comm=/) print substr($i, 6)
            }' | sort | uniq -c | sort -rn | head -20
          ;;

        # ── Statistiche audit ────────────────────────────────────────
        stats)
          echo "── auditd stats ──"
          sudo auditctl -s 2>/dev/null || echo "auditd non attivo"
          echo
          echo "── Rules attive ──"
          sudo auditctl -l 2>/dev/null | head -20
          ;;

        # ── Cerca connessioni a IP specifico ─────────────────────────
        ip)
          IP="''${1:?Usage: solem-net-audit ip <ip>}"
          sudo ausearch -k net_connect -i 2>/dev/null | grep -B2 -A2 "$IP" | head -30
          ;;

        # ── Real-time follow ─────────────────────────────────────────
        follow|tail-live)
          sudo tail -F /var/log/audit/audit.log 2>/dev/null | \
            awk '/type=SYSCALL/{print}'
          ;;

        # ── HELP ─────────────────────────────────────────────────────
        help|--help|-h|*)
          cat <<'HELP'
solem-net-audit — log ogni connessione outbound (auditd FOSS)

  recent [N]            ultime N connessioni outbound
  by-process            top processi che fanno connect() (5 min)
  ip <ip-addr>          cerca connessioni a IP specifico
  follow                tail audit log live
  stats                 stats auditd + rules attive

Rules attive (auditctl -l):
  - net_connect: TCP/UDP connect() outbound
  - net_send: sendto/sendmsg datagrammi
  - net_accept: accept inbound (chi si connette a noi)
  - net_bind: bind() porte di ascolto

Performance: auditd kernel-level, overhead < 1% CPU.

Tutto FOSS (auditd GPL-2.0). 0 €. Niente cloud, log locale.
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.netAudit = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        auditd con rules SOLEM per loggare ogni connect/sendto/accept/bind.
        Default off (genera molto log per sistemi attivi).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      auditCli
      audit
    ];

    security.auditd.enable = true;
    security.audit = {
      enable = true;
      rules = lib.splitString "\n" (builtins.readFile auditRules);
    };

    environment.etc."solem/net-audit.md".text = ''
      # SOLEM Net Audit

      ## Cosa fa

      auditd kernel-level logga ogni syscall di rete:
        - connect() → outbound TCP/UDP
        - sendto / sendmsg → datagrammi (incl. DNS)
        - accept → inbound (chi parla con noi)
        - bind → quale processo apre porte

      ## Vantaggio vs Wireshark

      - Wireshark: vede solo il PROTOCOLLO. Devi correlare a processo.
      - auditd: vede SUBITO il PROCESSO che fa la connect().
      - auditd: anche traffico encrypted/VPN — tracking exfil.

      ## Use cases

      1. Detect malware phone-home: vediamo CHI parla con CHI.
      2. Privacy audit: scoprire app che fanno connect senza dirlo.
      3. Forensics: log immutabile post-incidente.

      ## Performance

      auditd kernel-level: < 1% CPU overhead anche su sistemi
      attivi. Log raw in /var/log/audit/audit.log.

      ## Limiti

      - Log GROSSI (può crescere a 100 MB/giorno su sistemi network-heavy).
      - Configura logrotate o trim periodico.
      - Auditd può rallentare in caso di flood (es. port scan locale).
    '';
  };
}
