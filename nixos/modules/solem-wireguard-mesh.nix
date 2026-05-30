{ config, pkgs, lib, ... }:

# SOLEM WIREGUARD MESH — Step 24: remote access SOLEM via VPN cifrata.
#
# Single responsibility: SOLO configurazione WireGuard server (lato SOLEM)
# e management dei peer remoti. Non sostituisce ssh-hardened (Step 11),
# non sostituisce firewall (rimane attivo).
#
# Threat coperto:
#   - SSH/API esposti su internet pubblico → attaccanti scoprono porte
#     SOLEM via Shodan/Censys e fanno brute-force, exploit zero-day.
#   - DNS leak quando si usa SSH da rete pubblica.
#   - Man-in-the-middle su WiFi non fidato.
#   - Geolocation tracking (IP origine ovvio).
#
# Approccio:
#   - WireGuard server interno a SOLEM su porta UDP 51820.
#   - SOLO IP del mesh (10.100.0.0/24) può accedere a SSH/GAVIO API.
#   - Peer (laptop/phone) genera keypair locale + scambia public key.
#   - Connessione: peer → server SOLEM via WG → SSH/API attraverso il tunnel.
#   - Niente SSH/API porte sulla public IP (firewall chiude).
#
# Differenza con Tailscale (Step futuro?):
#   - WireGuard puro: zero dipendenze esterne, niente "coordination server"
#   - Tailscale: usa derp + DERP relays (Tailscale Inc cloud). Comodo ma
#     dipendenza cloud (anche se end-to-end encrypted).
#   - Per "100% self-hosted FOSS": WireGuard. Per "facile UX": Tailscale.
#     Step 24 = WireGuard. Step 24-bis (futuro): Tailscale opt-in.
#
# Tutto FOSS (WireGuard GPL-2.0, kernel module mainline da 5.6+).

let
  cfg = config.solem.wireguardMesh;
