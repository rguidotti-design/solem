{ config, pkgs, lib, ... }:

# SOLEM AI NETWORK — egress firewall per processi AI (gavio-ai).
#
# Single responsibility: SOLO regole nftables che BLOCCANO outbound
# di default per l'utente `gavio-ai`. Whitelist solo destinazioni
# autorizzate (DNS, NTP, endpoint GAVIO, mirror update Nix).
#
# Differenza vs solem-net-audit:
#   - net-audit LOGGA tutto (forensics post-fatto)
#   - ai-network BLOCCA in kernel (prevenzione real-time)
#
# Threat model:
#   - L'AI tenta exfiltration dati → connect verso C2 → DROP.
#   - L'AI tenta DNS tunneling → DNS solo verso resolver autorizzato.
#   - L'AI tenta download payload → HTTP solo verso domini whitelist.
#
# Implementazione: nftables `meta skuid == 970 drop` (UID-based).
# Più solido di iptables-owner perché skuid si applica anche a
# socket creati prima del setuid.

let
  cfg = config.solem.aiNetwork;
  aiUid = config.solem.aiUser.uid or 970;

  # NB: stringa diretta (no writeText + readFile per evitare
  # "drv path not valid" in pure-eval mode).
  ruleText = ''
    # SOLEM AI Network — egress whitelist per UID ${toString aiUid} (gavio-ai)
    #
    # NB: questo file e' MERGED con il ruleset esistente, non lo sostituisce.

    table inet solem-ai {
      # Set degli IP/CIDR autorizzati (popolato runtime via solem-ai-net allow)
      set ai_allowed_v4 {
        type ipv4_addr
        flags interval
        elements = {
          ${lib.concatStringsSep ", " ([ "127.0.0.0/8" ] ++ cfg.allowedV4)}
        }
      }
      set ai_allowed_v6 {
        type ipv6_addr
        flags interval
        elements = {
          ${lib.concatStringsSep ", " ([ "::1/128" ] ++ cfg.allowedV6)}
        }
      }
      set ai_allowed_ports {
        type inet_service
        elements = {
          ${lib.concatStringsSep ", " (map toString ([ 53 123 443 ] ++ cfg.allowedPorts))}
        }
      }

      chain ai_egress {
        # Fail-closed: policy drop. Se nessuna regola matcha, packet dropped.
        # Per altri UID return early (no impact su utente umano).
        type filter hook output priority 0; policy drop;

        # Utente umano gavio (UID != 970): return -> chain successive decidono
        meta skuid != ${toString aiUid} accept

        # Loopback completo (gavio-ai parla con GAVIO API locale)
        oif "lo" accept

        # Whitelist destinazioni + porte
        ip daddr @ai_allowed_v4 tcp dport @ai_allowed_ports accept
        ip daddr @ai_allowed_v4 udp dport @ai_allowed_ports accept
        ip6 daddr @ai_allowed_v6 tcp dport @ai_allowed_ports accept
        ip6 daddr @ai_allowed_v6 udp dport @ai_allowed_ports accept

        # Log esplicito + DROP esplicito (policy drop e' fallback anyway)
        ${lib.optionalString cfg.logBlocked ''
          limit rate 10/minute log prefix "SOLEM-AI-BLOCK: " flags all
        ''}
        counter drop
      }
    }
  '';

  netCli = pkgs.writeShellApplication {
    name = "solem-ai-net";
    runtimeInputs = with pkgs; [ coreutils nftables iproute2 gawk ];
    text = ''
      ACTION="''${1:-status}"
      shift || true

      case "$ACTION" in
        status)
          echo "── SOLEM AI Network ──"
          echo "AI UID watch: ${toString aiUid}"
          echo
          if sudo nft list table inet solem-ai 2>/dev/null; then
            echo
            echo "── Drop counter ──"
            sudo nft list chain inet solem-ai ai_egress 2>/dev/null | grep counter || true
          else
            echo "Tabella inet solem-ai non caricata (modulo disabilitato?)"
            exit 1
          fi
          ;;

        blocked|denied)
          echo "── Ultimi blocchi outbound AI (journalctl) ──"
          sudo journalctl -k --since "1 hour ago" 2>/dev/null | \
            grep "SOLEM-AI-BLOCK" | tail -20 || \
            echo "(nessun blocco — o logging disabilitato)"
          ;;

        test-block)
          # Test che l'AI NON puo' raggiungere un IP non autorizzato.
          # Usa 1.1.1.1 (Cloudflare) come target esterno generico.
          echo "Test: gavio-ai prova a raggiungere 1.1.1.1:443 (non in whitelist)"
          if sudo -u gavio-ai timeout 5 ${pkgs.curl}/bin/curl -s -o /dev/null -w "%{http_code}\n" https://1.1.1.1 2>/dev/null; then
            echo "✗ FAIL: connessione riuscita (firewall NON sta bloccando)"
            exit 1
          else
            echo "✓ OK: connessione bloccata"
          fi
          ;;

        test-allow)
          echo "Test: gavio-ai puo' raggiungere localhost (whitelistato)"
          if sudo -u gavio-ai timeout 3 ${pkgs.curl}/bin/curl -s -o /dev/null http://127.0.0.1 2>/dev/null; then
            echo "✓ OK: localhost raggiunto"
          else
            echo "(nessun server localhost — test inconclusivo)"
          fi
          ;;

        allow)
          IP="''${1:?Usage: solem-ai-net allow <ip>}"
          sudo nft add element inet solem-ai ai_allowed_v4 "{ $IP }" 2>/dev/null && \
            echo "✓ $IP aggiunto a whitelist (volatile, perso al reboot)" || \
            echo "✗ errore aggiunta (modulo attivo?)"
          ;;

        deny)
          IP="''${1:?Usage: solem-ai-net deny <ip>}"
          sudo nft delete element inet solem-ai ai_allowed_v4 "{ $IP }" 2>/dev/null && \
            echo "✓ $IP rimosso da whitelist" || \
            echo "✗ errore rimozione"
          ;;

        help|--help|-h|*)
          cat <<'HELP'
