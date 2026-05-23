{ config, pkgs, lib, ... }:

# SOLEM PRIVACY NETWORK — I2P + Yggdrasil + Tor opt-in (oltre solem-tor.nix).
#
# Single responsibility: SOLO installazione client privacy network
# alternativi. Configurazione minima (ascolto SOCKS proxy + helper).
#
# Vantaggi:
#   - I2P: rete anonima end-to-end (mail anonima, eepsites)
#   - Yggdrasil: mesh IPv6 self-routing peer-to-peer
#   - Tor: già in solem-tor.nix
#
# Tutti FOSS, costo 0 €.

let
  cfg = config.solem.privacyNetwork;
in {
  options.solem.privacyNetwork = {
    i2p = {
      enable = lib.mkEnableOption "I2P (Invisible Internet Project)";
      enableEepsite = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Espone il tuo nodo I2P come eepsite";
      };
    };

    yggdrasil = {
      enable = lib.mkEnableOption "Yggdrasil mesh IPv6 self-routing";
      publicPeers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          # Public peer list https://publicpeers.neilalexander.dev/
          "tls://ygg-uk.incognet.io:8089"
          "tls://95.216.5.243:18836"
        ];
      };
    };

    iodine = lib.mkEnableOption "iodine (DNS tunneling — bypass captive portal)";
  };

  config = lib.mkMerge [
    # I2P
    (lib.mkIf cfg.i2p.enable {
      services.i2pd = {
        enable = true;
        proto = {
          http = {
            enable = true;
            address = "127.0.0.1";
            port = 7070;
          };
          httpProxy = {
            enable = true;
            address = "127.0.0.1";
            port = 4444;
          };
          socksProxy = {
            enable = true;
            address = "127.0.0.1";
            port = 4447;
          };
        };
      };
      environment.systemPackages = with pkgs; [ i2pd ];

      environment.etc."solem/i2p.md".text = ''
        # SOLEM I2P

        Proxy HTTP:    127.0.0.1:4444 → naviga .i2p
        Proxy SOCKS:   127.0.0.1:4447 → tunnel app
        Web console:   http://127.0.0.1:7070

        Test: curl --proxy http://127.0.0.1:4444 http://i2p-projekt.i2p/
      '';
    })

    # Yggdrasil
    (lib.mkIf cfg.yggdrasil.enable {
      services.yggdrasil = {
        enable = true;
        openMulticastPort = true;
        settings = {
          Peers = cfg.yggdrasil.publicPeers;
          IfName = "ygg0";
          MulticastInterfaces = [{
            Regex = ".*";
            Beacon = true;
            Listen = true;
            Port = 0;
          }];
        };
      };

      environment.etc."solem/yggdrasil.md".text = ''
        # SOLEM Yggdrasil

        Yggdrasil è una mesh IPv6 self-routing peer-to-peer. Niente DNS
        centrale, niente exit, niente censure. Ogni nodo è equal.

        Il tuo IPv6 yggdrasil:
          ip addr show ygg0

        Altri nodi sulla mesh:
          yggdrasilctl getPeers

        Provi a pingare un nodo conosciuto:
          ping6 200:abcd:...
      '';
    })

    # iodine DNS tunnel
    (lib.mkIf cfg.iodine {
      environment.systemPackages = with pkgs; [ iodine ];
      environment.etc."solem/iodine.md".text = ''
        # SOLEM iodine

        Tunnel IP-over-DNS per bypass captive portal aeroporti/hotel.
        Richiede un server iodine accessibile sotto un subdomain
        delegato (NS your-server.example.com).

        Client: iodine -P pass tunnel.example.com
      '';
    })
  ];
}
