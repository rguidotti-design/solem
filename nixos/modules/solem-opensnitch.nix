{ config, pkgs, lib, ... }:

# SOLEM OPENSNITCH — per-app firewall interattivo (Little Snitch FOSS).
#
# Single responsibility: SOLO orchestrare daemon opensnitch + GUI.
# Niente regole hardcoded (l'utente impara prompt-by-prompt al primo
# avvio di ogni app).
#
# 100% FOSS, costo 0 €. Filosofia: "ogni app deve chiedere il permesso
# per uscire in rete" → zero trust app-level.

let
  cfg = config.solem.opensnitch;
in {
  options.solem.opensnitch = {
    enable = lib.mkEnableOption "Per-app firewall interattivo (opensnitch)";

    defaultAction = lib.mkOption {
      type = lib.types.enum [ "allow" "deny" ];
      default = "deny";
      description = "Azione default se utente non risponde entro timeout";
    };

    promptTimeout = lib.mkOption {
      type = lib.types.int;
      default = 15;
      description = "Secondi timeout dialog";
    };
  };

  config = lib.mkIf cfg.enable {
    services.opensnitch = {
      enable = true;
      settings = {
        DefaultAction = cfg.defaultAction;
        DefaultDuration = "always";
        InterceptUnknown = false;
        ProcMonitorMethod = "ebpf";
        LogLevel = 2;
        Firewall = "iptables";
        Stats = {
          MaxEvents = 150;
          MaxStats = 25;
        };
        Ebpf.ModulesPath = "${pkgs.opensnitch}/etc/opensnitchd/opensnitch-procs.o";
      };
    };

    # GUI client (deve girare nella sessione user)
    environment.systemPackages = with pkgs; [ opensnitch-ui ];

    systemd.user.services.opensnitch-ui = {
      description = "OpenSnitch UI client";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.opensnitch-ui}/bin/opensnitch-ui";
        Restart = "on-failure";
      };
    };
  };
}