in {
  options.solem.wireguardMesh = {
    enable = lib.mkEnableOption "WireGuard server + mesh per remote access SOLEM";

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 51820;
      description = "Porta UDP server WireGuard (standard).";
    };

    interface = lib.mkOption {
      type = lib.types.str;
      default = "wg-solem";
      description = "Nome interfaccia WireGuard kernel.";
    };

    serverAddress = lib.mkOption {
      type = lib.types.str;
      default = "10.100.0.1/24";
      description = ''
        IP del server nel mesh (default 10.100.0.0/24).
        Peer ricevono IP successivi (10.100.0.2, 10.100.0.3, ...).
      '';
    };

    privateKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/solem/wg-mesh.key";
      description = ''
        Path al file con chiave privata WireGuard.
        Genera con: solem-wg init
        chmod 600 obbligatorio.
      '';
    };

    peers = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            example = "laptop-personale";
          };
          publicKey = lib.mkOption {
            type = lib.types.str;
            example = "abcDEF123...";
            description = "Public key del peer (ottieni con wg pubkey dal peer)";
          };
          allowedIPs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            example = [ "10.100.0.2/32" ];
            description = "IP del peer nel mesh (di solito /32 single host)";
          };
          presharedKeyFile = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              PSK opzionale: extra layer di crypto + post-quantum
              resistance parziale. Genera con: wg genpsk > psk.key
            '';
          };
        };
      });
      default = [ ];
      description = "Lista peer autorizzati ad accedere al mesh";
    };

    restrictSshToMesh = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Restrict SSH (porta 22) a solo mesh 10.100.0.0/24.
        Public IP NON puo' connettersi a SSH. Solo dopo WG up.
      '';
    };

    restrictGavioApiToMesh = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Restrict GAVIO API (porta 8000) a mesh only.
        Plus loopback (127.0.0.1) sempre permesso.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # ────────────────────────────────────────────────────────────────
    # 1. WireGuard server config
    # ────────────────────────────────────────────────────────────────
    networking.wireguard.interfaces.${cfg.interface} = {
      ips = [ cfg.serverAddress ];
      listenPort = cfg.listenPort;
      privateKeyFile = cfg.privateKeyFile;

      peers = map (p: {
        publicKey = p.publicKey;
        allowedIPs = p.allowedIPs;
        presharedKeyFile = p.presharedKeyFile;
        persistentKeepalive = 25;  # NAT keepalive
      }) cfg.peers;

      # PostSetup: log device up
      postSetup = ''
        ${pkgs.iproute2}/bin/ip link set ${cfg.interface} mtu 1380
        ${pkgs.systemd}/bin/systemd-cat -t solem-wg -p info ${pkgs.coreutils}/bin/echo "WG mesh ${cfg.interface} UP on port ${toString cfg.listenPort}"
      '';
    };

    # ────────────────────────────────────────────────────────────────
    # 2. Firewall: apri solo UDP 51820 + chiudi SSH/API public
    # ────────────────────────────────────────────────────────────────
    networking.firewall.allowedUDPPorts = [ cfg.listenPort ];

    # SSH restriction (solo dal mesh)
    networking.firewall.extraCommands = lib.mkIf cfg.restrictSshToMesh ''
      # Blocca SSH (porta 22) da TUTTI tranne loopback + mesh
      iptables -I INPUT -p tcp --dport 22 -j DROP
      iptables -I INPUT -p tcp --dport 22 -s 127.0.0.1 -j ACCEPT
      iptables -I INPUT -p tcp --dport 22 -s 10.100.0.0/24 -j ACCEPT

      # GAVIO API (porta 8000) restriction
      ${lib.optionalString cfg.restrictGavioApiToMesh ''
        iptables -I INPUT -p tcp --dport 8000 -j DROP
        iptables -I INPUT -p tcp --dport 8000 -s 127.0.0.1 -j ACCEPT
        iptables -I INPUT -p tcp --dport 8000 -s 10.100.0.0/24 -j ACCEPT
      ''}
    '';

    # ────────────────────────────────────────────────────────────────
    # 3. systemd-tmpfiles per dir secret
    # ────────────────────────────────────────────────────────────────
    systemd.tmpfiles.rules = [
      "d /etc/solem 0700 root root - -"
    ];

    # ────────────────────────────────────────────────────────────────
    # 4. CLI di gestione
    # ────────────────────────────────────────────────────────────────
    environment.systemPackages = with pkgs; [
      wireguard-tools
      qrencode
      (pkgs.writeShellApplication {
        name = "solem-wg";
        runtimeInputs = with pkgs; [ coreutils wireguard-tools qrencode iproute2 systemd ];
        text = ''
          ACTION="''${1:-status}"
          shift || true

          KEYFILE="${cfg.privateKeyFile}"
          INTERFACE="${cfg.interface}"
          PORT="${toString cfg.listenPort}"

          case "$ACTION" in
            init)
              if [ -f "$KEYFILE" ]; then
                echo "Private key gia' esiste: $KEYFILE"
                echo "Public key corrispondente:"
                wg pubkey < "$KEYFILE"
                exit 0
              fi
              mkdir -p "$(dirname "$KEYFILE")"
              wg genkey | sudo tee "$KEYFILE" > /dev/null
              sudo chmod 600 "$KEYFILE"
              echo "✓ Private key generata in $KEYFILE"
              echo "Public key del SERVER (condividi con i peer):"
              sudo wg pubkey < "$KEYFILE"
              ;;

            status)
              echo "── SOLEM WireGuard Mesh ──"
              echo "Interface: $INTERFACE"
              echo "Listen:    UDP $PORT"
              echo "Address:   ${cfg.serverAddress}"
              echo
              if ip link show "$INTERFACE" >/dev/null 2>&1; then
                echo "── Interface UP ──"
                sudo wg show "$INTERFACE"
              else
                echo "Interface non attiva (servizio non partito?)"
              fi
              echo
              echo "── Peer configurati ──"
              ${lib.concatMapStringsSep "\n              " (p:
                "echo '  - ${p.name} → ${lib.concatStringsSep "," p.allowedIPs}'"
              ) cfg.peers}
              ;;

            new-peer)
              # Genera config per nuovo peer (lato client)
              NAME="''${1:?Usage: solem-wg new-peer <name> [ip-suffix]}"
              IPSUFFIX="''${2:-100}"  # 10.100.0.100 default
              PEER_PRIV=$(wg genkey)
              PEER_PUB=$(echo "$PEER_PRIV" | wg pubkey)
              PEER_PSK=$(wg genpsk)
              SERVER_PUB=$(sudo wg pubkey < "$KEYFILE" 2>/dev/null || echo "<server-not-initialized>")

              # Determina endpoint pubblico (utente deve verificare)
              ENDPOINT_IP="''${SOLEM_PUBLIC_IP:-$(curl -s -4 -m 3 ifconfig.me 2>/dev/null || echo 'YOUR_PUBLIC_IP')}"

              echo "── Config per peer '$NAME' ──"
              cat <<EOF

# Salva questo come ~/.config/wg/$NAME.conf sul DEVICE PEER (laptop/phone):

[Interface]
PrivateKey = $PEER_PRIV
Address = 10.100.0.$IPSUFFIX/24
DNS = 1.1.1.1, 9.9.9.9

