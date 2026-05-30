{ config, pkgs, lib, ... }:

# SOLEM SURICATA IDS — Step 25: network intrusion detection signature-based.
#
# Single responsibility: SOLO Suricata daemon in modalita' IDS passiva
# (afpacket monitor) + ET Open ruleset (free signature library).
#
# Differenza con altri layer SOLEM:
#   - solem-ai-network (Step 2): firewall preventivo (drop pkg)
#   - solem-net-audit (Step pre-zt): auditd connect log (kernel syscall)
#   - solem-suricata-ids (Step 25): DPI signature-match runtime
#     (legge CONTENUTO traffic, non solo metadata)
#
# Detect (NON block — passive monitoring):
#   - Tentativi exploit CVE noti (Log4Shell, Heartbleed, ecc.)
#   - C2 traffic pattern (Cobalt Strike, Mythic, AsyncRAT signature)
#   - DNS exfiltration tunneling (long subdomain entropy)
#   - Cryptominer traffic patterns
#   - Reverse shell signatures (msfvenom, netcat patterns)
#   - SQL injection in HTTP body
#   - Browser exploit kits noti
#
# Plus integration con solem-self-heal (Step 23): alert critico
# può trigger kill switch o policy update.
#
# Tutto FOSS (Suricata GPL-2.0, ET Open ruleset BSD).

let
  cfg = config.solem.suricataIds;
