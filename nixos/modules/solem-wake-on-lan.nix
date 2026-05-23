{ config, pkgs, lib, ... }:

# SOLEM WAKE-ON-LAN — accendi i tuoi device da remoto (mesh-aware).
#
# Single responsibility: SOLO config WoL ricezione + CLI per invio
# magic packet. Niente integrazione cluster automatica (ma `solem-wol`
# legge da /solem/cluster/devices se disponibile).

let
  cfg = config.solem.wakeOnLan;

  wolCli = pkgs.writeShellApplication {
    name = "solem-wol";
    runtimeInputs = with pkgs; [ wakeonlan curl jq coreutils ];
    text = ''
      ACTION="''${1:-help}"
      case "$ACTION" in
        wake|on)
          shift
          TARGET="''${1:?Usage: solem-wol wake <mac|device-name>}"
          # Se inizia con xx:xx:xx, MAC diretto
          if [[ "$TARGET" =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
            wakeonlan "$TARGET"
            echo "Magic packet inviato a $TARGET"
          else
            # Cerca device_id nel cluster registry
            API="''${SOLEM_API_URL:-http://127.0.0.1:8001}"
            MAC=$(curl -fsS "$API/solem/cluster/devices" | jq -r ".[] | select(.device_id == \"$TARGET\") | .mac // empty")
            if [ -z "$MAC" ]; then
              echo "Device $TARGET non trovato nel cluster (o mac non registrato)"
              exit 1
            fi
            wakeonlan "$MAC"
            echo "Magic packet inviato a $TARGET ($MAC)"
          fi
          ;;
        list)
          API="''${SOLEM_API_URL:-http://127.0.0.1:8001}"
          curl -fsS "$API/solem/cluster/devices" | jq -r '.[] | "\(.device_id)\t\(.endpoint)\t\(.online)"'
          ;;
        *)
          echo "solem-wol — wake-on-LAN del cluster"
          echo
          echo "  solem-wol wake <mac|device-id>    invia magic packet"
          echo "  solem-wol list                    lista device cluster"
          ;;
      esac
    '';
  };
in {
  options.solem.wakeOnLan = {
    enable = lib.mkEnableOption "Wake-on-LAN ricezione + CLI invio";

    interfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "eth0" ];
      description = "Interfacce abilitate a ricevere magic packet";
    };
  };

  config = lib.mkIf cfg.enable {
    # Abilita WoL su tutte le interfacce listate
    networking.interfaces = lib.genAttrs cfg.interfaces (iface: {
      wakeOnLan.enable = true;
    });

    environment.systemPackages = with pkgs; [
      wakeonlan wolCli ethtool
    ];

    # Service per assicurare WoL abilitato anche dopo suspend
    systemd.services.solem-wol-keepalive = {
      description = "SOLEM — riarma WoL sulle NIC dopo resume";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" "suspend.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "wol-arm" ''
          ${lib.concatStringsSep "\n" (map (i:
            "${pkgs.ethtool}/bin/ethtool -s ${i} wol g 2>/dev/null || true"
          ) cfg.interfaces)}
        '';
      };
    };
  };
}