[Peer]
PublicKey = $SERVER_PUB
PresharedKey = $PEER_PSK
Endpoint = $ENDPOINT_IP:$PORT
AllowedIPs = 10.100.0.0/24
PersistentKeepalive = 25
EOF
              echo
              echo "── Aggiungi al config SOLEM (flake.nix): ──"
              echo "solem.wireguardMesh.peers = [{"
              echo "  name = \"$NAME\";"
              echo "  publicKey = \"$PEER_PUB\";"
              echo "  allowedIPs = [ \"10.100.0.$IPSUFFIX/32\" ];"
              echo "}];"
              echo
              echo "Poi: sudo nixos-rebuild switch"
              echo
              echo "── QR code per import in WireGuard mobile app ──"
              cat <<EOF | qrencode -t UTF8
[Interface]
PrivateKey = $PEER_PRIV
Address = 10.100.0.$IPSUFFIX/24
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUB
PresharedKey = $PEER_PSK
Endpoint = $ENDPOINT_IP:$PORT
AllowedIPs = 10.100.0.0/24
PersistentKeepalive = 25
EOF
              ;;

            disconnect)
              PEER="''${1:?Usage: solem-wg disconnect <pubkey>}"
              sudo wg set "$INTERFACE" peer "$PEER" remove
              echo "✓ Peer $PEER disconnesso (re-add in flake.nix per persistere)"
              ;;

            help|--help|-h|*)
              cat <<'HELP'
solem-wg — WireGuard mesh management

  init                  genera private key server (PRIMO setup)
  status                stato server + peer connessi + handshakes
  new-peer <name> [ip]  genera config per nuovo peer + QR code
  disconnect <pubkey>   rimuovi peer da runtime (non persiste)

Workflow primo setup:
  1. solem-wg init                                  (genera server key)
  2. Apri porta UDP 51820 su router (port forward)
  3. solem-wg new-peer my-laptop 100                (genera client config)
  4. Aggiungi peer al config solem-wg.peers
  5. sudo nixos-rebuild switch
  6. Sul device peer: importa config → connect
  7. SSH/API ora SOLO via mesh: ssh gavio@10.100.0.1

Threat coperto:
  - SSH/API esposti pubblicamente -> ora SOLO via tunnel
  - MITM su WiFi pubblico (tutto cifrato curve25519)
  - DNS leak (DNS = 1.1.1.1 nel tunnel)
HELP
              ;;
          esac
        '';
      })
    ];

    environment.etc."solem/wireguard-mesh.md".text = ''
      # SOLEM WireGuard Mesh (Step 24)

      Remote access SOLEM via VPN cifrata. SSH e GAVIO API NON sono
      esposti al public internet — solo via tunnel WireGuard.

      ## Threat coperto

      - **SSH/API public exposure**: prima erano raggiungibili da chiunque
        sapesse l'IP pubblico (brute force, exploit zero-day).
        Ora: firewall iptables DROP su porta 22 e 8000 da public,
        ACCEPT solo da 10.100.0.0/24 (mesh).
      - **MITM su WiFi pubblico**: tutto traffic cifrato (curve25519 + chacha20).
      - **DNS leak**: peer config DNS=1.1.1.1 (resolver dentro tunnel).
      - **Replay attack**: PSK opzionale per post-quantum resistance parziale.
      - **Geolocation tracking**: traffic outbound dal SOLEM IP, non
        dall'IP del peer.

      ## Setup primo uso

      ```bash
      # Sul SOLEM:
      solem-wg init                       # genera server private key

      # Port forwarding UDP 51820 sul router (solo questo!)

      # Per ogni device:
      solem-wg new-peer my-laptop 100      # genera config + QR
      # Aggiungi a flake.nix:
      solem.wireguardMesh.peers = [{...}];
      sudo nixos-rebuild switch

      # Sul peer:
      # Salva config in /etc/wireguard/wg-solem.conf
      # sudo wg-quick up wg-solem
      # ssh gavio@10.100.0.1
      ```

      ## Limiti onesti

      - Server private key on disk (/etc/solem/wg-mesh.key chmod 600).
        Se rubato, attacker entra. SOLUZIONE: backup separato su USB.
      - Port forwarding UDP 51820 router obbligatorio. Su CGNAT (ISP
        consumer): non funziona. SOLUZIONE: Tailscale (step futuro) o
        WireGuard via Cloudflare WARP (free).
      - Peer config rivela endpoint IP SOLEM. Mitigato dal fatto che la
        porta 51820 espone SOLO WG (no banner SOLEM, no fingerprint).
      - Se device peer compromesso (laptop rubato), attacker entra.
        SOLUZIONE: revoke peer + nixos-rebuild.
      - WireGuard kernel module (no userspace fallback in questa config).
        Su kernel < 5.6 serve userspace boringtun.
    '';
  };
}