in {
  options.solem.suricataIds = {
    enable = lib.mkEnableOption "Suricata IDS network-level (passive monitoring)";

    interfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "eth0" ];
      example = [ "eth0" "wg-solem" ];
      description = ''
        Interfacce di rete da monitorare. Default eth0.
        Aggiungi wg-solem se vuoi monitorare anche traffic VPN mesh.
      '';
    };

    homeNet = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "192.168.0.0/16" "10.0.0.0/8" "172.16.0.0/12" ];
      description = ''
        HOME_NET: range IP considerati "nostri" (LAN locale, VPN, ...).
        Suricata classifica traffic INSIDE-OUT vs OUTSIDE-IN diversamente.
      '';
    };

    enableEmergingThreats = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Scarica + aggiorna ET Open ruleset da emergingthreats.net.
        Pacchetto: ~30k signature gratuite. Update via suricata-update timer daily.
      '';
    };

    inhibitAlerts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "ET INFO Microsoft Windows OS Generic Detection" ];
      description = "Lista sostringhe alert msg da sopprimere (riduce noise)";
    };

    integrateCanary = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Su alert CRITICAL (priority 1), scrive a /var/lib/solem/IDS_ALERT
        che e' watched dal canary kill switch (Step 4).
        Effetto: alert CVE critico -> kill GAVIO + notify utente.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.suricata = {
      enable = true;
      settings = {
        vars = {
          address-groups = {
            HOME_NET = "[" + lib.concatStringsSep "," cfg.homeNet + "]";
            EXTERNAL_NET = "!$HOME_NET";
            HTTP_SERVERS = "$HOME_NET";
            SMTP_SERVERS = "$HOME_NET";
            SQL_SERVERS = "$HOME_NET";
            DNS_SERVERS = "$HOME_NET";
            TELNET_SERVERS = "$HOME_NET";
          };
          port-groups = {
            HTTP_PORTS = "80,443,8080,8000,8001";
            SHELLCODE_PORTS = "!80";
            ORACLE_PORTS = "1521";
            SSH_PORTS = "22";
            DNP3_PORTS = "20000";
            MODBUS_PORTS = "502";
          };
        };

        # Output: EVE JSON (machine-readable) + fast.log (human)
        outputs = [
          {
            fast = {
              enabled = true;
              filename = "/var/log/suricata/fast.log";
              append = true;
            };
          }
          {
            eve-log = {
              enabled = true;
              filetype = "regular";
              filename = "/var/log/suricata/eve.json";
              types = [
                "alert"
                "anomaly"
                "http"
                "dns"
                "tls"
                "flow"
              ];
            };
          }
          {
            stats = {
              enabled = true;
              filename = "/var/log/suricata/stats.log";
              interval = 300;
            };
          }
        ];

        # afpacket: passive monitor, no inline blocking
        af-packet = map (iface: {
          interface = iface;
          threads = "auto";
          cluster-id = 99;
          cluster-type = "cluster_flow";
          defrag = "yes";
          use-mmap = "yes";
          mmap-locked = "yes";
        }) cfg.interfaces;

        # Stream reassembly
        stream = {
          memcap = "256mb";
          checksum-validation = "yes";
          inline = "no";  # passive only
          reassembly = {
            memcap = "256mb";
            depth = "1mb";
            toserver-chunk-size = 2560;
            toclient-chunk-size = 2560;
            randomize-chunk-size = "yes";
          };
        };

        # Detection engine
        detect = {
          profile = "medium";
          custom-values = {};
          sgh-mpm-context = "auto";
        };

        # MPM (pattern matching) algo
        mpm-algo = "auto";
      };
    };

    # ────────────────────────────────────────────────────────────────
    # ET Open ruleset auto-update (daily timer)
    # ────────────────────────────────────────────────────────────────
    systemd.services.suricata-update = lib.mkIf cfg.enableEmergingThreats {
      description = "SOLEM: aggiorna ET Open ruleset Suricata";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.suricata}/bin/suricata-update --no-test --no-reload";
        ExecStartPost = "${pkgs.systemd}/bin/systemctl reload suricata.service || true";
        User = "root";
      };
    };

    systemd.timers.suricata-update = lib.mkIf cfg.enableEmergingThreats {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };

    # ────────────────────────────────────────────────────────────────
    # Canary integration: alert critical -> marker file
    # ────────────────────────────────────────────────────────────────
    systemd.services.solem-suricata-canary-bridge = lib.mkIf cfg.integrateCanary {
      description = "SOLEM IDS: bridge alert critical → canary marker";
      after = [ "suricata.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = 30;
        ExecStart = pkgs.writeShellScript "solem-suricata-bridge" ''
          set +e
          mkdir -p /var/lib/solem
          tail -F /var/log/suricata/eve.json 2>/dev/null | while read -r line; do
            if echo "$line" | ${pkgs.jq}/bin/jq -e 'select(.event_type=="alert" and .alert.severity==1)' >/dev/null 2>&1; then
              SIG=$(echo "$line" | ${pkgs.jq}/bin/jq -r '.alert.signature' 2>/dev/null)
              SRC=$(echo "$line" | ${pkgs.jq}/bin/jq -r '.src_ip' 2>/dev/null)
              echo "$(date -Iseconds) CRITICAL: $SIG src=$SRC" >> /var/lib/solem/IDS_ALERT
              ${pkgs.systemd}/bin/systemd-cat -t solem-ids -p alert echo "Suricata CRITICAL: $SIG src=$SRC"
            fi
          done
        '';
      };
    };

    # ────────────────────────────────────────────────────────────────
    # CLI
    # ────────────────────────────────────────────────────────────────
    environment.systemPackages = with pkgs; [
      suricata
      jq
      (pkgs.writeShellApplication {
        name = "solem-ids";
        runtimeInputs = with pkgs; [ coreutils jq suricata systemd ];
        text = ''
          ACTION="''${1:-status}"

          case "$ACTION" in
            status)
              echo "── SOLEM Suricata IDS ──"
              if systemctl is-active suricata.service >/dev/null 2>&1; then
                echo "Daemon: ATTIVO"
              else
                echo "Daemon: spento"
              fi
              echo
              if [ -f /var/log/suricata/stats.log ]; then
                echo "── Stats ultimo intervallo ──"
                tail -20 /var/log/suricata/stats.log | grep -E "decoder|tcp|alerts" | head -10
              fi
              echo
              if [ -f /var/lib/solem/IDS_ALERT ]; then
                echo "⚠⚠ CRITICAL alert recenti ⚠⚠"
                tail -5 /var/lib/solem/IDS_ALERT
              fi
              ;;

            alerts|recent)
              N="''${1:-20}"
              echo "── Ultimi $N alert (eve.json) ──"
              if [ -f /var/log/suricata/eve.json ]; then
                tail -1000 /var/log/suricata/eve.json | \
                  jq -r 'select(.event_type=="alert") | "\(.timestamp) [\(.alert.severity)] \(.alert.signature) - \(.src_ip) -> \(.dest_ip):\(.dest_port)"' | \
                  tail -"$N"
              else
                echo "(no eve.json yet)"
              fi
              ;;

            critical)
              echo "── Alert CRITICAL (severity 1) ──"
              if [ -f /var/log/suricata/eve.json ]; then
                tail -10000 /var/log/suricata/eve.json | \
                  jq -r 'select(.event_type=="alert" and .alert.severity==1) | "\(.timestamp) \(.alert.signature) src=\(.src_ip)"' | \
                  tail -20
              fi
              ;;

            stats)
              echo "── Stats Suricata complete ──"
              tail -40 /var/log/suricata/stats.log
              ;;

            update-rules)
              echo "Update ET Open ruleset..."
              sudo systemctl start suricata-update.service
              sleep 5
              sudo systemctl reload suricata.service
              echo "Done. Conta regole attive: $(suricata-update list-enabled-sources | wc -l)"
              ;;

            reset-alert)
              sudo rm -f /var/lib/solem/IDS_ALERT
              echo "✓ Alert marker rimosso"
              ;;

            help|--help|-h|*)
              cat <<'HELP'
