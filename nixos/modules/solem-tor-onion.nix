{ config, pkgs, lib, ... }:

# SOLEM TOR ONION — Step 29: hidden service opt-in per accesso anonimo.
#
# Single responsibility: SOLO Tor daemon + hidden service config.
# Espone SSH + GAVIO API come .onion address, accessibili da chiunque
# usi Tor (Browser, Orbot, ...) SENZA esporre IP pubblico.
#
# Threat coperto:
#   - Network surveillance: ISP/governo vede traffic encrypted MA non puo'
#     vedere CHI accede a SOLEM (relay Tor offusca).
#   - IP geolocation: peer remoti accedono via .onion, mai vedono IP reale.
#   - Censorship: paesi che bloccano IP/DNS specifici non possono bloccare
#     .onion (sono nella darknet Tor).
#   - Coordination server vendor lock-in: alternativa a Tailscale (proprietario)
#     o WireGuard (richiede port forward). Tor non richiede nulla.
#
# Differenza con WireGuard mesh (Step 24):
#   - WireGuard: VPN end-to-end, performance alta, IP rivelato al peer.
#   - Tor onion: anonimato, latenza ~300-500ms, IP nascosto da TUTTI.
#   - Sono COMPLEMENTARI: usa WG per uso normale, Tor per anonymous research.
#
# Tutto FOSS (Tor BSD-3). 0 €.

let
  cfg = config.solem.torOnion;
in {
  options.solem.torOnion = {
    enable = lib.mkEnableOption "Tor onion service per SSH/GAVIO accesso anonimo";

    services = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          port = lib.mkOption {
            type = lib.types.int;
            description = "Porta del .onion address (es. 22 per SSH)";
          };
          targetPort = lib.mkOption {
            type = lib.types.int;
            description = "Porta locale del servizio (es. 22 per SSH locale)";
          };
          targetAddr = lib.mkOption {
            type = lib.types.str;
            default = "127.0.0.1";
            description = "Indirizzo locale del servizio";
          };
        };
      });
      default = {
        ssh = { port = 22; targetPort = 22; };
        gavio-api = { port = 80; targetPort = 8000; };
      };
      description = "Mappa nome → port mapping del hidden service";
    };

    authorizedClients = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "alice:descriptor:x25519:...keyfile" ];
      description = ''
        Client authorization v3 onion (opzionale).
        Senza: .onion address pubblico (chiunque conosce l'address entra).
        Con: solo client con key autorizzata possono risolverlo.
      '';
    };

    relayBridge = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Configura SOLEM anche come bridge Tor per altri utenti.
        Aiuta network Tor (più exit node = più anonimato per tutti).
        Default off: usa solo come client.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.tor = {
      enable = true;
      enableGeoIP = true;
      client.enable = false;  # SOLEM e' SERVER hidden service, non client

      relay = lib.mkIf cfg.relayBridge {
        enable = true;
        role = "bridge";
      };

      settings = {
        # Hidden service v3 (cifratura corrente, 56-char .onion)
        HiddenServiceDir = "/var/lib/tor/solem-onion";
        HiddenServiceVersion = 3;
        HiddenServicePort = lib.mapAttrsToList (name: svc:
          "${toString svc.port} ${svc.targetAddr}:${toString svc.targetPort}"
        ) cfg.services;

        # Client authorization opt-in
        HiddenServiceAuthorizeClient = lib.mkIf (cfg.authorizedClients != []) (
          lib.concatStringsSep "," cfg.authorizedClients
        );

        # Privacy hardening
        SafeLogging = 1;
        ClientUseIPv4 = 1;
        ClientUseIPv6 = 0;  # IPv6 puo' leakare info
      };
    };

    # tmpfiles per hidden service dir
    systemd.tmpfiles.rules = [
      "d /var/lib/tor 0700 tor tor - -"
      "d /var/lib/tor/solem-onion 0700 tor tor - -"
    ];

    environment.systemPackages = with pkgs; [
      tor
      (pkgs.writeShellApplication {
        name = "solem-tor";
        runtimeInputs = with pkgs; [ coreutils tor systemd ];
        text = ''
          ACTION="''${1:-status}"

          case "$ACTION" in
            status)
              echo "── SOLEM Tor Onion ──"
              if systemctl is-active tor.service >/dev/null 2>&1; then
                echo "Daemon: ATTIVO"
              else
                echo "Daemon: spento"
                exit 1
              fi
              echo
              echo "── Hidden service address (.onion) ──"
              ONION="/var/lib/tor/solem-onion/hostname"
              if [ -f "$ONION" ]; then
                ADDR=$(sudo cat "$ONION")
                echo "  $ADDR"
                echo
                echo "── Port mapping ──"
                ${lib.concatStringsSep "\n              " (lib.mapAttrsToList (name: svc:
                  "echo \"  ${name}: $ADDR:${toString svc.port} → 127.0.0.1:${toString svc.targetPort}\" || true"
                ) cfg.services)}
              else
                echo "(hidden service non ancora inizializzato — aspetta primo boot Tor)"
              fi
              echo
              echo "── Tor circuit info ──"
              echo "GETINFO circuit-status" | sudo nc -q 1 127.0.0.1 9051 2>/dev/null | head -10 || echo "(control port non configurato)"
              ;;

            address|hostname)
              if [ -f /var/lib/tor/solem-onion/hostname ]; then
                sudo cat /var/lib/tor/solem-onion/hostname
              else
                echo "Hidden service non ancora pronto. Aspetta 1-2 min dopo boot Tor."
              fi
              ;;

            backup)
              # Backup chiavi hidden service (CRITICO)
              DEST="''${1:?Usage: solem-tor backup <dest-path>}"
              if [ -d /var/lib/tor/solem-onion ]; then
                sudo tar -czf "$DEST" -C /var/lib/tor solem-onion
                sudo chmod 600 "$DEST"
                echo "✓ Backup hidden service in $DEST"
                echo "  ⚠ CONTIENE chiave privata onion. Tratta come segreto MAX."
                echo "  Salva su USB esterno offline."
              fi
              ;;

            restore)
              SRC="''${1:?Usage: solem-tor restore <backup-tar>}"
              sudo systemctl stop tor.service
              sudo tar -xzf "$SRC" -C /var/lib/tor
              sudo chown -R tor:tor /var/lib/tor/solem-onion
              sudo systemctl start tor.service
              echo "✓ Restored. .onion address dovrebbe essere quello originale."
              ;;

            test)
              ADDR=$(sudo cat /var/lib/tor/solem-onion/hostname 2>/dev/null)
              if [ -z "$ADDR" ]; then
                echo "Hidden service non pronto"
                exit 1
              fi
              echo "Test access via Tor (richiede torsocks installato)..."
              torsocks curl -s "http://$ADDR/" -m 30 2>&1 | head -5 || \
                echo "(test fail — usa Tor Browser: http://$ADDR)"
              ;;

            help|--help|-h|*)
              cat <<'HELP'
