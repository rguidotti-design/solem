{ config, pkgs, lib, ... }:

# SOLEM HPC — Slurm controller/worker, opt-in.
#
# Single responsibility: SOLO orchestrare Slurm (controller + slurmd) +
# munge per auth. Niente provisioning utenti HPC (Step 1+).
#
# Architettura:
#   - Single-box (Beelink): slurmctld + slurmd su stesso host (queue locale)
#   - Multi-node:           slurmctld solo su gateway, slurmd su ogni worker
#
# 100% FOSS (Slurm GPL, munge GPL), 0 €.

let
  cfg = config.solem.hpc;
in {
  options.solem.hpc = {
    enable = lib.mkEnableOption "Slurm HPC scheduler (controller + worker)";

    role = lib.mkOption {
      type = lib.types.enum [ "controller" "worker" "both" ];
      default = "both";
      description = "controller=solo slurmctld · worker=solo slurmd · both=entrambi (single-box)";
    };

    clusterName = lib.mkOption {
      type = lib.types.str;
      default = "solem-cluster";
    };

    controlMachine = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "Hostname del nodo che ospita slurmctld";
    };

    partitions = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      default = {
        default = { Nodes = "ALL"; Default = "YES"; MaxTime = "INFINITE"; State = "UP"; };
      };
      description = "Partition Slurm";
    };

    nodes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "${config.networking.hostName} CPUs=1 RealMemory=2048 State=UNKNOWN" ];
      description = "Definizioni nodi Slurm (NodeName=... CPUs=... RealMemory=...)";
    };
  };

  config = lib.mkIf cfg.enable {
    services.munge.enable = true;

    services.slurm = {
      enable = true;
      clusterName = cfg.clusterName;
      controlMachine = cfg.controlMachine;
      server.enable = cfg.role != "worker";
      client.enable = cfg.role != "controller";
      nodeName = cfg.nodes;
      partitionName = lib.mapAttrsToList (name: spec:
        "${name} ${lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "${k}=${toString v}") spec)}"
      ) cfg.partitions;
    };

    environment.systemPackages = with pkgs; [
      slurm
      munge
    ];

    # Firewall (Slurm: 6817 ctld, 6818 slurmd, 6819 dbd)
    networking.firewall.allowedTCPPorts = [ 6817 6818 6819 ];
  };
}
