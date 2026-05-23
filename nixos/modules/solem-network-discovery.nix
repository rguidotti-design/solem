{ config, pkgs, lib, ... }:

# SOLEM NETWORK DISCOVERY — Avahi mDNS + autodiscovery NAS/printer SMB/NFS.
#
# Single responsibility: SOLO Avahi + browser per scoprire device sulla
# LAN. CLI `solem-discover` per inventory.
#
# Discovery automatico:
#   - mDNS (.local hostnames + servizi pubblicati)
#   - SMB/CIFS (router Windows + NAS)
#   - NFS exports
#   - IPP printers
#   - SSH boxes

let
  cfg = config.solem.networkDiscovery;

  discoverCli = pkgs.writeShellApplication {
    name = "solem-discover";
    runtimeInputs = with pkgs; [ avahi samba nfs-utils coreutils ];
    text = ''
      ACTION="''${1:-all}"
      case "$ACTION" in
        all)
          echo "── mDNS hosts ──"
          avahi-browse -alrt 2>/dev/null | grep -E "^=" | awk '{print "  " $7 " (" $6 ") → " $4}' | sort -u | head -30 || true
          echo
          echo "── SMB shares ──"
          smbtree -N 2>/dev/null | head -30 || echo "  (nessuna)"
          echo
          echo "── NFS exports ──"
          for host in $(avahi-browse -alrt -p 2>/dev/null | grep _nfs._tcp | awk -F';' '{print $7}' | sort -u); do
            echo "  $host:"
            showmount -e "$host" 2>/dev/null | tail -n +2 | head -5 || true
          done
          echo
          echo "── Stampanti IPP ──"
          avahi-browse -alrt -p 2>/dev/null | grep _ipp._tcp | awk -F';' '{print "  " $4 " → " $7}' | sort -u | head -10 || true
          ;;
        hosts|mdns)
          avahi-browse -alrt 2>/dev/null | grep -E "^=" | awk '{print $7, $4, "(" $6 ")"}' | sort -u
          ;;
        smb|samba)
          smbtree -N 2>/dev/null
          ;;
        printers)
          avahi-browse -alrt -p 2>/dev/null | grep _ipp | awk -F';' '{print $4, "→", $7}' | sort -u
          ;;
        *)
          echo "solem-discover — esplora la rete locale"
          echo
          echo "  solem-discover all          mDNS + SMB + NFS + IPP"
          echo "  solem-discover hosts        solo mDNS hostnames"
          echo "  solem-discover smb          Windows shares"
          echo "  solem-discover printers     IPP stampanti"
          ;;
      esac
    '';
  };
in {
  options.solem.networkDiscovery = {
    enable = lib.mkEnableOption "Avahi mDNS + browser SMB/NFS";

    publishServices = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Pubblica i servizi SOLEM via mDNS (es. _solem._tcp port 8001)";
    };
  };

  config = lib.mkIf cfg.enable {
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      nssmdns6 = true;
      openFirewall = true;
      publish = lib.mkIf cfg.publishServices {
        enable = true;
        addresses = true;
        domain = true;
        userServices = true;
        workstation = true;
      };
      extraServiceFiles.solem = lib.mkIf cfg.publishServices ''
        <?xml version="1.0" standalone='no'?>
        <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
        <service-group>
          <name replace-wildcards="yes">SOLEM API on %h</name>
          <service>
            <type>_http._tcp</type>
            <port>8001</port>
            <txt-record>path=/solem/manifest</txt-record>
          </service>
        </service-group>
      '';
    };

    environment.systemPackages = with pkgs; [
      discoverCli avahi samba nfs-utils
    ];
  };
}
