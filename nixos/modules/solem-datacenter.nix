{ config, pkgs, lib, ... }:

# SOLEM DATA CENTER — tool IPMI/Redfish + sudo helper, opt-in.
#
# Single responsibility: SOLO installazione tool low-level per:
#   - ipmitool      (IPMI 1.5/2.0 via LAN)
#   - freeipmi      (alternativo, GPL)
#   - openbmc-tools (utility BMC)
#   - smartmontools (S.M.A.R.T. dischi)
#   - lm-sensors    (temp/fan locale)
#   - lldpd         (discovery topologia rete switch)
#
# Provisioning PXE/iPXE in modulo separato (solem-pxe.nix futuro).
# 100% FOSS, 0 €.

let
  cfg = config.solem.datacenter;
in {
  options.solem.datacenter = {
    enable = lib.mkEnableOption "Strumenti data center (IPMI/Redfish/SMART/LLDP)";

    enableLldp = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "lldpd daemon per discovery switch (mostra a quale switch sei connesso)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      ipmitool
      freeipmi
      smartmontools
      lm_sensors
      nvme-cli
      ethtool
      iproute2
      tcpdump
      mtr
    ];

    # LLDP discovery (vedi quale switch porta sei collegato)
    services.lldpd = lib.mkIf cfg.enableLldp {
      enable = true;
    };

    # Credenziali BMC vivono in dir 0700 root
    systemd.tmpfiles.rules = [
      "d /var/lib/solem-secrets/bmc 0700 root root - -"
    ];

    # Permetti a gavio user di lanciare ipmitool/ipmi-* via sudo NOPASSWD
    # (il PATH del comando è dinamico, scegli quello del pacchetto)
    security.sudo.extraRules = [{
      users = [ "gavio" ];
      commands = [
        { command = "${pkgs.ipmitool}/bin/ipmitool"; options = [ "NOPASSWD" ]; }
        { command = "${pkgs.freeipmi}/bin/ipmi-power"; options = [ "NOPASSWD" ]; }
        { command = "${pkgs.freeipmi}/bin/ipmi-sensors"; options = [ "NOPASSWD" ]; }
      ];
    }];
  };
}
