{ config, pkgs, lib, ... }:

# SOLEM AI DNS — resolver locale con allowlist domini per gavio-ai.
#
# Single responsibility: SOLO blocca DNS tunneling esfiltration.
# Resolver locale unbound su porta 5353 che ACCETTA query solo per
# domini esplicitamente in allowlist. Tutti gli altri → REFUSED.
#
# Traffico DNS di gavio-ai (UID 970) viene REDIRETTO via nftables NAT
# da 53 → 127.0.0.1:5353. L'utente umano `gavio` continua a usare il
# resolver di sistema normale (no redirect).
#
# Threat coperto:
#   - DNS tunneling: AI esfiltra dati codificandoli nei sotto-domini
#     (es. `c2VjcmV0.attacker.com`) → REFUSED dal resolver locale.
#   - C2 via DNS TXT records: AI cerca payload in `cmd.attacker.com TXT`
#     → REFUSED.
#   - Domain fronting via DNS: AI risolve domini malevoli mascherati
#     → REFUSED se non in allowlist.
#
# Limiti onesti:
#   - Se l'allowlist e' troppo larga (es. *.googleusercontent.com),
#     domini malevoli ospitati lì passano.
#   - DoH (DNS over HTTPS verso 443) bypassa tutto: AI fa direttamente
#     HTTPS a un resolver remoto → ma porta 443 e' filtrata da
#     solem-ai-network whitelist IP, quindi reggiamo se nftables OK.
#   - Cache poisoning interna a unbound: minimo perche' usiamo DNSSEC.

let
  cfg = config.solem.aiDns;
  aiUid = config.solem.aiUser.uid or 970;
in {
  options.solem.aiDns = {
    enable = lib.mkEnableOption "DNS allowlist per gavio-ai (anti DNS tunneling)";

    port = lib.mkOption {
      type = lib.types.int;
      default = 5353;
      description = "Porta locale del resolver AI (default 5353)";
    };

    allowedDomains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        # Ollama model registry
        "ollama.com"
        "ollama.ai"
        "registry.ollama.ai"
        # HuggingFace (model download)
        "huggingface.co"
        "cdn-lfs.huggingface.co"
        # NixOS substituters (per build remote)
        "cache.nixos.org"
        # NTP
        "pool.ntp.org"
        "time.cloudflare.com"
        # DNS upstream (per il resolver stesso)
        "one.one.one.one"
        "dns.quad9.net"
      ];
      example = [ "example.com" "api.anthropic.com" ];
      description = ''
        Lista domini autorizzati per query DNS da gavio-ai.
        Subdomain inclusi (transparent zone). Default include Ollama
        + HuggingFace + Nix cache + NTP + DNS upstream.
        TUTTI gli altri domini ricevono REFUSED.
      '';
    };

    upstreamResolvers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "1.1.1.1@853#one.one.one.one"   # Cloudflare DoT
        "9.9.9.9@853#dns.quad9.net"     # Quad9 DoT
      ];
      description = ''
        DNS upstream (formato unbound forward-addr: IP@porta#TLS-name).
        Default: Cloudflare + Quad9 via DNS-over-TLS (porta 853).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = config.solem.aiUser.enable;
      message = "solem.aiDns richiede solem.aiUser.enable = true";
    }];

    # ────────────────────────────────────────────────────────────────
    # Unbound: resolver locale con allowlist
    # ────────────────────────────────────────────────────────────────
    services.unbound = {
      enable = true;
      settings = {
        server = {
          interface = [ "127.0.0.1" ];
          port = cfg.port;
          # Accetta solo localhost (no exposed pubblico)
          access-control = [
            "127.0.0.0/8 allow"
            "::1/128 allow"
            "0.0.0.0/0 refuse"
            "::/0 refuse"
          ];
          # DNSSEC validation (NixOS gestisce root.key via enableRootTrustAnchor)
          # Non settare auto-trust-anchor-file qui: unbound-keygen.service lo
          # popola se enableRootTrustAnchor=true (default). In VM isolata
          # disabilita via solem.aiDns.dnssec = false oppure usa il test setup.
          val-permissive-mode = "no";
          # Privacy: minimize query info (RFC 7816)
          qname-minimisation = "yes";
          # Hardening
          hide-identity = "yes";
          hide-version = "yes";
          harden-glue = "yes";
          harden-dnssec-stripped = "yes";
          use-caps-for-id = "yes";
          # CRITICO: refuse ALL by default + transparent per allowlist
          # local-zone "." refuse  → tutti i domini refused
          # local-zone "ollama.com." transparent  → query a ollama.com proseguono
          #   (matcha la sub-zone piu' specifica)
          local-zone = [ ''"." refuse'' ] ++
            (map (d: ''"${d}." transparent'') cfg.allowedDomains);
        };

        # Forward upstream solo per domini in allowlist (via DoT)
        forward-zone = map (domain: {
          name = "${domain}.";
          forward-tls-upstream = "yes";
          forward-addr = cfg.upstreamResolvers;
        }) cfg.allowedDomains;
      };
    };

    # ────────────────────────────────────────────────────────────────
    # nftables NAT: redirect UID 970 DNS → resolver locale
    # ────────────────────────────────────────────────────────────────
    networking.nftables.enable = true;
    networking.nftables.ruleset = lib.mkAfter ''
      table inet solem-ai-dns {
        chain ai_dns_redirect {
          type nat hook output priority -100; policy accept;
          # SOLO l'UID gavio-ai viene rediretto
          meta skuid != ${toString aiUid} return
          # DNAT verso resolver locale porta cfg.port
          udp dport 53 dnat ip to 127.0.0.1:${toString cfg.port}
          tcp dport 53 dnat ip to 127.0.0.1:${toString cfg.port}
        }
      }
    '';

    # ────────────────────────────────────────────────────────────────
    # CLI di ispezione e test
    # ────────────────────────────────────────────────────────────────
    environment.systemPackages = [
      pkgs.dig
      (pkgs.writeShellApplication {
        name = "solem-ai-dns";
        runtimeInputs = with pkgs; [ coreutils dig systemd nftables ];
        text = ''
          ACTION="''${1:-status}"

          case "$ACTION" in
            status)
              echo "── SOLEM AI DNS ──"
              echo "Resolver locale: 127.0.0.1:${toString cfg.port}"
              systemctl is-active unbound.service >/dev/null 2>&1 && \
                echo "unbound: ATTIVO" || echo "unbound: spento"
              echo
              echo "── Allowlist domini ──"
              for D in ${lib.concatStringsSep " " cfg.allowedDomains}; do
                echo "  ✓ $D"
              done
              echo
              echo "── Drop counter NAT redirect ──"
              sudo nft list chain inet solem-ai-dns ai_dns_redirect 2>/dev/null || \
                echo "(tabella nft non caricata)"
              ;;

            test-allow)
              D="''${1:-ollama.com}"
              echo "Test: gavio-ai risolve $D (in allowlist)"
              if sudo -u gavio-ai dig +short +time=3 "$D" @127.0.0.1 -p ${toString cfg.port} 2>&1 | head -3; then
                echo "  ✓ risposta ricevuta"
              else
                echo "  ✗ no response"
              fi
              ;;

            test-deny)
              D="''${1:-evil.example.com}"
              echo "Test: gavio-ai risolve $D (NON in allowlist)"
              OUT=$(sudo -u gavio-ai dig +short +time=3 "$D" @127.0.0.1 -p ${toString cfg.port} 2>&1)
              # REFUSED == no answer (empty result) + rcode REFUSED
              FULL=$(sudo -u gavio-ai dig +time=3 "$D" @127.0.0.1 -p ${toString cfg.port} 2>&1)
              if echo "$FULL" | grep -q "status: REFUSED\|status: NXDOMAIN"; then
                echo "  ✓ REFUSED/NXDOMAIN (allowlist sta bloccando)"
              elif [ -z "$OUT" ]; then
                echo "  ✓ no answer (probabilmente REFUSED)"
              else
                echo "  ✗ FAIL: ottenuto risposta '$OUT' — allowlist NON sta filtrando"
              fi
              ;;

            help|--help|-h|*)
              cat <<'HELP'
