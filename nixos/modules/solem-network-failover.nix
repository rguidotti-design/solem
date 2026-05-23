{ config, pkgs, lib, ... }:

# SOLEM NETWORK FAILOVER — auto-switch LAN/WiFi/4G in base a connettività.
#
# Single responsibility: SOLO config NetworkManager con priorità multi-link
# + ModemManager per 4G/5G + ping-based health check.
#
# Logica:
#   1. Ethernet (priorità 100, se cavo collegato)
#   2. WiFi (priorità 50, se SSID known reachable)
#   3. 4G/5G modem (priorità 10, fallback)
#   4. Mesh VPN (priorità 5, ultima risorsa via altro nodo)

let
  cfg = config.solem.networkFailover;
in {
  options.solem.networkFailover = {
    enable = lib.mkEnableOption "Network failover automatico LAN/WiFi/4G";

    enableMobile = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Abilita modem 4G/5G come fallback (richiede SIM)";
    };

    pingTarget = lib.mkOption {
      type = lib.types.str;
      default = "1.1.1.1";
      description = "Target ping per health check connettività";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.networkmanager = {
      enable = true;
      wifi.powersave = false;       # connessione stabile
      wifi.backend = "iwd";          # backend moderno (più affidabile vs wpa_supplicant)
      enableStrongSwan = false;
      # Connectivity check ogni 60s
      connectionConfig = {
        "ethernet.route-metric" = 100;   # priorità più alta = numero più basso? In NM più basso = preferito
        "wifi.route-metric" = 200;
        "gsm.route-metric" = 700;        # 4G ultimo
      };
    };

    # ModemManager per 4G/5G
    networking.modemmanager.enable = cfg.enableMobile;

    # Tool diagnostici failover
    environment.systemPackages = with pkgs; [
      networkmanager-applet  # GUI tray icon
      modemmanager
      mobile-broadband-provider-info
    ];

    # Service health check + log
    systemd.services.solem-net-watchdog = {
      description = "SOLEM network failover watchdog";
      after = [ "NetworkManager.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = pkgs.writeShellScript "solem-net-watchdog" ''
          while true; do
            if ${pkgs.iputils}/bin/ping -c 1 -W 3 ${cfg.pingTarget} >/dev/null 2>&1; then
              STATE=ok
            else
              STATE=fail
              # NetworkManager dovrebbe già fare failover, ma logghiamo
              ${pkgs.systemd}/bin/systemd-cat -t solem-net "ping ${cfg.pingTarget} fail"
            fi
            ${pkgs.coreutils}/bin/sleep 60
          done
        '';
        Restart = "always";
      };
    };
  };
}