solem-ai-net — egress firewall per UID gavio-ai (nftables)

  status            stato tabella + drop counter
  blocked           ultimi outbound bloccati (journal)
  test-block        verifica che IP non-whitelist sia DROP
  test-allow        verifica che localhost sia ALLOW
  allow <ip>        aggiungi IP a whitelist (volatile)
  deny <ip>         rimuovi IP da whitelist

Funzionamento:
  - Tutto outbound da UID 970 (gavio-ai) -> DROP di default.
  - Whitelist: 127/8, ::1, IP configurati in solem.aiNetwork.allowedV4.
  - Porte: 53 (DNS), 123 (NTP), 443 (HTTPS), + allowedPorts.
  - L'utente umano `gavio` NON e' filtrato (regola skuid solo per AI).

vs solem-net-audit:
  - net-audit: LOGGA tutto per forensics.
  - ai-net:    BLOCCA in kernel real-time.

Tutto FOSS (nftables GPL). 0 €.
HELP
          ;;
      esac
    '';
  };
in {
  options.solem.aiNetwork = {
    enable = lib.mkEnableOption "Egress firewall per UID gavio-ai (block-by-default)";

    allowedV4 = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "192.168.1.0/24" "10.0.0.50/32" ];
      description = ''
        IPv4 / CIDR autorizzati per gavio-ai outbound.
        Localhost (127/8) sempre incluso.
      '';
    };

    allowedV6 = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "IPv6 / prefix autorizzati per gavio-ai outbound.";
    };

    allowedPorts = lib.mkOption {
      type = lib.types.listOf lib.types.int;
      default = [ ];
      example = [ 8000 11434 ];
      description = ''
        Porte destinazione aggiuntive (oltre 53/123/443).
        Es. 11434 per Ollama, 8000 per GAVIO API.
      '';
    };

    logBlocked = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Log syslog dei pacchetti bloccati (rate-limited 10/min)";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = config.solem.aiUser.enable;
      message = ''
        solem.aiNetwork richiede solem.aiUser.enable = true.
        Altrimenti UID ${toString aiUid} potrebbe non esistere o
        appartenere a utente sbagliato.
      '';
    }];

    # nftables deve essere abilitato a livello sistema
    networking.nftables.enable = true;

    # Iniettiamo il nostro ruleset
    networking.nftables.ruleset = lib.mkBefore ruleText;

    environment.systemPackages = [
      netCli
      pkgs.nftables
    ];

    environment.etc."solem/ai-network.md".text = ''
      # SOLEM AI Network — Egress whitelist

      Tutto outbound dell'utente gavio-ai (UID ${toString aiUid}) e' DROPPATO
      di default. Whitelist esplicita in `solem.aiNetwork.allowedV4`.

      ## Threat coperto

      - **Exfiltration**: l'AI prova a fare POST verso C2 → DROP.
      - **Phone-home malware**: payload scaricato non puo' comunicare.
      - **DNS tunneling**: solo resolver in whitelist accettato.
      - **Lateral movement**: l'AI non scopre rete interna fuori CIDR allow.

      ## Esempio config

      ```nix
      solem.aiNetwork = {
        enable = true;
        allowedV4 = [
          "192.168.1.0/24"    # LAN locale
          "1.1.1.1/32"        # DNS Cloudflare
          "9.9.9.9/32"        # DNS Quad9
        ];
        allowedPorts = [ 11434 8000 ];  # Ollama + GAVIO API
      };
      ```

      ## Verifica

      ```
      solem-ai-net status         # vede tabella nft + counter
      solem-ai-net test-block     # prova IP non-whitelist (deve fallire)
      solem-ai-net blocked        # ultimi DROP
      ```

      ## Limiti onesti

      - Filtra per UID: se l'AI riesce a setuid (root exploit) bypassa tutto.
      - L'AI puo' comunque parlare con altri processi locali (loopback aperto).
      - DNS tunneling via porta 53 PASSA — serve un layer DNS filtering
        separato (DNS over HTTPS allowlist, futuro modulo).
      - Connessioni gia' aperte prima del cambio rules non vengono droppate.
    '';
  };
}