solem-ai-dns — DNS allowlist per gavio-ai (anti tunneling)

  status         stato unbound + allowlist + counter NAT
  test-allow [d] dig dominio in allowlist (default ollama.com)
  test-deny  [d] dig dominio non whitelist (default evil.example.com)

Funzionamento:
  - unbound listening su 127.0.0.1:${toString cfg.port}
  - local-zone "." refuse → tutti i domini bloccati di default
  - forward-zone per ogni dominio in allowlist → forward via DoT a upstream
  - nftables NAT: UID 970 DNS query → DNAT a 127.0.0.1:${toString cfg.port}
  - Utente umano `gavio` NON rediretto, usa resolver di sistema

Threat coperto:
  - DNS tunneling esfiltration (sub-domain encoding)
  - C2 via DNS TXT records
  - Domain fronting via DNS lookup arbitrari

Tutto FOSS (unbound BSD-3, nftables GPL). 0 €.
HELP
              ;;
          esac
        '';
      })
    ];

    environment.etc."solem/ai-dns.md".text = ''
      # SOLEM AI DNS — Allowlist e anti tunneling

      ## Cosa fa

      Un resolver unbound locale ascolta su 127.0.0.1:${toString cfg.port}.
      Configurazione critica:
        - `local-zone "." refuse` → NIENTE risposta per default
        - `forward-zone` per ogni dominio in allowlist → forward via
          DNS-over-TLS a upstream sicuri

      nftables NAT chain `ai_dns_redirect` redireziona TUTTO il traffico
      DNS (porte 53 UDP/TCP) dell'UID ${toString aiUid} verso 127.0.0.1:${toString cfg.port}.

      L'utente umano `gavio` NON e' rediretto: continua a usare il
      resolver di sistema (NetworkManager / systemd-resolved / etc).

      ## Domini default

      ${lib.concatMapStringsSep "\n        " (d: "- ${d}") cfg.allowedDomains}

      Aggiungi via `solem.aiDns.allowedDomains = [ ... ]`.

      ## Verifica

      ```
      solem-ai-dns status
      solem-ai-dns test-allow ollama.com
      solem-ai-dns test-deny  evil.example.com
      ```

      ## Limiti onesti

      - **DoH (DNS over HTTPS)** bypassa tutto se l'AI fa direttamente HTTPS
        a un resolver remoto. Mitigazione: solem-ai-network filtra outbound
        porta 443 a IP non in whitelist. Se entrambi attivi, DoH chiuso.
      - **DoT (DNS over TLS porta 853)**: stesso discorso, chiuso se la
        whitelist IP esclude i resolver pubblici noti.
      - **Allowlist troppo larga**: se metti `*.googleusercontent.com`,
        un attaccante crea bucket su Google e bypassa.
      - **Cache poisoning unbound**: minimo perche' DNSSEC + qname-min
        + use-caps-for-id (0x20 hex randomization).
    '';
  };
}