solem-tor — Tor onion service per accesso anonimo

  status       daemon + .onion address + port mapping
  address      stampa solo .onion hostname
  backup <f>   backup chiavi hidden service (CRITICO)
  restore <f>  ripristina .onion address da backup
  test         curl test via torsocks

Servizi esposti come .onion:
HELP
              for name in ${lib.concatStringsSep " " (lib.attrNames cfg.services)}; do
                echo "  - $name"
              done
              cat <<'HELP'

Workflow uso:
  1. Aspetta 1-2 min dopo boot per init hidden service
  2. solem-tor address       → ottieni xxxx.onion
  3. solem-tor backup /media/usb/onion-backup.tgz  (BACKUP CRITICO!)
  4. Da client (Tor Browser / Orbot / torsocks):
     ssh gavio@xxxx.onion -p 22
     curl http://xxxx.onion/ (GAVIO API)

Threat coperto:
  - Network surveillance (ISP, governo): IP nascosto
  - Geolocation tracking: relay Tor offusca
  - Censorship: .onion non blockable via IP/DNS
  - No port forwarding richiesto (vs WireGuard Step 24)

Latenza: ~300-500ms (vs WireGuard <50ms). Per task no-realtime.
HELP
              ;;
          esac
        '';
      })
    ];

    environment.etc."solem/tor-onion.md".text = ''
      # SOLEM Tor Onion (Step 29)

      Hidden service Tor v3 per esporre SSH + GAVIO API come .onion address.

      ## Threat coperto
      - **Network surveillance** (ISP, governo): vede TLS encrypted ma non
        CHI accede a SOLEM (Tor relay offuscano).
      - **Geolocation**: IP server SOLEM mai rivelato al peer.
      - **Censorship**: .onion non blockable via IP/DNS (darknet Tor).
      - **No port forward**: a differenza WireGuard, Tor funziona dietro
        NAT/CGNAT (perforazione automatica via relay).

      ## Differenza con WireGuard mesh (Step 24)

      | Aspetto | WireGuard | Tor onion |
      |---|---|---|
      | Latenza | <50ms | 300-500ms |
      | Performance | Alta | Bassa |
      | Anonimato IP | Peer vede tuo IP | Peer NON vede IP |
      | Port forward | Richiesto router | Non richiesto |
      | Censorship resistance | Bassa | Alta |
      | Use case | Daily remote work | Anonymous access |

      Complementari, non sostituti.

      ## Setup

      ```nix
      solem.torOnion = {
        enable = true;
        services = {
          ssh = { port = 22; targetPort = 22; };
          gavio-api = { port = 80; targetPort = 8000; };
        };
      };
      ```

      Dopo boot:
      ```bash
      solem-tor address              # xxxxxxxxxxxxxxxx.onion
      solem-tor backup /media/usb/.tgz   # ⚠ CRITICO
      ```

      Da client (Tor Browser / Orbot Android):
      ```
      http://xxxxxxxxxxxxxxxx.onion/        # GAVIO API
      ssh -o ProxyCommand='nc -X 5 -x 127.0.0.1:9050 %h %p' gavio@xxxxxxxxxxxxxxxx.onion
      ```

      ## Client authorization v3 (paranoid)

      Default: chiunque conosce .onion address entra. Per restrizione:
      ```nix
      solem.torOnion.authorizedClients = [
        "alice:descriptor:x25519:KEY..."
      ];
      ```
      Solo client con `KEY` corrispondente possono risolvere l'address.

      ## Limiti onesti
      - Performance: 300-500ms latency, throughput <5MB/s tipico.
      - .onion address e' DERIVATO da chiave privata. Backup essenziale.
        Senza backup, ogni reinstall SOLEM genera address NUOVO → tutti
        i bookmark client da aggiornare.
      - Tor exit node compromessi MAI vedono traffico encrypted (e2e tunnel),
        ma sniffano metadata (volumi, timing). Mitigazione: padding traffic.
      - Bridge mode (`relayBridge=true`) aumenta consumo banda (~10-50GB/mese).
    '';
  };
}
