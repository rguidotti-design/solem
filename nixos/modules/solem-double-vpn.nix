{ config, pkgs, lib, ... }:

let
  cfg = config.solem.doubleVpn;
in {
  # ──────────────────────────────────────────────────────────────────────
  # SOLEM DOUBLE-VPN — encapsulamento a 2 layer
  # ──────────────────────────────────────────────────────────────────────
  #
  # Layer 1 (INTERNO): mesh WireGuard tra device dell'utente (gestita da
  #                    solem-mesh.nix). Traffico inter-device cifrato.
  #
  # Layer 2 (ESTERNO): WireGuard verso server esterno (self-host VPS o
  #                    nodo SOLEM remoto). Tutto il traffico outbound
  #                    verso Internet pubblico passa qui.
  #
  # Effetto: traffico Internet che esce dal tuo device = doppiamente cifrato:
  #   client → mesh (peer SOLEM) → tunnel esterno → Internet
  #
  # Default: OFF (richiede config peer esterno). Opt-in via:
  #   solem.doubleVpn.enable = true;
  #   solem.doubleVpn.externalPeer = { ... };
  #
  # FILOSOFIA single-responsibility: questo modulo SOLO il tunnel esterno
  # (layer 2). Layer 1 mesh interno resta in solem-mesh.nix.

  options.solem.doubleVpn = {
    enable = lib.mkEnableOption "Doppio incapsulamento VPN (mesh + tunnel esterno)";

    externalInterface = lib.mkOption {
      type = lib.types.str;
      default = "wg-solem-out";
      description = "Nome interfaccia WireGuard per il tunnel esterno (layer 2).";
    };

    localAddress = lib.mkOption {
      type = lib.types.str;
      default = "10.43.0.2/32";
      description = "IP assegnato a questo client nel tunnel esterno.";
    };

    privateKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/wireguard/wg-solem-out.key";
      description = "Path della chiave privata (auto-generata al primo boot).";
    };

    externalPeer = lib.mkOption {
      type = lib.types.submodule {
        options = {
          publicKey = lib.mkOption { type = lib.types.str; default = ""; description = "Pub key del peer esterno"; };
          endpoint = lib.mkOption { type = lib.types.str; default = ""; description = "host:port del peer esterno"; };
          allowedIPs = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ "0.0.0.0/0" "::/0" ]; description = "Default: tutto outbound passa per il peer"; };
          persistentKeepalive = lib.mkOption { type = lib.types.int; default = 25; };
        };
      };
      default = { };
      description = "Configurazione peer VPN esterno (layer 2).";
    };

    dns = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "1.1.1.1" "9.9.9.9" ];
      description = "DNS server dietro il tunnel (override DNS sistema quando wg-solem-out è up).";
    };
  };

  config = lib.mkIf cfg.enable {
    # Pre-flight check: peer esterno deve essere configurato
    assertions = [{
      assertion = cfg.externalPeer.publicKey != "" && cfg.externalPeer.endpoint != "";
      message = ''
        solem.doubleVpn.enable = true richiede solem.doubleVpn.externalPeer.{publicKey,endpoint} configurati.
        Esempio:
          solem.doubleVpn.externalPeer = {
            publicKey = "abc123...="; # pub key del server
            endpoint = "vpn.tuo-dominio.it:51820";
          };
      '';
    }];

    # Keygen automatico (idempotente)
    systemd.services.solem-double-vpn-keygen = {
      description = "SOLEM double-VPN — genera chiave WireGuard layer 2";
      wantedBy = [ "multi-user.target" ];
      before = [ "wireguard-${cfg.externalInterface}.service" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      script = ''
        mkdir -p /var/lib/wireguard
        chmod 700 /var/lib/wireguard
        if [ ! -f ${cfg.privateKeyFile} ]; then
          umask 077
          ${pkgs.wireguard-tools}/bin/wg genkey \
            | tee ${cfg.privateKeyFile} \
            | ${pkgs.wireguard-tools}/bin/wg pubkey \
            > ${cfg.privateKeyFile}.pub
          chmod 600 ${cfg.privateKeyFile}
          chmod 644 ${cfg.privateKeyFile}.pub
        fi
      '';
    };

    # Interfaccia WireGuard layer 2 (outbound)
    networking.wireguard.interfaces.${cfg.externalInterface} = {
      ips = [ cfg.localAddress ];
      privateKeyFile = cfg.privateKeyFile;
      peers = [{
        inherit (cfg.externalPeer) publicKey allowedIPs persistentKeepalive;
        endpoint = cfg.externalPeer.endpoint;
      }];
    };

    # DNS via tunnel (no leak)
    networking.nameservers = cfg.dns;

    # Manifest leggibile dall'API SOLEM
    environment.etc."solem/double-vpn-config.json".text = builtins.toJSON {
      enabled = cfg.enable;
      layer1_mesh_interface = "wg-solem";     # da solem-mesh.nix
      layer2_external_interface = cfg.externalInterface;
      local_address = cfg.localAddress;
      external_endpoint = cfg.externalPeer.endpoint;
      dns = cfg.dns;
      pubkey_file = "${cfg.privateKeyFile}.pub";
    };
  };
}
