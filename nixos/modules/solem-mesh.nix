{ config, pkgs, lib, ... }:

let
  cfg = config.solem.mesh;
in {
  # ──────────────────────────────────────────────────────────────────────
  # SOLEM MESH — VPN WireGuard tra device che ospitano SOLEM
  # ──────────────────────────────────────────────────────────────────────
  # Filosofia: ogni device dell'utente che monta SOLEM (telefono futuro,
  # watch, smartglass, secondo server) entra automaticamente in una mesh
  # WireGuard privata. I device si parlano solo tra loro, fuori da Internet
  # pubblico, senza passare per cloud di terze parti (no Tailscale, no Zerotier).
  #
  # Modello:
  #   - Un nodo è "coordinator" (di solito il server SOLEM principale)
  #   - Altri nodi sono "peer" e si pairing-ano con il coordinator via PIN
  #     BBM-style 8 hex (vedi spec founder messaging)
  #   - Subnet privata 10.42.0.0/24 (configurabile)
  #   - Discovery via DNS interno: phone.solem.mesh, watch.solem.mesh, ecc.
  #
  # Step 0: stub disabilitato di default (no device da paired).
  # Step 1+: attivo sul Beelink coordinator.
  # Step 3+: pairing automatico nuovi device via PIN/QR.

  options.solem.mesh = {
    enable = lib.mkEnableOption "VPN WireGuard mesh tra device SOLEM";

    role = lib.mkOption {
      type = lib.types.enum [ "coordinator" "peer" ];
      default = "coordinator";
      description = ''
        Ruolo del nodo nella mesh.
        - coordinator: registry dei peer, normalmente il server SOLEM principale
        - peer: device secondario (laptop, secondo server)
      '';
    };

    subnet = lib.mkOption {
      type = lib.types.str;
      default = "10.42.0.0/24";
      description = "Subnet privata della mesh SOLEM (RFC1918).";
    };

    nodeAddress = lib.mkOption {
      type = lib.types.str;
      default = "10.42.0.1/24";
      description = "Indirizzo WireGuard di questo nodo dentro la mesh.";
    };

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 51820;
      description = "Porta UDP WireGuard.";
    };

    peers = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption { type = lib.types.str; };
          publicKey = lib.mkOption { type = lib.types.str; };
          allowedIPs = lib.mkOption { type = lib.types.listOf lib.types.str; };
          endpoint = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
          persistentKeepalive = lib.mkOption { type = lib.types.int; default = 25; };
        };
      });
      default = [ ];
      description = ''
        Lista dei peer della mesh. Step 0: vuoto (no device).
        Step 1+: popolato dinamicamente dal pairing API in solem-api.
      '';
    };

    coordinatorEndpoint = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Endpoint del coordinator (host:port). Obbligatorio se role="peer".
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Interfaccia WireGuard "wg-solem"
    networking.wireguard.interfaces.wg-solem = {
      ips = [ cfg.nodeAddress ];
      listenPort = if cfg.role == "coordinator" then cfg.listenPort else null;
      privateKeyFile = "/var/lib/wireguard/wg-solem.key";

      # Step 0: peers vuoto → mesh inerte ma interface up.
      # Step 1+: pairing API popola questa lista dinamicamente.
      peers = map (p: {
        inherit (p) publicKey allowedIPs persistentKeepalive;
        endpoint = p.endpoint;
      }) cfg.peers;
    };

    # Firewall: apri porta UDP WireGuard (solo se coordinator)
    networking.firewall.allowedUDPPorts =
      lib.mkIf (cfg.role == "coordinator") [ cfg.listenPort ];

    # Genera chiave privata al primo boot se manca (gestione idempotente)
    systemd.services.solem-mesh-keygen = {
      description = "Genera chiave WireGuard SOLEM se mancante";
      wantedBy = [ "multi-user.target" ];
      before = [ "wireguard-wg-solem.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /var/lib/wireguard
        chmod 700 /var/lib/wireguard
        if [ ! -f /var/lib/wireguard/wg-solem.key ]; then
          umask 077
          ${pkgs.wireguard-tools}/bin/wg genkey \
            | tee /var/lib/wireguard/wg-solem.key \
            | ${pkgs.wireguard-tools}/bin/wg pubkey \
            > /var/lib/wireguard/wg-solem.pub
          chmod 600 /var/lib/wireguard/wg-solem.key
          chmod 644 /var/lib/wireguard/wg-solem.pub
        fi
      '';
    };

    # Tool WireGuard sempre presenti per debug (wg, wg-quick)
    environment.systemPackages = with pkgs; [ wireguard-tools ];

    # DNS interno: risolvi <nome>.solem.mesh → IP del peer.
    # Step 0: stub statico. Step 2: integrazione con pairing API.
    services.dnsmasq = {
      enable = lib.mkDefault false;  # attivare solo su coordinator quando peers esistono
      settings = {
        domain-needed = true;
        bogus-priv = true;
        local = "/solem.mesh/";
        domain = "solem.mesh";
        expand-hosts = true;
      };
    };
  };
}