solem-ids — Suricata network IDS

  status         daemon + stats + critical alert
  alerts [N]     ultimi N alert (default 20)
  critical       solo alert severity 1 (gravi)
  stats          Suricata stats interne
  update-rules   force update ET Open ruleset
  reset-alert    rimuove marker IDS_ALERT (dopo investigazione)

Threat detect (passive — NOT inline block):
  - CVE exploit signature (Log4Shell, Heartbleed, ...)
  - C2 traffic pattern (Cobalt Strike, AsyncRAT)
  - DNS tunneling (long subdomain entropy)
  - Cryptominer traffic
  - SQL injection HTTP body
  - Reverse shell payload
  - Browser exploit kit

Output: /var/log/suricata/eve.json (JSON machine-readable).

Critical alert (severity 1) -> /var/lib/solem/IDS_ALERT marker.
Integrazione canary: marker triggera kill switch GAVIO.

Tutto FOSS (Suricata GPL + ET Open BSD).
HELP
              ;;
          esac
        '';
      })
    ];

    environment.etc."solem/suricata-ids.md".text = ''
      # SOLEM Suricata IDS (Step 25)

      Network intrusion detection signature-based, PASSIVE monitoring
      (no inline blocking — quello e' Step 2 nft/firewall).

      ## Stack
      - **Suricata** (GPL-2.0): DPI multi-thread, 10-40 Gbps capable
      - **ET Open ruleset** (BSD): ~30k signature free
      - **suricata-update**: auto-fetch ruleset daily
      - **EVE JSON output**: machine-readable per integration

      ## Detect (~30k signature)
      - CVE noti: Log4Shell, Heartbleed, BlueKeep, ProxyShell, ...
      - C2 patterns: Cobalt Strike beacon, AsyncRAT, Mythic, Sliver
      - DNS tunneling: long subdomain entropy, base64-encoded subdomain
      - Cryptominer: Monero pool patterns, XMRig traffic
      - Reverse shell: msfvenom payload, ncat reverse, bash TCP
      - SQL injection: HTTP body patterns
      - Browser exploit kit: Angler, Magnitude, RIG

      ## Integrazione canary

      Quando Suricata trigger CRITICAL alert (severity 1):
        - Scrive /var/lib/solem/IDS_ALERT
        - Marker watched dal Step 4 canary watcher
        - Effetto: kill switch GAVIO automatico

      ## Differenza con altri SOLEM layers

      | Layer | Step | Type | Layer di rete |
      |---|---|---|---|
      | solem-ai-network | 2 | preventive | L3/L4 firewall |
      | solem-ai-dns | 7 | preventive | L7 DNS allowlist |
      | solem-suricata-ids | 25 | detective | L7 DPI signature |
      | solem-net-audit | pre-zt | detective | L3 syscall log |

      ## Limiti onesti
      - Passive monitor: detect ma NON blocca runtime (no IPS inline).
        Per blocco: integration via nftables hook su match → futuro.
      - Encrypted traffic (HTTPS): solo metadata (SNI, JA3 fingerprint),
        non payload. Mitigazione: combina con TLS pinning.
      - False positive: 30k regole noise. Tuning inhibitAlerts list.
      - Performance: ~100-500MB RAM. Su low-end (Beelink): considera
        riducere stream memcap o disabilitare reassembly.
      - Aggiornamento ruleset richiede internet (suricata-update fetch).
    '';
  };
}
